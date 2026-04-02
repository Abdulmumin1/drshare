import Foundation

enum RetentionPolicy: String, CaseIterable, Identifiable, Sendable {
    case oneHour
    case oneDay
    case oneWeek
    case never

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneHour:
            return "1 hour"
        case .oneDay:
            return "24 hours"
        case .oneWeek:
            return "7 days"
        case .never:
            return "Never"
        }
    }

    var shortLabel: String {
        switch self {
        case .oneHour:
            return "1h"
        case .oneDay:
            return "24h"
        case .oneWeek:
            return "7d"
        case .never:
            return "Never"
        }
    }

    var seconds: Int {
        switch self {
        case .oneHour:
            return 60 * 60
        case .oneDay:
            return 24 * 60 * 60
        case .oneWeek:
            return 7 * 24 * 60 * 60
        case .never:
            return 0
        }
    }
}

enum RetentionSettings {
    private static let key = "drshare.retention-policy"
    static let defaultPolicy: RetentionPolicy = .oneDay

    static func current(userDefaults: UserDefaults = .standard) -> RetentionPolicy {
        guard
            let rawValue = userDefaults.string(forKey: key),
            let policy = RetentionPolicy(rawValue: rawValue)
        else {
            return defaultPolicy
        }

        return policy
    }

    static func set(_ policy: RetentionPolicy, userDefaults: UserDefaults = .standard) {
        userDefaults.set(policy.rawValue, forKey: key)
    }

    static func resolvedSeconds(userDefaults: UserDefaults = .standard) -> Int {
        environmentOverrideSeconds() ?? current(userDefaults: userDefaults).seconds
    }

    static func environmentOverrideSeconds() -> Int? {
        guard let rawValue = ProcessInfo.processInfo.environment["DRSHARE_RETENTION_HOURS"] else {
            return nil
        }

        if rawValue.lowercased() == "never" {
            return 0
        }

        guard let hours = Double(rawValue), hours >= 0 else {
            return nil
        }

        if hours == 0 {
            return 0
        }

        return max(Int(hours * 60 * 60), 1)
    }
}
