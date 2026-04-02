import AppKit
import Foundation
import SwiftUI

import DrShareShared

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var isHosting = false
    @Published private(set) var displayURLs: [String] = []
    @Published private(set) var recentDrops: [DropRecord] = []
    @Published private(set) var dropThumbnails: [UUID: NSImage] = [:]
    @Published private(set) var token: String
    @Published private(set) var retentionPolicy: RetentionPolicy
    @Published private(set) var qrCodeImage: NSImage?
    @Published private(set) var isAdvertisingBonjour = false
    @Published private(set) var bonjourDescription: String?
    @Published private(set) var lastError: String?
    @Published private(set) var activeTransfer: UploadActivity?

    private var dropStore: DropStore
    private let port: UInt16 = 3847
    private var server: HTTPServer?

    init(dropStore: DropStore = DropStore()) {
        self.dropStore = dropStore
        self.token = PairingTokenStore.current()
        self.retentionPolicy = RetentionSettings.current()

        Task {
            await loadInitialDrops()
        }

        startHosting()
    }

    var primaryURL: String? {
        displayURLs.first
    }

    var shareURLs: [String] {
        displayURLs.map { "\($0)/?token=\(token)" }
    }

    var primaryShareURL: String? {
        shareURLs.first
    }

    var retentionDescription: String {
        Self.formatRetention(seconds: dropStore.retentionSeconds)
    }

    var retentionOverrideDescription: String? {
        guard let overrideSeconds = RetentionSettings.environmentOverrideSeconds() else {
            return nil
        }

        return Self.formatRetention(seconds: overrideSeconds)
    }

    func startHosting() {
        guard server == nil else {
            return
        }

        let server = HTTPServer(
            configuration: .init(
                port: port,
                urlsProvider: { LocalAddressResolver.baseURLs(port: self.port) },
                tokenProvider: { PairingTokenStore.current() },
                bonjourService: HostDiscovery.makeService(),
                dropStore: dropStore,
                onServerError: { [weak self] message in
                    Task { @MainActor [weak self] in
                        self?.lastError = message
                        self?.isHosting = false
                        self?.isAdvertisingBonjour = false
                        self?.bonjourDescription = nil
                        self?.displayURLs = []
                        self?.qrCodeImage = nil
                        self?.server = nil
                    }
                },
                onBonjourUpdate: { [weak self] isAdvertising, description in
                    Task { @MainActor [weak self] in
                        self?.isAdvertisingBonjour = isAdvertising
                        self?.bonjourDescription = description ?? HostDiscovery.fallbackStatusDescription()
                    }
                },
                onTransferActivity: { [weak self] activity in
                    Task { @MainActor [weak self] in
                        self?.applyTransferActivity(activity)
                    }
                },
                onDropAdded: { [weak self] drop in
                    Task { @MainActor [weak self] in
                        self?.insertDrop(drop)
                    }
                }
            )
        )

        do {
            try server.start()
            self.server = server
            isHosting = true
            lastError = nil
            refreshDisplayURLs()
            bonjourDescription = HostDiscovery.fallbackStatusDescription()
            printLaunchHint()
        } catch {
            isHosting = false
            lastError = error.localizedDescription
            displayURLs = []
            qrCodeImage = nil
        }
    }

    func stopHosting() {
        server?.stop()
        server = nil
        isHosting = false
        isAdvertisingBonjour = false
        bonjourDescription = nil
        displayURLs = []
        qrCodeImage = nil
    }

    func copyShareURL() {
        guard let primaryShareURL else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(primaryShareURL, forType: .string)
    }

    func openShareURLInBrowser() {
        guard let primaryShareURL, let url = URL(string: primaryShareURL) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func copyToken() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(token, forType: .string)
    }

    func rotateToken() {
        token = PairingTokenStore.rotate()
        refreshDisplayURLs()
        printLaunchHint()
    }

    func updateRetentionPolicy(_ policy: RetentionPolicy) {
        RetentionSettings.set(policy)
        retentionPolicy = policy
        rebuildStoreAndHost()
    }

    func sendText(_ text: String) {
        let currentDropStore = dropStore

        Task { [weak self] in
            do {
                let drop = try await currentDropStore.addTextDrop(text: text, sender: .mac)
                self?.lastError = nil
                self?.insertDrop(drop)
            } catch {
                self?.lastError = error.localizedDescription
            }
        }
    }

    func uploadFile(from url: URL) {
        let uploadID = UUID()
        let currentDropStore = dropStore
        let progressReporter = TransferReporter(model: self)

        Task { [weak self] in
            do {
                let isSecurityScoped = url.startAccessingSecurityScopedResource()
                defer {
                    if isSecurityScoped {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let filename = url.lastPathComponent
                let fileSize = try Self.fileSize(for: url)
                self?.applyTransferActivity(
                    UploadActivity(
                        sessionID: uploadID,
                        filename: filename,
                        transferredBytes: 0,
                        totalBytes: fileSize,
                        direction: .sending,
                        phase: .preparing,
                        errorMessage: nil
                    )
                )

                let temporaryURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("drshare-local-upload-\(UUID().uuidString)", isDirectory: false)
                defer {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                if FileManager.default.fileExists(atPath: temporaryURL.path) {
                    try? FileManager.default.removeItem(at: temporaryURL)
                }

                try await Self.copyFileChunked(from: url, to: temporaryURL) { copiedBytes in
                    progressReporter.publish(
                        UploadActivity(
                            sessionID: uploadID,
                            filename: filename,
                            transferredBytes: copiedBytes,
                            totalBytes: fileSize,
                            direction: .sending,
                            phase: .transferring,
                            errorMessage: nil
                        )
                    )
                }

                // Extremely rudimentary mime detection just for the UI
                let ext = url.pathExtension.lowercased()
                let mime: String
                switch ext {
                case "jpg", "jpeg": mime = "image/jpeg"
                case "png": mime = "image/png"
                case "gif": mime = "image/gif"
                case "mp4": mime = "video/mp4"
                case "pdf": mime = "application/pdf"
                case "txt": mime = "text/plain"
                default: mime = "application/octet-stream"
                }

                self?.applyTransferActivity(
                    UploadActivity(
                        sessionID: uploadID,
                        filename: filename,
                        transferredBytes: fileSize,
                        totalBytes: fileSize,
                        direction: .sending,
                        phase: .finalizing,
                        errorMessage: nil
                    )
                )

                let drop = try await currentDropStore.addFileDrop(
                    fromTemporaryFileAt: temporaryURL,
                    size: fileSize,
                    filename: filename,
                    mime: mime,
                    sender: .mac
                )
                self?.insertDrop(drop)
                self?.completeTransfer(sessionID: uploadID)
            } catch {
                self?.lastError = error.localizedDescription
                self?.applyTransferActivity(
                    UploadActivity(
                        sessionID: uploadID,
                        filename: url.lastPathComponent,
                        transferredBytes: 0,
                        totalBytes: 0,
                        direction: .sending,
                        phase: .failed,
                        errorMessage: error.localizedDescription
                    )
                )
            }
        }
    }

    func deleteDrop(_ drop: DropRecord) {
        Task {
            await dropStore.deleteDrop(by: drop.id)
            await MainActor.run {
                self.recentDrops.removeAll { $0.id == drop.id }
            }
        }
    }

    func copyText(for drop: DropRecord) {
        guard let text = drop.text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openFile(for drop: DropRecord) {
        Task {
            do {
                let managedFile = try await dropStore.managedFile(for: drop.id)
                _ = await MainActor.run {
                    NSWorkspace.shared.open(managedFile.fileURL)
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func loadThumbnail(for drop: DropRecord) {
        guard drop.kind == .file, drop.mime.starts(with: "image/"), dropThumbnails[drop.id] == nil else { return }
        Task {
            do {
                let managedFile = try await dropStore.managedFile(for: drop.id)
                if let image = NSImage(contentsOf: managedFile.fileURL) {
                    let thumb = makeThumbnail(from: image, size: NSSize(width: 40, height: 40))
                    await MainActor.run {
                        self.dropThumbnails[drop.id] = thumb
                    }
                }
            } catch {
            }
        }
    }

    private func makeThumbnail(from image: NSImage, size: NSSize) -> NSImage {
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        // Compute aspect fill rect
        let imageSize = image.size
        let ratio = max(size.width / imageSize.width, size.height / imageSize.height)
        let newSize = NSSize(width: imageSize.width * ratio, height: imageSize.height * ratio)
        let rect = NSRect(
            x: (size.width - newSize.width) / 2.0,
            y: (size.height - newSize.height) / 2.0,
            width: newSize.width,
            height: newSize.height
        )
        image.draw(in: rect)
        thumb.unlockFocus()
        return thumb
    }

    func copyLatestText() {
        guard let text = recentDrops.first(where: { $0.kind == .text })?.text else {
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func openLatestFile() {
        guard let fileDrop = recentDrops.first(where: { $0.kind == .file }) else {
            return
        }

        Task {
            do {
                let managedFile = try await dropStore.managedFile(for: fileDrop.id)
                _ = await MainActor.run {
                    NSWorkspace.shared.open(managedFile.fileURL)
                }
            } catch {
                await MainActor.run {
                    self.lastError = error.localizedDescription
                }
            }
        }
    }

    func reloadDrops() {
        Task {
            await loadInitialDrops()
        }
    }

    private func loadInitialDrops() async {
        let drops = await dropStore.recentDrops(limit: 8)
        recentDrops = drops
        let visibleIDs = Set(drops.map(\.id))
        dropThumbnails = dropThumbnails.filter { visibleIDs.contains($0.key) }
    }

    private func refreshDisplayURLs() {
        displayURLs = LocalAddressResolver.baseURLs(port: port)
        qrCodeImage = primaryShareURL.flatMap { QRCodeRenderer.image(for: $0) }
    }

    private func insertDrop(_ drop: DropRecord) {
        recentDrops.removeAll { $0.id == drop.id }
        recentDrops.insert(drop, at: 0)
        recentDrops = Array(recentDrops.prefix(8))
        let visibleIDs = Set(recentDrops.map(\.id))
        dropThumbnails = dropThumbnails.filter { visibleIDs.contains($0.key) }
    }

    fileprivate func applyTransferActivity(_ activity: UploadActivity) {
        activeTransfer = activity

        if activity.phase == .completed {
            scheduleTransferClear(sessionID: activity.sessionID)
        }
    }

    private func completeTransfer(sessionID: UUID) {
        guard activeTransfer?.sessionID == sessionID else {
            return
        }

        activeTransfer = UploadActivity(
            sessionID: sessionID,
            filename: activeTransfer?.filename ?? "file",
            transferredBytes: activeTransfer?.totalBytes ?? 0,
            totalBytes: activeTransfer?.totalBytes ?? 0,
            direction: activeTransfer?.direction ?? .sending,
            phase: .completed,
            errorMessage: nil
        )

        scheduleTransferClear(sessionID: sessionID)
    }

    private func scheduleTransferClear(sessionID: UUID) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard self?.activeTransfer?.sessionID == sessionID else {
                return
            }
            self?.activeTransfer = nil
        }
    }

    private func printLaunchHint() {
        if let primaryShareURL {
            print("[drshare] host ready at \(primaryShareURL)")
        }
    }

    nonisolated private static func fileSize(for url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values.fileSize {
            return fileSize
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }

    nonisolated private static func copyFileChunked(
        from sourceURL: URL,
        to destinationURL: URL,
        progress: @escaping @Sendable (Int) async -> Void
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            FileManager.default.createFile(atPath: destinationURL.path, contents: nil)

            let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
            let destinationHandle = try FileHandle(forWritingTo: destinationURL)
            defer {
                try? sourceHandle.close()
                try? destinationHandle.close()
            }

            let chunkSize = 1_048_576
            var copiedBytes = 0

            while true {
                let chunk = sourceHandle.readData(ofLength: chunkSize)
                guard !chunk.isEmpty else {
                    break
                }

                try destinationHandle.write(contentsOf: chunk)
                copiedBytes += chunk.count
                await progress(copiedBytes)
            }

            let destinationSize = try fileSize(for: destinationURL)
            guard destinationSize == copiedBytes else {
                throw CocoaError(.fileWriteUnknown)
            }
        }.value
    }

    private static func formatRetention(seconds: Int) -> String {
        if seconds <= 0 {
            return "never"
        }

        if seconds < 60 {
            return "\(seconds)s"
        }

        if seconds < 3600 {
            return "\(seconds / 60)m"
        }

        if seconds < 86_400 {
            let hours = Double(seconds) / 3600
            return hours.rounded(.down) == hours ? "\(Int(hours))h" : String(format: "%.1fh", hours)
        }

        let days = Double(seconds) / 86_400
        return days.rounded(.down) == days ? "\(Int(days))d" : String(format: "%.1fd", days)
    }

    private func rebuildStoreAndHost() {
        let shouldRestartHost = isHosting

        if shouldRestartHost {
            stopHosting()
        }

        dropStore = DropStore()
        dropThumbnails = [:]

        Task {
            await loadInitialDrops()
        }

        if shouldRestartHost {
            startHosting()
        }
    }
}

private final class TransferReporter: @unchecked Sendable {
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    func publish(_ activity: UploadActivity) {
        Task { @MainActor [weak self] in
            self?.model?.applyTransferActivity(activity)
        }
    }
}
