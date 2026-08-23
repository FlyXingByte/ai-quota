import Foundation

enum AppInfo {
    static let name = "AI Quota"
    static let version = "1.4.0"
    static let bundleID = "com.flyx.aiquota"
}

/// Which quota the menu bar reads out. The panel always shows everything.
enum MenuBarSource: String, CaseIterable, Hashable {
    case codexWeekly = "codex-weekly"
    case claudeWeekly = "claude-weekly"
    case opencodeWeekly = "opencode-weekly"
    case deepseekBalance = "deepseek-balance"
    case tightest

    var title: String {
        switch self {
        case .codexWeekly: return L("source.codex_weekly")
        case .claudeWeekly: return L("source.claude_weekly")
        case .opencodeWeekly: return L("source.opencode_weekly")
        case .deepseekBalance: return L("source.deepseek_balance")
        case .tightest: return L("source.tightest")
        }
    }

    /// Whether this source has a provider behind it right now. Offering one
    /// that is switched off buys a permanent silent stand-in: the menu bar
    /// quietly reads out something else and nothing says why.
    func isAvailable(in config: Config) -> Bool {
        switch self {
        case .codexWeekly: return config.showCodex
        case .claudeWeekly: return config.showClaude
        case .opencodeWeekly: return config.showOpenCode && !config.opencodeWorkspaceID.isEmpty
        case .deepseekBalance: return config.showDeepSeek
        case .tightest: return true
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
        case .tightest: return nil
        }
    }
}

/// User settings, stored as plain JSON so they are easy to hand-edit.
struct Config: Codable {
    var opencodeWorkspaceID: String = ""
    var refreshMinutes: Int = 10
    var deepseekKeychainService: String = "AI Quota DeepSeek API Key"
    var deepseekKeychainAccount: String = "default"
    var showCodex: Bool = true
    var showClaude: Bool = true
    var showOpenCode: Bool = false
    var showDeepSeek: Bool = false
    /// Stops automatic credential reads until the first-run screen has
    /// explained which enabled sources can trigger a keychain prompt.
    var setupCompleted: Bool = false

    /// What the menu bar reads out. The panel always shows everything.
    ///   "codex-weekly" — Codex's account-wide weekly quota (default)
    ///   "tightest"     — whichever quota has the least left
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
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Config.fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: Config.fileURL.path)
    }

    /// What the menu bar picker offers: the sources that can actually produce a
    /// number, plus whatever is selected right now — a hand-edited config may
    /// name a switched-off source, and the picker still has to be able to show
    /// its own selection.
    var availableMenuBarSources: [MenuBarSource] {
        var list = MenuBarSource.allCases.filter { $0.isAvailable(in: self) }
        if !list.contains(menuBar) { list.append(menuBar) }
        return list
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
        // A decoded file is necessarily an existing installation. Before 1.3.0
        // this key did not exist, so migrate it to completed instead of forcing
        // established users back through onboarding. A truly fresh install has
        // no file and still receives Config().setupCompleted == false.
        // The unfinished first-run flow never writes a file, so any decodable
        // on-disk config belongs to an established installation. This also
        // repairs the short-lived beta that could persist `false` indirectly.
        setupCompleted = true
        menuBarSource = value(.menuBarSource, fallback.menuBarSource)
    }
}
