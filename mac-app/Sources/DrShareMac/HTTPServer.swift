import Foundation
import Network

import DrShareShared
import DrShareWebAssets

final class HTTPServer: @unchecked Sendable {
    struct Configuration {
        let port: UInt16
        let urlsProvider: @Sendable () -> [String]
        let tokenProvider: @Sendable () -> String
        let bonjourService: NWListener.Service?
        let dropStore: DropStore
        let onServerError: @Sendable (String) -> Void
        let onBonjourUpdate: @Sendable (Bool, String?) -> Void
        let onTransferActivity: @Sendable (UploadActivity) -> Void
        let onDropAdded: @Sendable (DropRecord) -> Void
    }

    private let configuration: Configuration
    private let queue = DispatchQueue(label: "drshare.http-server")
    private var listener: NWListener?
    private var handlers: [UUID: ConnectionHandler] = [:]

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func start() throws {
        guard listener == nil else {
            return
        }

        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: configuration.port)!)
        listener.service = configuration.bonjourService

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }

        listener.stateUpdateHandler = { [configuration] state in
            if case let .failed(error) = state {
                print("[drshare] listener failed: \(error.localizedDescription)")
                configuration.onServerError(error.localizedDescription)
            }
        }

        listener.serviceRegistrationUpdateHandler = { [configuration] change in
            switch change {
            case let .add(endpoint):
                configuration.onBonjourUpdate(true, endpoint.debugDescription)
            case let .remove(endpoint):
                configuration.onBonjourUpdate(false, endpoint.debugDescription)
            @unknown default:
                configuration.onBonjourUpdate(false, nil)
            }
        }

        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        handlers.values.forEach { $0.stop() }
        handlers.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        let handler = ConnectionHandler(
            id: id,
            connection: connection,
            configuration: configuration,
            queue: queue,
            onClose: { [weak self] id in
                self?.handlers[id] = nil
            }
        )

        handlers[id] = handler
        handler.start()
    }
}

private final class ConnectionHandler: @unchecked Sendable {
    private let id: UUID
    private let connection: NWConnection
    private let configuration: HTTPServer.Configuration
    private let queue: DispatchQueue
    private let onClose: @Sendable (UUID) -> Void

    private var buffer = Data()
    private var pendingUpload: PendingUpload?

    init(
        id: UUID,
        connection: NWConnection,
        configuration: HTTPServer.Configuration,
        queue: DispatchQueue,
        onClose: @escaping @Sendable (UUID) -> Void
    ) {
        self.id = id
        self.connection = connection
        self.configuration = configuration
        self.queue = queue
        self.onClose = onClose
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.finish()
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveNextChunk()
    }

    func stop() {
        connection.cancel()
        finish()
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let error {
                print("[drshare] receive error: \(error.localizedDescription)")
                cancelPendingUpload()
                finish()
                return
            }

            if let data, !data.isEmpty {
                if let pendingUpload {
                    do {
                        try pendingUpload.append(data)
                        reportIncomingTransfer(
                            sessionID: pendingUpload.sessionID,
                            filename: pendingUpload.filename,
                            transferredBytes: pendingUpload.receivedBytes,
                            totalBytes: pendingUpload.expectedBytes,
                            phase: .transferring
                        )
                    } catch {
                        let response = HTTPResponse.json(
                            APIErrorResponse(error: error.localizedDescription),
                            statusCode: 500,
                            reasonPhrase: "Internal Server Error"
                        )
                        reportIncomingTransfer(
                            sessionID: pendingUpload.sessionID,
                            filename: pendingUpload.filename,
                            transferredBytes: pendingUpload.receivedBytes,
                            totalBytes: pendingUpload.expectedBytes,
                            phase: .failed,
                            errorMessage: error.localizedDescription
                        )
                        pendingUpload.cancel()
                        self.pendingUpload = nil
                        send(response)
                        return
                    }

                    if pendingUpload.isComplete {
                        completePendingUpload(pendingUpload)
                        return
                    }
                } else {
                    buffer.append(data)
                }
            }

            if pendingUpload == nil, beginStreamingUploadIfNeeded() {
                return
            }

            if let request = HTTPRequestParser.parse(from: &buffer) {
                route(request) { [weak self] response in
                    self?.send(response)
                }
                return
            }

            if isComplete {
                cancelPendingUpload()
                finish()
                return
            }

            receiveNextChunk()
        }
    }

    private func route(_ request: HTTPRequest, completion: @escaping @Sendable (HTTPResponse) -> Void) {
        if request.path == "/favicon.ico" {
            completion(.empty(statusCode: 204, reasonPhrase: "No Content"))
            return
        }

        if request.path == "/health" {
            completion(.json(HealthResponse(status: "ok", app: "drshare")))
            return
        }

        if let asset = DrShareWebAssets.asset(for: request.path) {
            completion(.asset(asset.data, contentType: asset.contentType))
            return
        }

        guard isAuthorized(request) else {
            completion(.json(APIErrorResponse(error: "Pairing token is missing or invalid."), statusCode: 401, reasonPhrase: "Unauthorized"))
            return
        }

        if request.method == "GET", let downloadID = parseDownloadID(request.path) {
            Task {
                do {
                    let managedFile = try await configuration.dropStore.managedFile(for: downloadID)
                    let data = try Data(contentsOf: managedFile.fileURL)
                    let filename = managedFile.drop.filename ?? managedFile.fileURL.lastPathComponent
                    let disposition = #"attachment; filename="\#(filename.replacingOccurrences(of: "\"", with: ""))""#
                    completion(.binary(data, contentType: managedFile.drop.mime, contentDisposition: disposition))
                } catch let error as DropStoreError {
                    let statusCode: Int
                    let reason: String

                    switch error {
                    case .missingDrop:
                        statusCode = 404
                        reason = "Not Found"
                    default:
                        statusCode = 400
                        reason = "Bad Request"
                    }

                    completion(.json(APIErrorResponse(error: error.localizedDescription), statusCode: statusCode, reasonPhrase: reason))
                } catch {
                    completion(.json(APIErrorResponse(error: error.localizedDescription), statusCode: 500, reasonPhrase: "Internal Server Error"))
                }
            }
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/api/session"):
            completion(.json(makeSessionInfo()))

        case ("GET", "/api/drops"):
            Task {
                let drops = await configuration.dropStore.recentDrops(limit: 12)
                completion(.json(DropListResponse(drops: drops)))
            }

        case ("POST", "/api/drops/text"):
            guard let payload = try? JSONCodec.makeDecoder().decode(TextDropCreateRequest.self, from: request.body) else {
                completion(.json(APIErrorResponse(error: "Expected a JSON body with a `text` field."), statusCode: 400, reasonPhrase: "Bad Request"))
                return
            }

            Task {
                do {
                    let drop = try await configuration.dropStore.addTextDrop(text: payload.text, sender: .web)
                    configuration.onDropAdded(drop)
                    completion(.json(TextDropCreateResponse(drop: drop), statusCode: 201, reasonPhrase: "Created"))
                } catch {
                    completion(.json(APIErrorResponse(error: error.localizedDescription), statusCode: 400, reasonPhrase: "Bad Request"))
                }
            }

        case ("POST", "/api/drops/file"):
            let filename = request.headers["x-drshare-filename"]?.removingPercentEncoding
                ?? request.query["filename"]?.removingPercentEncoding
                ?? ""
            let mime = request.headers["content-type"] ?? "application/octet-stream"

            Task {
                do {
                    let drop = try await configuration.dropStore.addFileDrop(
                        data: request.body,
                        filename: filename,
                        mime: mime,
                        sender: .web
                    )
                    configuration.onDropAdded(drop)
                    completion(.json(FileDropCreateResponse(drop: drop), statusCode: 201, reasonPhrase: "Created"))
                } catch {
                    completion(.json(APIErrorResponse(error: error.localizedDescription), statusCode: 400, reasonPhrase: "Bad Request"))
                }
            }

        default:
            completion(.json(APIErrorResponse(error: "Route not found."), statusCode: 404, reasonPhrase: "Not Found"))
        }
    }

    private func send(_ response: HTTPResponse) {
        connection.send(content: response.serialized(), completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
            self?.finish()
        })
    }

    private func finish() {
        cancelPendingUpload()
        onClose(id)
    }

    private func makeSessionInfo() -> SessionInfo {
        let urls = configuration.urlsProvider()
        let token = configuration.tokenProvider()

        return SessionInfo(
            appName: "drshare",
            appVersion: "0.1.0",
            isHosting: true,
            port: Int(configuration.port),
            urls: urls,
            tokenHint: PairingTokenStore.masked(token),
            capabilities: [
                "text-send",
                "text-list",
                "file-upload",
                "file-download",
            ],
            maxUploadBytes: DropStore.maximumFileSizeBytes,
            retentionSeconds: configuration.dropStore.retentionSeconds
        )
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        let presentedToken = request.headers["x-drshare-token"] ?? request.query["token"] ?? ""
        return !presentedToken.isEmpty && presentedToken == configuration.tokenProvider()
    }

    private func isAuthorized(_ head: HTTPRequestHead) -> Bool {
        let presentedToken = head.headers["x-drshare-token"] ?? head.query["token"] ?? ""
        return !presentedToken.isEmpty && presentedToken == configuration.tokenProvider()
    }

    private func parseDownloadID(_ path: String) -> UUID? {
        let components = path.split(separator: "/")

        guard components.count == 4 else {
            return nil
        }

        guard components[0] == "api", components[1] == "drops", components[3] == "download" else {
            return nil
        }

        return UUID(uuidString: String(components[2]))
    }

    private func beginStreamingUploadIfNeeded() -> Bool {
        guard let (head, bodyStart) = HTTPRequestParser.parseHead(from: buffer) else {
            return false
        }

        guard head.method == "POST", head.path == "/api/drops/file" else {
            return false
        }

        guard isAuthorized(head) else {
            send(.json(APIErrorResponse(error: "Pairing token is missing or invalid."), statusCode: 401, reasonPhrase: "Unauthorized"))
            return true
        }

        guard head.headers["transfer-encoding"]?.lowercased() != "chunked" else {
            send(.json(APIErrorResponse(error: "Chunked uploads are not supported. Send a request with Content-Length."), statusCode: 400, reasonPhrase: "Bad Request"))
            return true
        }

        guard head.contentLength > 0 else {
            send(.json(APIErrorResponse(error: "File uploads require a positive Content-Length."), statusCode: 411, reasonPhrase: "Length Required"))
            return true
        }

        guard head.contentLength <= DropStore.maximumFileSizeBytes else {
            send(.json(APIErrorResponse(error: DropStoreError.fileTooLarge(maxBytes: DropStore.maximumFileSizeBytes).localizedDescription), statusCode: 413, reasonPhrase: "Payload Too Large"))
            return true
        }

        let filename = head.headers["x-drshare-filename"]?.removingPercentEncoding
            ?? head.query["filename"]?.removingPercentEncoding
            ?? ""
        let mime = head.headers["content-type"] ?? "application/octet-stream"

        do {
            let upload = try PendingUpload(
                expectedBytes: head.contentLength,
                filename: filename,
                mime: mime
            )

            let availableBodyBytes = min(max(buffer.count - bodyStart, 0), head.contentLength)
            if availableBodyBytes > 0 {
                let initialBody = Data(buffer[bodyStart..<(bodyStart + availableBodyBytes)])
                try upload.append(initialBody)
            }

            buffer.removeAll(keepingCapacity: false)
            pendingUpload = upload
            reportIncomingTransfer(
                sessionID: upload.sessionID,
                filename: upload.filename,
                transferredBytes: upload.receivedBytes,
                totalBytes: upload.expectedBytes,
                phase: .transferring
            )

            if upload.isComplete {
                completePendingUpload(upload)
            } else {
                receiveNextChunk()
            }
        } catch {
            send(.json(APIErrorResponse(error: error.localizedDescription), statusCode: 500, reasonPhrase: "Internal Server Error"))
        }

        return true
    }

    private func completePendingUpload(_ upload: PendingUpload) {
        pendingUpload = nil
        upload.close()
        reportIncomingTransfer(
            sessionID: upload.sessionID,
            filename: upload.filename,
            transferredBytes: upload.expectedBytes,
            totalBytes: upload.expectedBytes,
            phase: .finalizing
        )
        let temporaryFileURL = upload.temporaryFileURL
        let expectedBytes = upload.expectedBytes
        let filename = upload.filename
        let mime = upload.mime
        let sessionID = upload.sessionID

        Task {
            do {
                let drop = try await configuration.dropStore.addFileDrop(
                    fromTemporaryFileAt: temporaryFileURL,
                    size: expectedBytes,
                    filename: filename,
                    mime: mime,
                    sender: .web
                )
                configuration.onDropAdded(drop)
                reportIncomingTransfer(
                    sessionID: sessionID,
                    filename: filename,
                    transferredBytes: expectedBytes,
                    totalBytes: expectedBytes,
                    phase: .completed
                )
                send(.json(FileDropCreateResponse(drop: drop), statusCode: 201, reasonPhrase: "Created"))
            } catch {
                try? FileManager.default.removeItem(at: temporaryFileURL)
                reportIncomingTransfer(
                    sessionID: sessionID,
                    filename: filename,
                    transferredBytes: 0,
                    totalBytes: expectedBytes,
                    phase: .failed,
                    errorMessage: error.localizedDescription
                )
                send(.json(APIErrorResponse(error: error.localizedDescription), statusCode: 400, reasonPhrase: "Bad Request"))
            }
        }
    }

    private func cancelPendingUpload() {
        if let pendingUpload {
            reportIncomingTransfer(
                sessionID: pendingUpload.sessionID,
                filename: pendingUpload.filename,
                transferredBytes: pendingUpload.receivedBytes,
                totalBytes: pendingUpload.expectedBytes,
                phase: .failed,
                errorMessage: "Upload cancelled."
            )
        }
        pendingUpload?.cancel()
        pendingUpload = nil
    }

    private func reportIncomingTransfer(
        sessionID: UUID,
        filename: String,
        transferredBytes: Int,
        totalBytes: Int,
        phase: UploadActivity.Phase,
        errorMessage: String? = nil
    ) {
        configuration.onTransferActivity(
            UploadActivity(
                sessionID: sessionID,
                filename: filename.isEmpty ? "untitled file" : filename,
                transferredBytes: transferredBytes,
                totalBytes: totalBytes,
                direction: .receiving,
                phase: phase,
                errorMessage: errorMessage
            )
        )
    }
}

private final class PendingUpload {
    let sessionID = UUID()
    let expectedBytes: Int
    let filename: String
    let mime: String
    let temporaryFileURL: URL

    private let fileHandle: FileHandle
    private(set) var receivedBytes = 0
    private var isClosed = false

    init(expectedBytes: Int, filename: String, mime: String) throws {
        self.expectedBytes = expectedBytes
        self.filename = filename
        self.mime = mime
        self.temporaryFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("drshare-upload-\(UUID().uuidString)", isDirectory: false)

        FileManager.default.createFile(atPath: temporaryFileURL.path, contents: nil)
        self.fileHandle = try FileHandle(forWritingTo: temporaryFileURL)
    }

    var isComplete: Bool {
        receivedBytes >= expectedBytes
    }

    func append(_ data: Data) throws {
        guard !isClosed else {
            return
        }

        let remainingBytes = expectedBytes - receivedBytes
        guard remainingBytes > 0 else {
            return
        }

        let chunk = data.prefix(remainingBytes)
        try fileHandle.write(contentsOf: chunk)
        receivedBytes += chunk.count
    }

    func close() {
        guard !isClosed else {
            return
        }

        isClosed = true
        try? fileHandle.close()
    }

    func cancel() {
        close()
        try? FileManager.default.removeItem(at: temporaryFileURL)
    }
}
