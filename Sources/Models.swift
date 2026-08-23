import Foundation

/// One measurable quota window, e.g. "Codex weekly, 33% used, resets Fri 14:20".
struct QuotaWindow: Identifiable {
    let id = UUID()
    var label: String
    /// How much of the window has been consumed, 0...100, as every upstream
    /// source reports it. `nil` when the source gives a balance instead.
    /// The UI never shows this directly — see `remainingPercent`.
    var usedPercent: Double?
    var resetsAt: Date?
    /// Free-form right-hand value, e.g. "¥110.00" or "1 次重置券".
    var value: String?

    /// What is still available — this is what gets displayed.
    var remainingPercent: Double? {
        usedPercent.map { max(0, min(100, 100 - $0)) }
    }

    var isCritical: Bool { (remainingPercent ?? 100) <= 10 }
    var isWarning: Bool { (remainingPercent ?? 100) <= 25 }
}

/// One AI service and everything we know about its quota right now.
struct ProviderCard: Identifiable {
    var id: String
    var name: String
    var subtitle: String?
    var windows: [QuotaWindow] = []
    var notes: [String] = []
    var error: String?
    var link: URL?

    /// The window with the least left in it — what the menu bar shows.
    var tightest: QuotaWindow? {
        windows.filter { $0.remainingPercent != nil }
            .min { ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100) }
    }
}

struct Snapshot {
    var cards: [ProviderCard] = []
    var updatedAt: Date?
    var refreshing = false
}

protocol QuotaProvider {
    var id: String { get }
    var name: String { get }
    func fetch() async -> ProviderCard
}

enum QuotaError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

// MARK: - Formatting helpers

enum Fmt {
    static func relative(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return "已重置" }
        let mins = Int(secs / 60)
        if mins < 60 { return "\(mins) 分钟后重置" }
        let hours = mins / 60
        if hours < 24 { return "\(hours) 小时后重置" }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? "\(days) 天后重置" : "\(days) 天 \(remHours) 小时后重置"
    }

    static func stamp(_ date: Date?) -> String {
        guard let date else { return "从未" }
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }

    /// Turns "1234567" micro-cents into "$12.35" (opencode stores money this way).
    static func microCents(_ raw: Double, currency: String = "$") -> String {
        String(format: "%@%.2f", currency, raw / 1_000_000.0)
    }
}
