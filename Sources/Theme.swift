import AppKit
import SwiftUI

/// Visual tokens for the compact "Calm Dashboard" interface.
///
/// The normal quota colour deliberately uses macOS system blue instead of
/// green: blue carries the app identity, while orange and red remain reserved
/// for states that need attention. System colours keep every token adaptive in
/// light, dark, and increased-contrast appearances.
enum QuotaTheme {
    static let brand = Color(nsColor: .systemBlue)
    static let cardFill = Color(nsColor: .controlBackgroundColor).opacity(0.58)
    static let cardStroke = Color(nsColor: .separatorColor).opacity(0.32)
    static let track = Color.secondary.opacity(0.14)

    static func quotaColor(for remaining: Double) -> Color {
        if remaining <= 10 { return .red }
        if remaining <= 25 { return .orange }
        return brand
    }

    /// A menu bar extra should stay quiet until something needs attention.
    static func menuBarColor(for remaining: Double) -> NSColor {
        if remaining <= 10 { return .systemRed }
        if remaining <= 25 { return .systemOrange }
        return .labelColor
    }
}

enum FeedbackTone: Equatable {
    case neutral
    case success
    case error

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return QuotaTheme.brand
        case .error: return .red
        }
    }
}

struct FeedbackMessage {
    var text: String
    var tone: FeedbackTone
}

/// Sizing for the status item, kept out of the app delegate so it can be
/// exercised on its own.
enum MenuBarMetrics {
    /// Fits the item to what it actually draws.
    ///
    /// A fixed 36pt was enough for "57%" and silently clipped anything longer —
    /// balance sources read out things like "¥1234". Capped as well as floored:
    /// a menu bar extra that grows without limit is how items get pushed off a
    /// crowded bar, or under the notch.
    static let minimumWidth: CGFloat = 32
    static let maximumWidth: CGFloat = 68

    /// The top line is a fixed "AI"; only the value line varies. Computed
    /// rather than stored: a stored NSFont is shared mutable state as far as
    /// the concurrency checker is concerned.
    static var topLabelFont: NSFont { .systemFont(ofSize: 8.5, weight: .medium) }

    static func width(for readout: NSAttributedString) -> CGFloat {
        let label = ("AI" as NSString).size(withAttributes: [.font: topLabelFont]).width
        let padding: CGFloat = 6  // 2pt leading + 1pt trailing, plus breathing room
        let needed = ceil(max(label, readout.size().width)) + padding
        return min(max(needed, minimumWidth), maximumWidth)
    }
}
