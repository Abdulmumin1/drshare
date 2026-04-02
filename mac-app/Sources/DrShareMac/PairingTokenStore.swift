import Foundation

enum PairingTokenStore {
    private static let key = "drshare.pairing-token"

    static func current() -> String {
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }

        let fresh = generate()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static func rotate() -> String {
        let fresh = generate()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    static func masked(_ token: String) -> String {
        let suffix = String(token.suffix(4))
        return "••••\(suffix)"
    }

    private static func generate() -> String {
        let raw = UUID().uuidString.replacingOccurrences(of: "-", with: "").uppercased()
        let first = raw.prefix(4)
        let second = raw.dropFirst(4).prefix(4)
        let third = raw.dropFirst(8).prefix(4)
        return "\(first)-\(second)-\(third)"
    }
}
