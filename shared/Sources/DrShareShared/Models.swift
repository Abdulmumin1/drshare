import Foundation

public enum DropKind: String, Codable, Sendable {
    case text
    case file
}

public enum DropSender: String, Codable, Sendable {
    case web
    case mac
    case android
}

public struct DropRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let kind: DropKind
    public let sender: DropSender
    public let mime: String
    public let filename: String?
    public let size: Int
    public let text: String?
    public let downloadPath: String?
    public let createdAt: Date

    public init(
        id: UUID,
        kind: DropKind,
        sender: DropSender,
        mime: String,
        filename: String?,
        size: Int,
        text: String?,
        downloadPath: String?,
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.sender = sender
        self.mime = mime
        self.filename = filename
        self.size = size
        self.text = text
        self.downloadPath = downloadPath
        self.createdAt = createdAt
    }
}

public struct DropListResponse: Codable, Sendable {
    public let drops: [DropRecord]

    public init(drops: [DropRecord]) {
        self.drops = drops
    }
}

public struct TextDropCreateRequest: Codable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct TextDropCreateResponse: Codable, Sendable {
    public let drop: DropRecord

    public init(drop: DropRecord) {
        self.drop = drop
    }
}

public struct FileDropCreateResponse: Codable, Sendable {
    public let drop: DropRecord

    public init(drop: DropRecord) {
        self.drop = drop
    }
}

public struct SessionInfo: Codable, Sendable {
    public let appName: String
    public let appVersion: String
    public let isHosting: Bool
    public let port: Int
    public let urls: [String]
    public let tokenHint: String
    public let capabilities: [String]
    public let maxUploadBytes: Int
    public let retentionSeconds: Int

    public init(
        appName: String,
        appVersion: String,
        isHosting: Bool,
        port: Int,
        urls: [String],
        tokenHint: String,
        capabilities: [String],
        maxUploadBytes: Int,
        retentionSeconds: Int
    ) {
        self.appName = appName
        self.appVersion = appVersion
        self.isHosting = isHosting
        self.port = port
        self.urls = urls
        self.tokenHint = tokenHint
        self.capabilities = capabilities
        self.maxUploadBytes = maxUploadBytes
        self.retentionSeconds = retentionSeconds
    }
}

public struct HealthResponse: Codable, Sendable {
    public let status: String
    public let app: String

    public init(status: String, app: String) {
        self.status = status
        self.app = app
    }
}

public struct APIErrorResponse: Codable, Sendable {
    public let error: String

    public init(error: String) {
        self.error = error
    }
}

public enum JSONCodec {
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
