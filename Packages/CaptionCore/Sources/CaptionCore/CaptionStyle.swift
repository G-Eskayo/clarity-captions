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

    /// True for dark backgrounds, so the whole app can switch its system controls to match.
    public var isDark: Bool { luminance < 0.4 }

    /// WCAG contrast ratio, 1...21. 7 is the AAA bar for normal text.
    public static func contrast(_ a: RGBA, _ b: RGBA) -> Double {
        let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
        return (hi + 0.05) / (lo + 0.05)
    }

    /// Alpha-composite this color over a background, returning the visible result.
    public func composited(over background: RGBA) -> RGBA {
        let outAlpha = a + background.a * (1 - a)
        if outAlpha == 0 { return RGBA(0, 0, 0, 0) }
        let inv = 1 / outAlpha
        return RGBA(
            (r * a + background.r * background.a * (1 - a)) * inv,
            (g * a + background.g * background.a * (1 - a)) * inv,
            (b * a + background.b * background.a * (1 - a)) * inv,
            outAlpha
        )
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

/// System text size category, mirroring DynamicTypeSize / UIContentSizeCategory, with published point sizes from Apple for `.body`.
public enum SystemTextSizeCategory: Int, Codable, CaseIterable, Equatable, Sendable {
    case extraSmall, small, medium, large, extraLarge, extraExtraLarge, extraExtraExtraLarge
    case accessibilityMedium, accessibilityLarge, accessibilityExtraLarge, accessibilityExtraExtraLarge, accessibilityExtraExtraExtraLarge

    /// The `.body` point size for this category, per Apple's published typography metrics.
    public var bodyPointSize: Double {
        switch self {
        case .extraSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .extraLarge: 19
        case .extraExtraLarge: 21
        case .extraExtraExtraLarge: 23
        case .accessibilityMedium: 28
        case .accessibilityLarge: 33
        case .accessibilityExtraLarge: 40
        case .accessibilityExtraExtraLarge: 47
        case .accessibilityExtraExtraExtraLarge: 53
        }
    }

    /// Scale relative to `.large` (the system default), to let caption sizes track system Dynamic Type.
    public var scale: Double {
        let largeSize = SystemTextSizeCategory.large.bodyPointSize
        return bodyPointSize / largeSize
    }
}

public enum CaptionTextSize: Int, Codable, CaseIterable, Sendable {
    case smallest, small, medium, large, largest
    private static let basePointSize = 28.0

    /// Point size for this caption text step at a given system Dynamic Type category.
    public func pointSize(for category: SystemTextSizeCategory) -> Double {
        let relativeMultiplier: Double = switch self {
        case .smallest: 0.75
        case .small: 0.875
        case .medium: 1.0
        case .large: 1.15
        case .largest: 1.35
        }
        return Self.basePointSize * relativeMultiplier * category.scale
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

/// Speaker label colors that stay readable on whatever look is chosen. Dark backgrounds get light tints,
/// light backgrounds get deep shades; any color that still falls short of 4.5:1 is replaced by the text color
/// nudged toward the background, so the labels stay distinguishable by wording even then.
public enum SpeakerPalette {
    private static let onDark: [RGBA] = [RGBA(0.45, 0.70, 1.0), RGBA(1.0, 0.65, 0.30), RGBA(0.80, 0.60, 1.0), RGBA(0.35, 0.85, 0.80)]
    private static let onLight: [RGBA] = [RGBA(0.05, 0.25, 0.65), RGBA(0.65, 0.25, 0.0), RGBA(0.40, 0.10, 0.60), RGBA(0.0, 0.40, 0.38)]

    public static func colors(on background: RGBA, text: RGBA) -> [RGBA] {
        let candidates = background.isDark ? onDark : onLight
        return candidates.enumerated().map { i, c in
            if RGBA.contrast(c, background) >= 4.5 { return c }
            // Fallback keeps contrast by staying close to the (already high-contrast) text color.
            let d = Double(i) * 0.02
            return RGBA(min(1, max(0, text.r + (background.isDark ? -d : d))),
                        min(1, max(0, text.g + (background.isDark ? -d : d))),
                        min(1, max(0, text.b + (background.isDark ? -d : d))))
        }
    }
}
