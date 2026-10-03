import Foundation

/// A color the core can reason about (contrast) without importing any UI framework.
public struct RGBA: Codable, Equatable, Sendable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)

    /// WCAG relative luminance.
    var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG contrast ratio, 1...21. 7 is the AAA bar for normal text.
    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }
}

public enum CaptionFont: String, Codable, CaseIterable, Sendable {
    case system, rounded, serif, monospaced
    public var label: String {
        switch self {
        case .system: "Standard"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .monospaced: "Typewriter"
        }
    }
}

public enum CaptionTextSize: Int, Codable, CaseIterable, Sendable {
    case small, medium, large, extraLarge
    public var points: Double {
        switch self {
        case .small: 22
        case .medium: 28
        case .large: 36
        case .extraLarge: 46
        }
    }
    public func larger() -> CaptionTextSize { CaptionTextSize(rawValue: rawValue + 1) ?? self }
    public func smaller() -> CaptionTextSize { CaptionTextSize(rawValue: rawValue - 1) ?? self }
}

/// A ready-made pair of colors. Offering a few presets (ADR 0013) beats offering free-form pickers.
public struct CaptionPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let background: RGBA
    public let text: RGBA

    /// Every preset must stay at AAA contrast (7:1); a test enforces it.
    public static let all: [CaptionPreset] = [
        CaptionPreset(id: "classic", name: "Classic", background: .black, text: .white),
        CaptionPreset(id: "bright", name: "Bright", background: .black, text: RGBA(1.0, 0.9, 0.2)),
        CaptionPreset(id: "paper", name: "Paper", background: RGBA(0.98, 0.96, 0.90), text: RGBA(0.08, 0.08, 0.10)),
        CaptionPreset(id: "night", name: "Night", background: RGBA(0.05, 0.07, 0.15), text: RGBA(0.85, 0.90, 1.0)),
    ]
}

public struct CaptionStyle: Codable, Equatable, Sendable {
    public var background: RGBA
    public var text: RGBA
    public var size: CaptionTextSize
    public var font: CaptionFont

    public static let standard = CaptionStyle(
        background: CaptionPreset.all[0].background, text: CaptionPreset.all[0].text, size: .medium, font: .system)

    /// A preset changes the two colors only; the user's size and font choices stay.
    public func applying(_ preset: CaptionPreset) -> CaptionStyle {
        var s = self
        s.background = preset.background
        s.text = preset.text
        return s
    }
}

/// Saves the style between launches. Unreadable saved data never blocks the app: it falls back to standard.
public struct CaptionStyleStore {
    public static let key = "captionStyle.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> CaptionStyle {
        guard let data = defaults.data(forKey: Self.key),
              let style = try? JSONDecoder().decode(CaptionStyle.self, from: data) else { return .standard }
        return style
    }

    public func save(_ style: CaptionStyle) {
        if let data = try? JSONEncoder().encode(style) { defaults.set(data, forKey: Self.key) }
    }
}
