import Foundation

/// Localized lookup. Every key lives in `Resources/<lang>.lproj/Localizable.strings`;
/// `scripts/check-localization.sh` fails the build if a key used here is missing
/// from either table, or if a table carries a key nothing uses.
///
/// English is the development language, so an unlocalized build (or a locale we
/// do not ship) still reads sensibly rather than falling back to raw keys.
func L(_ key: String) -> String {
    NSLocalizedString(key, bundle: .main, comment: "")
}

/// Formatted variant. Placeholders are positional (`%1$@`) wherever the two
/// languages need a different word order.
func L(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, bundle: .main, comment: ""),
           locale: .current, arguments: arguments)
}
