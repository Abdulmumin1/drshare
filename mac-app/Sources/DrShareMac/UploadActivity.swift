import Foundation

struct UploadActivity: Equatable, Sendable {
    enum Direction: String, Sendable {
        case sending
        case receiving
    }

    enum Phase: String, Sendable {
        case preparing
        case transferring
        case finalizing
        case completed
        case failed
    }

    let sessionID: UUID
    let filename: String
    let transferredBytes: Int
    let totalBytes: Int
    let direction: Direction
    let phase: Phase
    let errorMessage: String?

    var progressFraction: Double {
        guard totalBytes > 0 else {
            return 0
        }

        return min(max(Double(transferredBytes) / Double(totalBytes), 0), 1)
    }
}
