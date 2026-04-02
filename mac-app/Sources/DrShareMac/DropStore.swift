import Foundation

import DrShareShared

enum DropStoreError: LocalizedError {
    case emptyText
    case emptyFile
    case missingFilename
    case missingDrop
    case fileNotAvailable
    case fileTooLarge(maxBytes: Int)

    var errorDescription: String? {
        switch self {
        case .emptyText:
            return "Text is empty."
        case .emptyFile:
            return "File body is empty."
        case .missingFilename:
            return "A filename is required for file uploads."
        case .missingDrop:
            return "Drop was not found."
        case .fileNotAvailable:
            return "File is no longer available."
        case let .fileTooLarge(maxBytes):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "File is too large. Max size is \(formatter.string(fromByteCount: Int64(maxBytes)))."
        }
    }
}

struct ManagedFile: Sendable {
    let drop: DropRecord
    let fileURL: URL
}

actor DropStore {
    static let maximumFileSizeBytes = 5 * 1_073_741_824

    private let metadataURL: URL
    private let filesDirectoryURL: URL
    private let fileManager: FileManager
    nonisolated let retentionSeconds: Int
    private var storedDrops: [StoredDrop]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.retentionSeconds = RetentionSettings.resolvedSeconds()
        let rootDirectory = Self.resolveStorageDirectory(fileManager: fileManager)
        self.metadataURL = rootDirectory.appendingPathComponent("drops.json")
        self.filesDirectoryURL = rootDirectory.appendingPathComponent("files", isDirectory: true)
        try? fileManager.createDirectory(at: filesDirectoryURL, withIntermediateDirectories: true)

        if
            let data = try? Data(contentsOf: metadataURL),
            let decoded = try? JSONCodec.makeDecoder().decode([StoredDrop].self, from: data)
        {
            self.storedDrops = decoded
        } else {
            self.storedDrops = []
        }

        let prunedDrops = Self.pruneExpired(
            from: storedDrops,
            filesDirectoryURL: filesDirectoryURL,
            fileManager: fileManager,
            retentionSeconds: retentionSeconds
        )

        if prunedDrops.count != storedDrops.count {
            self.storedDrops = prunedDrops
            try? Self.persist(storedDrops, to: metadataURL)
        }
    }

    func recentDrops(limit: Int) -> [DropRecord] {
        pruneExpiredIfNeeded()
        return Array(storedDrops.prefix(limit).map(\.record))
    }

    func addTextDrop(text: String, sender: DropSender) throws -> DropRecord {
        pruneExpiredIfNeeded()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            throw DropStoreError.emptyText
        }

        let id = UUID()
        let record = DropRecord(
            id: id,
            kind: .text,
            sender: sender,
            mime: "text/plain",
            filename: nil,
            size: trimmed.lengthOfBytes(using: .utf8),
            text: trimmed,
            downloadPath: nil,
            createdAt: Date()
        )

        try insertStoredDrop(StoredDrop(record: record, storedFilename: nil))
        return record
    }

    func addFileDrop(
        data: Data,
        filename: String,
        mime: String,
        sender: DropSender
    ) throws -> DropRecord {
        pruneExpiredIfNeeded()

        guard !data.isEmpty else {
            throw DropStoreError.emptyFile
        }

        guard data.count <= Self.maximumFileSizeBytes else {
            throw DropStoreError.fileTooLarge(maxBytes: Self.maximumFileSizeBytes)
        }

        let sanitizedFilename = sanitize(filename)
        guard !sanitizedFilename.isEmpty else {
            throw DropStoreError.missingFilename
        }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("drshare-upload-\(UUID().uuidString)", isDirectory: false)
        try data.write(to: temporaryURL, options: .atomic)
        return try addFileDrop(
            fromTemporaryFileAt: temporaryURL,
            size: data.count,
            filename: sanitizedFilename,
            mime: mime,
            sender: sender
        )
    }

    func addFileDrop(
        fromTemporaryFileAt temporaryURL: URL,
        size: Int,
        filename: String,
        mime: String,
        sender: DropSender
    ) throws -> DropRecord {
        pruneExpiredIfNeeded()

        guard size > 0 else {
            try? fileManager.removeItem(at: temporaryURL)
            throw DropStoreError.emptyFile
        }

        guard size <= Self.maximumFileSizeBytes else {
            try? fileManager.removeItem(at: temporaryURL)
            throw DropStoreError.fileTooLarge(maxBytes: Self.maximumFileSizeBytes)
        }

        let sanitizedFilename = sanitize(filename)
        guard !sanitizedFilename.isEmpty else {
            try? fileManager.removeItem(at: temporaryURL)
            throw DropStoreError.missingFilename
        }

        let id = UUID()
        let fileExtension = URL(fileURLWithPath: sanitizedFilename).pathExtension
        let storedFilename = fileExtension.isEmpty
            ? id.uuidString
            : "\(id.uuidString).\(fileExtension)"
        let fileURL = filesDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)

        if fileManager.fileExists(atPath: fileURL.path) {
            try? fileManager.removeItem(at: fileURL)
        }

        do {
            try fileManager.moveItem(at: temporaryURL, to: fileURL)
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }

        let record = DropRecord(
            id: id,
            kind: .file,
            sender: sender,
            mime: mime.isEmpty ? "application/octet-stream" : mime,
            filename: sanitizedFilename,
            size: size,
            text: nil,
            downloadPath: "/api/drops/\(id.uuidString)/download",
            createdAt: Date()
        )

        do {
            try insertStoredDrop(StoredDrop(record: record, storedFilename: storedFilename))
            return record
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    func managedFile(for id: UUID) throws -> ManagedFile {
        pruneExpiredIfNeeded()

        guard let storedDrop = storedDrops.first(where: { $0.record.id == id }) else {
            throw DropStoreError.missingDrop
        }

        guard let storedFilename = storedDrop.storedFilename else {
            throw DropStoreError.fileNotAvailable
        }

        let fileURL = filesDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DropStoreError.fileNotAvailable
        }

        return ManagedFile(drop: storedDrop.record, fileURL: fileURL)
    }

    func deleteDrop(by id: UUID) {
        guard let index = storedDrops.firstIndex(where: { $0.record.id == id }) else { return }
        let drop = storedDrops[index]
        storedDrops.remove(at: index)
        removeFiles(for: [drop])
        try? persist()
    }

    private func persist() throws {
        try Self.persist(storedDrops, to: metadataURL)
    }

    private func insertStoredDrop(_ storedDrop: StoredDrop) throws {
        var updated = [storedDrop]
        updated.append(contentsOf: storedDrops)

        let trimmedDrops = Array(updated.prefix(50))
        let removedDrops = Array(updated.dropFirst(50))
        removeFiles(for: removedDrops)

        storedDrops = trimmedDrops
        try persist()
    }

    private func pruneExpiredIfNeeded(referenceDate: Date = Date()) {
        let prunedDrops = Self.pruneExpired(
            from: storedDrops,
            filesDirectoryURL: filesDirectoryURL,
            fileManager: fileManager,
            retentionSeconds: retentionSeconds,
            referenceDate: referenceDate
        )

        guard prunedDrops.count != storedDrops.count else {
            return
        }

        storedDrops = prunedDrops
        try? persist()
    }

    private static func pruneExpired(
        from storedDrops: [StoredDrop],
        filesDirectoryURL: URL,
        fileManager: FileManager,
        retentionSeconds: Int,
        referenceDate: Date = Date()
    ) -> [StoredDrop] {
        guard retentionSeconds > 0 else {
            return storedDrops
        }

        let expirationDate = referenceDate.addingTimeInterval(-TimeInterval(retentionSeconds))

        let expiredDrops = storedDrops.filter { $0.record.createdAt < expirationDate }
        guard !expiredDrops.isEmpty else {
            return storedDrops
        }

        removeFiles(for: expiredDrops, filesDirectoryURL: filesDirectoryURL, fileManager: fileManager)
        return storedDrops.filter { $0.record.createdAt >= expirationDate }
    }

    private func removeFiles(for drops: [StoredDrop]) {
        Self.removeFiles(for: drops, filesDirectoryURL: filesDirectoryURL, fileManager: fileManager)
    }

    private static func removeFiles(for drops: [StoredDrop], filesDirectoryURL: URL, fileManager: FileManager) {
        for drop in drops {
            guard let storedFilename = drop.storedFilename else {
                continue
            }

            let fileURL = filesDirectoryURL.appendingPathComponent(storedFilename, isDirectory: false)
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private static func persist(_ storedDrops: [StoredDrop], to metadataURL: URL) throws {
        let data = try JSONCodec.makeEncoder().encode(storedDrops)
        try data.write(to: metadataURL, options: .atomic)
    }

    private func sanitize(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        let disallowed = CharacterSet(charactersIn: "/:\\")
        let parts = trimmed.components(separatedBy: disallowed)
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "-")
        return joined.replacingOccurrences(of: "..", with: "-")
    }

    private static func resolveStorageDirectory(fileManager: FileManager) -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["DRSHARE_STORAGE_ROOT"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            try? fileManager.createDirectory(at: overrideURL, withIntermediateDirectories: true)
            return overrideURL
        }

        let applicationSupportURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/drshare", isDirectory: true)

        if (try? fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)) != nil {
            return applicationSupportURL
        }

        let workspaceFallbackURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".drshare-state", isDirectory: true)
        try? fileManager.createDirectory(at: workspaceFallbackURL, withIntermediateDirectories: true)
        return workspaceFallbackURL
    }
}

private struct StoredDrop: Codable {
    let record: DropRecord
    let storedFilename: String?
}
