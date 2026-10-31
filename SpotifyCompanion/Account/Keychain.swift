import Foundation
import Security

/// Generic-password items in the login keychain, for the Spotify refresh token.
///
/// Keychain calls can block for as long as macOS shows an access prompt (every rebuild of an
/// ad-hoc signed app gets one), so they run on a serial queue of their own, never the main
/// thread. Being serial also keeps a sign-out's delete ahead of the next sign-in's write.
enum Keychain {
    private static let service = "com.hoventan.SpotifyCompanion"
    private static let queue = DispatchQueue(label: "com.hoventan.SpotifyCompanion.keychain")

    static func read(_ account: String) async -> String? {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: readNow(account)) }
        }
    }

    /// Queued; returns at once.
    static func write(_ value: String, for account: String) {
        queue.async { writeNow(value, for: account) }
    }

    /// Queued; returns at once.
    static func delete(_ account: String) {
        queue.async {
            SecItemDelete([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ] as CFDictionary)
        }
    }

    private static func readNow(_ account: String) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeNow(_ value: String, for account: String) {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        let data = Data(value.utf8)
        if SecItemUpdate(query, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            SecItemAdd([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
                kSecAttrLabel: "Spotify Companion (Spotify sign-in)",
                kSecValueData: data,
            ] as CFDictionary, nil)
        }
    }
}
