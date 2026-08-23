import CommonCrypto
import Foundation
import SQLite3

/// Reads Chrome's cookie jar on macOS so the app can reuse the browser login
/// for sites that have no public quota API (opencode.ai, platform.deepseek.com).
///
/// macOS scheme: the AES key is PBKDF2-HMAC-SHA1 over the keychain password
/// stored under service "Chrome Safe Storage", salt "saltysalt", 1003 rounds,
/// 16 bytes. Values are AES-128-CBC with an IV of sixteen spaces. Chrome 130+
/// additionally prefixes the plaintext with sha256(host_key).
enum ChromeCookies {

    static let chromeRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Google/Chrome")

    private static var cachedKey: Data?

    // MARK: - Keychain

    /// Fetches the Safe Storage password. Prompts once, then the user can
    /// "Always Allow" and this stays silent.
    static func safeStoragePassword() throws -> String {
        let result = Keychain.read(service: "Chrome Safe Storage", account: "Chrome")
        if result.status == errSecSuccess, let data = result.data,
           let pw = String(data: data, encoding: .utf8) {
            return pw
        }
        let status = result.status
        // Fall back to the `security` CLI, which some keychain ACLs accept when
        // a freshly-signed binary does not.
        if let pw = try? Shell.run("/usr/bin/security",
                                   ["find-generic-password", "-w",
                                    "-s", "Chrome Safe Storage", "-a", "Chrome"],
                                   timeout: 30),
           !pw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return pw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw QuotaError.message(Keychain.explain(status, item: "Chrome Safe Storage"))
    }

    static func encryptionKey() throws -> Data {
        if let cachedKey { return cachedKey }
        let pw = try safeStoragePassword()
        let salt = Array("saltysalt".utf8)
        var derived = [UInt8](repeating: 0, count: 16)
        let pwBytes = Array(pw.utf8)
        let result = pwBytes.withUnsafeBufferPointer { pwPtr -> Int32 in
            pwPtr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: pwBytes.count) { pwChars in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2), pwChars, pwBytes.count,
                    salt, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                    &derived, derived.count)
            }
        }
        guard result == kCCSuccess else {
            throw QuotaError.message("PBKDF2 派生密钥失败 (\(result))")
        }
        let key = Data(derived)
        cachedKey = key
        return key
    }

    // MARK: - Decryption

    static func decrypt(_ encrypted: Data, hostKey: String, key: Data) -> String? {
        guard !encrypted.isEmpty else { return nil }
        let prefix = encrypted.prefix(3)
        guard prefix == Data("v10".utf8) || prefix == Data("v11".utf8) else {
            // Pre-encryption Chrome stored the value in the clear.
            return String(data: encrypted, encoding: .utf8)
        }
        var body = encrypted.dropFirst(3)
        let overflow = body.count % kCCBlockSizeAES128
        if overflow != 0 { body = body.dropLast(overflow) }
        guard !body.isEmpty else { return nil }

        let iv = [UInt8](repeating: 0x20, count: kCCBlockSizeAES128)  // sixteen spaces
        var out = [UInt8](repeating: 0, count: body.count + kCCBlockSizeAES128)
        var moved = 0
        let status = key.withUnsafeBytes { keyPtr in
            Data(body).withUnsafeBytes { dataPtr in
                CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(0),  // no padding flag: Chrome pads manually
                        keyPtr.baseAddress, key.count, iv,
                        dataPtr.baseAddress, body.count,
                        &out, out.count, &moved)
            }
        }
        guard status == kCCSuccess, moved > 0 else { return nil }
        var plain = Data(out.prefix(moved))

        // Strip PKCS#7 padding.
        if let pad = plain.last, pad >= 1, pad <= 16, plain.count >= Int(pad) {
            plain = plain.dropLast(Int(pad))
        }
        // Chrome >= 130 prefixes the value with sha256(host_key).
        let hostHash = sha256(Data(hostKey.utf8))
        if plain.count >= 32, plain.prefix(32) == hostHash {
            plain = plain.dropFirst(32)
        }
        return String(data: plain, encoding: .utf8)
    }

    static func sha256(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &digest) }
        return Data(digest)
    }

    // MARK: - Reading

    static func profileDirectories() -> [URL] {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: chromeRoot.path)) ?? []
        var dirs = names
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
            .map { chromeRoot.appendingPathComponent($0) }
        // Look at Default first, it is the common case.
        dirs.sort { a, _ in a.lastPathComponent == "Default" }
        return dirs.filter { fm.fileExists(atPath: $0.appendingPathComponent("Cookies").path) }
    }

    /// Returns every cookie whose host_key matches the SQL LIKE pattern,
    /// searching all Chrome profiles and preferring the profile with the most hits.
    static func cookies(matching hostPattern: String) throws -> [String: String] {
        let key = try encryptionKey()
        var best: [String: String] = [:]
        var lastError: Error?

        for profile in profileDirectories() {
            do {
                let jar = try readProfile(profile, hostPattern: hostPattern, key: key)
                if jar.count > best.count { best = jar }
            } catch {
                lastError = error
            }
        }
        if best.isEmpty, let lastError { throw lastError }
        return best
    }

    private static func readProfile(_ profile: URL, hostPattern: String, key: Data) throws -> [String: String] {
        let fm = FileManager.default
        let src = profile.appendingPathComponent("Cookies")
        let scratch = fm.temporaryDirectory
            .appendingPathComponent("aiquota-ck-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: scratch) }

        // Chrome keeps the live DB locked; work on a copy including any WAL.
        let copy = scratch.appendingPathComponent("Cookies")
        try fm.copyItem(at: src, to: copy)
        for ext in ["-wal", "-shm"] {
            let side = URL(fileURLWithPath: src.path + ext)
            if fm.fileExists(atPath: side.path) {
                try? fm.copyItem(at: side, to: URL(fileURLWithPath: copy.path + ext))
            }
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(copy.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw QuotaError.message("无法打开 Cookies 数据库 (\(profile.lastPathComponent))")
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        let sql = "SELECT host_key, name, encrypted_value FROM cookies WHERE host_key LIKE ?"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw QuotaError.message("Cookies 查询失败")
        }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hostPattern, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        var jar: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let hostC = sqlite3_column_text(stmt, 0),
                  let nameC = sqlite3_column_text(stmt, 1) else { continue }
            let host = String(cString: hostC)
            let name = String(cString: nameC)
            let bytes = sqlite3_column_bytes(stmt, 2)
            guard bytes > 0, let blob = sqlite3_column_blob(stmt, 2) else { continue }
            let enc = Data(bytes: blob, count: Int(bytes))
            if let value = decrypt(enc, hostKey: host, key: key), !value.isEmpty {
                jar[name] = value
            }
        }
        return jar
    }

    /// Ready-to-send `Cookie:` header value.
    static func header(matching hostPattern: String) throws -> String {
        let jar = try cookies(matching: hostPattern)
        guard !jar.isEmpty else {
            throw QuotaError.message("Chrome 里没找到 \(hostPattern) 的 cookie，请先在浏览器登录。")
        }
        return jar.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
}
