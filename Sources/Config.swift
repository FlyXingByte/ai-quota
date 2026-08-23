import Foundation

enum AppInfo {
    static let name = "AI Quota"
    static let version = "1.1.0"
    static let bundleID = "com.flyx.aiquota"
}

/// Which quota the menu bar reads out. The panel always shows everything.
enum MenuBarSource: String, CaseIterable, Hashable {
    case codexWeekly = "codex-weekly"
    case claudeWeekly = "claude-weekly"
    case opencodeWeekly = "opencode-weekly"
    case deepseekBalance = "deepseek-balance"
    case tightest
    case all

    var title: String {
        switch self {
        case .codexWeekly: return "Codex 每周额度"
        case .claudeWeekly: return "Claude 每周额度"
        case .opencodeWeekly: return "OpenCode 每周额度"
        case .deepseekBalance: return "DeepSeek 余额"
        case .tightest: return "剩余最少的"
        case .all: return "全部并排"
        }
    }

    /// The card and window this source pins to. `nil` for the modes that pick
    /// a window dynamically rather than naming one.
    var pinned: (cardID: String, windowKey: String)? {
        switch self {
        case .codexWeekly: return ("codex", CodexProvider.weeklyKey)
        case .claudeWeekly: return ("claude", ClaudeProvider.weeklyKey)
        case .opencodeWeekly: return ("opencode", OpenCodeProvider.weeklyKey)
        case .deepseekBalance: return ("deepseek", DeepSeekProvider.balanceKey)
        case .tightest, .all: return nil
        }
    }
}

/// User settings, stored as plain JSON so they are easy to hand-edit.
struct Config: Codable {
    var opencodeWorkspaceID: String = ""
    var refreshMinutes: Int = 10
    var deepseekKeychainService: String = "DeepSeek API Key"
    var deepseekKeychainAccount: String = "codex"
    var showCodex: Bool = true
    var showClaude: Bool = true
    var showOpenCode: Bool = true
    var showDeepSeek: Bool = true

    /// What the menu bar reads out. The panel always shows everything.
    ///   "codex-weekly" — Codex's account-wide weekly quota (default)
    ///   "tightest"     — whichever quota has the least left
    ///   "all"          — every source side by side
    var menuBarSource: String = MenuBarSource.codexWeekly.rawValue

    var menuBar: MenuBarSource {
        MenuBarSource(rawValue: menuBarSource) ?? .codexWeekly
    }

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AIQuota", isDirectory: true)
    }
    static var fileURL: URL { directory.appendingPathComponent("config.json") }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL) else { return Config() }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
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
        if showClaude { list.append(ClaudeProvider()) }
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

/// Decoded field by field with defaults for anything absent.
///
/// The synthesized `Decodable` throws on a missing key, and `load()` treats a
/// throw as "use defaults" — so simply adding a new setting would silently reset
/// every existing one, `opencodeWorkspaceID` included. Declared in an extension
/// so the memberwise initializer survives.
extension Config {
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config()

        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? box.decodeIfPresent(T.self, forKey: key)) .flatMap { $0 } ?? fallback
        }

        self.init()
        opencodeWorkspaceID = value(.opencodeWorkspaceID, fallback.opencodeWorkspaceID)
        refreshMinutes = value(.refreshMinutes, fallback.refreshMinutes)
        deepseekKeychainService = value(.deepseekKeychainService, fallback.deepseekKeychainService)
        deepseekKeychainAccount = value(.deepseekKeychainAccount, fallback.deepseekKeychainAccount)
        showCodex = value(.showCodex, fallback.showCodex)
        showClaude = value(.showClaude, fallback.showClaude)
        showOpenCode = value(.showOpenCode, fallback.showOpenCode)
        showDeepSeek = value(.showDeepSeek, fallback.showDeepSeek)
        menuBarSource = value(.menuBarSource, fallback.menuBarSource)
    }
}
