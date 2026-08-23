import Foundation

enum AppInfo {
    static let name = "AI Quota"
    static let version = "1.1.0"
    static let bundleID = "com.flyx.aiquota"
}

/// User settings, stored as plain JSON so they are easy to hand-edit.
struct Config: Codable {
    var opencodeWorkspaceID: String = ""
    var refreshMinutes: Int = 10
    var deepseekKeychainService: String = "DeepSeek API Key"
    var deepseekKeychainAccount: String = "codex"
    var showCodex: Bool = true
    var showOpenCode: Bool = true
    var showDeepSeek: Bool = true

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIQuota", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else {
            return Config()
        }
        return cfg
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.directory,
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Config.fileURL, options: .atomic)
    }

    var providers: [QuotaProvider] {
        var list: [QuotaProvider] = []
        if showCodex { list.append(CodexProvider()) }
        if showOpenCode, !opencodeWorkspaceID.isEmpty {
            list.append(OpenCodeProvider(workspaceID: opencodeWorkspaceID))
        }
        if showDeepSeek {
            list.append(DeepSeekProvider(keychainService: deepseekKeychainService,
                                         keychainAccount: deepseekKeychainAccount))
        }
        return list
    }
}
