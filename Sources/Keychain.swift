import Foundation
import Security

/// Serialized keychain reads.
///
/// Providers refresh concurrently, and three of them need keychain items whose
/// ACLs may prompt (Chrome Safe Storage, the DeepSeek key, the Claude Code
/// credentials). Overlapping prompts cancel each other and surface as
/// `errSecUserCanceled` (-128), so requests are funnelled through one lock.
enum Keychain {
    private static let gate = NSLock()

    /// Generic-password lookup. `account` is optional — some items are keyed by
    /// service alone.
    static func read(service: String, account: String? = nil) -> (data: Data?, status: OSStatus) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let account { query[kSecAttrAccount as String] = account }

        gate.lock()
        defer { gate.unlock() }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (item as? Data, status)
    }

    static func string(service: String, account: String? = nil) -> String? {
        let result = read(service: service, account: account)
        guard result.status == errSecSuccess, let data = result.data else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Stores a secret directly in Keychain. The value never enters Config,
    /// shell history, process arguments, or application logs.
    static func store(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8), !data.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        gate.lock()
        defer { gate.unlock() }

        var status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw QuotaError.message(L("keychain.write_failed", service, Int(status)))
        }
    }

    /// Human-readable reason for the statuses this app actually runs into.
    static func explain(_ status: OSStatus, item: String) -> String {
        switch status {
        case errSecItemNotFound:
            return L("keychain.not_found", item)
        case errSecUserCanceled:
            return L("keychain.user_canceled")
        case errSecInteractionNotAllowed:
            return L("keychain.no_interaction", Int(status))
        default:
            return L("keychain.read_failed", item, Int(status))
        }
    }
}
