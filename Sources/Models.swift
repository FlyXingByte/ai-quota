import Foundation

/// One measurable quota window, e.g. "Codex weekly, 33% used, resets Fri 14:20".
struct QuotaWindow: Identifiable {
    let id = UUID()
    var label: String
    /// Stable handle for windows the UI has to single out, so nothing has to
    /// match on display text. Only set where it is needed — see `codex.weekly`.
    var key: String?
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
    /// Two-or-three letter tag for the menu bar readout, where the full name
    /// would not fit. Defaults to the first two letters of `name`.
    var shortName: String?
    var subtitle: String?
    var windows: [QuotaWindow] = []
    var notes: [String] = []
    var error: String?
    var link: URL?

    var tag: String { shortName ?? String(name.prefix(2)) }

    /// The window with the least left in it.
    var tightest: QuotaWindow? {
        windows.filter { $0.remainingPercent != nil }
            .min { ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100) }
    }

    func window(key: String) -> QuotaWindow? {
        windows.first { $0.key == key }
    }

    /// What a one-line readout shows for this source: the window the provider
    /// tagged as the one that governs, else whichever has least left in it.
    var headlineWindow: QuotaWindow? {
        windows.first { $0.key != nil } ?? tightest
    }
}

/// The single quota the menu bar reads out. Resolved in one place so the
/// running app and `--probe` can never disagree about it.
struct Headline {
    var tag: String
    var label: String
    /// What gets drawn: "57%" for a window, "¥48.39" for a balance.
    var text: String
    /// Percentage left, when the source reports one. Drives the colour and the
    /// gauge needle; `nil` for balance-style sources, which have no ceiling to
    /// measure against.
    var remaining: Double?
    var resetsAt: Date?
    /// True when the chosen source was unavailable and something else is filling
    /// in — the tooltip says which, so the number is never mistaken for the one
    /// that was asked for.
    var isStandIn: Bool

    init(tag: String, label: String, window: QuotaWindow, isStandIn: Bool) {
        self.tag = tag
        self.label = label
        self.remaining = window.remainingPercent
        self.resetsAt = window.resetsAt
        self.isStandIn = isStandIn
        if let remaining = window.remainingPercent {
            self.text = "\(Int(remaining))%"
        } else {
            self.text = Fmt.compact(window.value ?? "—")
        }
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

    /// Menu bar width is scarce and trailing cents never matter at a glance.
    static func compact(_ value: String) -> String {
        guard let dot = value.lastIndex(of: ".") else { return value }
        let decimals = value[value.index(after: dot)...]
        guard decimals.count == 2, decimals.allSatisfy(\.isNumber) else { return value }
        return String(value[..<dot])
    }
}

extension Snapshot {
    /// Defaults to Codex's account-wide weekly window — the number that governs
    /// a week of work — so the readout stays on one quota instead of hopping
    /// between sources as usage shifts. When that window is missing (Codex off,
    /// logged out, unreachable) the tightest quota anywhere stands in, flagged
    /// so the tooltip can say it is a substitute rather than the real thing.
    func headline(for source: MenuBarSource) -> Headline? {
        if let pin = source.pinned,
           let card = cards.first(where: { $0.id == pin.cardID }),
           let window = card.window(key: pin.windowKey) {
            return Headline(tag: card.tag, label: "\(card.name) \(window.label)",
                            window: window, isStandIn: false)
        }
        guard let (card, window) = tightestOverall() else { return nil }
        return Headline(tag: card.tag, label: "\(card.name) \(window.label)",
                        window: window, isStandIn: source.pinned != nil)
    }

    private func tightestOverall() -> (ProviderCard, QuotaWindow)? {
        var best: (ProviderCard, QuotaWindow)?
        for card in cards {
            guard let window = card.tightest,
                  let remaining = window.remainingPercent else { continue }
            if best == nil || remaining < (best!.1.remainingPercent ?? 100) {
                best = (card, window)
            }
        }
        return best
    }
}
