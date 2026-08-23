import Foundation

/// One measurable quota window, e.g. "Codex weekly, 33% used, resets Fri 14:20".
struct QuotaWindow: Identifiable {
    /// Derived from what the window *is*, not from when it was built.
    ///
    /// A fresh `UUID()` per refresh gave every row a new SwiftUI identity ten
    /// minutes at a time, so the bar was rebuilt rather than animated and
    /// `.animation(value:)` never had a chance to run. Providers keep labels
    /// unique within a card, which is what makes this usable as an id.
    var id: String { key ?? label }

    var label: String
    /// Stable handle for windows the UI has to single out, so nothing has to
    /// match on display text. Only set where it is needed — see `codex.weekly`.
    var key: String?
    /// How much of the window has been consumed, 0...100, as every upstream
    /// source reports it. `nil` when the source gives a balance instead.
    /// The UI never shows this directly — see `remainingPercent`.
    var usedPercent: Double?
    var resetsAt: Date?
    /// Free-form right-hand value, e.g. "¥110.00" or "1 reset credit".
    var value: String?

    /// What is still available — this is what gets displayed.
    var remainingPercent: Double? {
        usedPercent.map { max(0, min(100, 100 - $0)) }
    }

    var isCritical: Bool { (remainingPercent ?? 100) <= 10 }
    var isWarning: Bool { (remainingPercent ?? 100) <= 25 }
}

/// A short line under a card's windows.
///
/// `needsAttention` is set by the provider that wrote the note. The view used
/// to infer it by matching words in the text, which stops working the moment
/// the text is translated.
struct ProviderNote: Identifiable {
    var id: String { text }
    var text: String
    var needsAttention = false
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
    var notes: [ProviderNote] = []
    var error: String?
    var link: URL?
    /// Set when the newest attempt failed and these numbers are the previous
    /// successful reading, kept rather than thrown away. `error` still says why
    /// the refresh failed.
    var isStale = false
    /// When the numbers currently on show were actually read.
    var readAt: Date?

    var tag: String { shortName ?? String(name.prefix(2)) }

    /// The window with the least left in it.
    var tightest: QuotaWindow? {
        windows.filter { $0.remainingPercent != nil }
            .min { ($0.remainingPercent ?? 100) < ($1.remainingPercent ?? 100) }
    }

    func window(key: String) -> QuotaWindow? {
        windows.first { $0.key == key }
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
    /// True when this is the last good reading rather than a fresh one.
    var isStale: Bool
    /// When the number on show was read. Only meaningful while stale.
    var readAt: Date?

    init(tag: String, label: String, window: QuotaWindow,
         isStandIn: Bool, isStale: Bool = false, readAt: Date? = nil) {
        self.tag = tag
        self.label = label
        self.remaining = window.remainingPercent
        self.resetsAt = window.resetsAt
        self.isStandIn = isStandIn
        self.isStale = isStale
        self.readAt = readAt
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

/// Providers are fetched from detached tasks, so they must be safe to hand
/// across threads — every conformer is an immutable struct.
protocol QuotaProvider: Sendable {
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
        if secs <= 0 { return L("time.reset_now") }
        let mins = Int(secs / 60)
        if mins < 60 { return L("time.reset_in_minutes", mins) }
        let hours = mins / 60
        if hours < 24 { return L("time.reset_in_hours", hours) }
        let days = hours / 24
        let remHours = hours % 24
        return remHours == 0 ? L("time.reset_in_days", days) : L("time.reset_in_days_hours", days, remHours)
    }

    /// How long ago something happened, e.g. "3 min ago".
    static func since(_ date: Date?) -> String? {
        guard let date else { return nil }
        let secs = Date().timeIntervalSince(date)
        if secs < 60 { return L("time.just_now") }
        let mins = Int(secs / 60)
        if mins < 60 { return L("time.minutes_ago", mins) }
        let hours = mins / 60
        if hours < 24 { return L("time.hours_ago", hours) }
        return L("time.days_ago", hours / 24)
    }

    static func stamp(_ date: Date?) -> String {
        guard let date else { return L("time.never") }
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
                            window: window, isStandIn: false,
                            isStale: card.isStale, readAt: card.readAt)
        }
        guard let (card, window) = tightestOverall() else { return nil }
        return Headline(tag: card.tag, label: "\(card.name) \(window.label)",
                        window: window, isStandIn: source.pinned != nil,
                        isStale: card.isStale, readAt: card.readAt)
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
