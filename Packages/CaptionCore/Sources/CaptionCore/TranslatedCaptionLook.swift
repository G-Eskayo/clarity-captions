import Foundation

/// #246: how a translated caption looks. A mock-up for the owner to choose from (the screen had grown busy: the
/// translation, what was said underneath, the translate mark and #233's speaker mark). `today` is the look shipped by
/// #171 and #238; the others are the options, reached only through debug demo flags until one is chosen.
public enum TranslatedCaptionLook: String, CaseIterable, Sendable {
    /// #171 / #238: the translate mark before the translation, what was said smaller underneath.
    case today
    /// Option A: no marks. A thin bar down the left side holds the translation and what was said together; it takes
    /// the gear's colour while the voice says the line.
    case bar
    /// Option B: no mark before the translation. What was said starts with a small tag naming its language ("ES");
    /// while the voice says the line, the tag carries the speaker mark.
    case tag
    /// Option C: the translation alone, with a small mark after its last word. A tap on the line opens what was said
    /// underneath; another closes it.
    case folded

    /// The demo flag's value: `a`, `b`, `c`, or `today`.
    public init?(flag: String?) {
        switch flag?.lowercased() {
        case "a": self = .bar
        case "b": self = .tag
        case "c": self = .folded
        case "today": self = .today
        default: return nil
        }
    }

    /// The language tag option B puts before what was said: the language code, upper case ("es-ES" → "ES").
    public static func languageTag(_ identifier: String) -> String? {
        let code = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
        return code.isEmpty ? nil : code.uppercased()
    }

    /// Whether what was said shows under the translation. Folded lines show it only once opened.
    public func showsSaid(opened: Bool) -> Bool { self != .folded || opened }

    /// Whether a mark sits before the translation, as today.
    public var markBeforeTranslation: Bool { self == .today }
}
