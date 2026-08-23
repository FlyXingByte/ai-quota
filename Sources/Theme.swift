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
    case warning
    case error

    var color: Color {
        switch self {
        case .neutral: return .secondary
        case .success: return QuotaTheme.brand
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct FeedbackMessage {
    var text: String
    var tone: FeedbackTone
}
