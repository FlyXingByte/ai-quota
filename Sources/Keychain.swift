import Foundation

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

    /// Human-readable reason for the statuses this app actually runs into.
    static func explain(_ status: OSStatus, item: String) -> String {
        switch status {
        case errSecItemNotFound:
            return "钥匙串里没有「\(item)」"
        case errSecUserCanceled:
            return "钥匙串授权被取消（状态 -128）。命令行里弹不出授权框，"
                + "请从访达或聚焦启动 AI Quota，在弹窗里点\"始终允许\"。"
        case errSecInteractionNotAllowed:
            return "钥匙串当前不允许交互（状态 \(status)），请解锁登录钥匙串后重试。"
        default:
            return "读不到钥匙串条目「\(item)」（状态 \(status)）"
        }
    }
}
