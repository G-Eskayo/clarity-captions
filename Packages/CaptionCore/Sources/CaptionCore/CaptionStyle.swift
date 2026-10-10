import Foundation

/// A color the core can reason about (contrast) without importing any UI framework.
public struct RGBA: Codable, Equatable, Sendable {
    public var r, g, b, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public static let black = RGBA(0, 0, 0)
    public static let white = RGBA(1, 1, 1)

    /// "#RRGGBB", as the design mock-ups write colors. A malformed string is a programming error, so it traps.
    public init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let v = UInt32(digits, radix: 16) else { preconditionFailure("bad hex color \(hex)") }
        self.init(Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// The flat lip under a gummy button (style A, design #96): a dark fill gets a lighter lip, a light fill a darker
    /// one, both by 28%, as the approved mock-ups draw it.
    public var gummyLip: RGBA {
        let amount = 0.28
        func shift(_ v: Double) -> Double { luminance < 0.25 ? v + (1 - v) * amount : v * (1 - amount) }
        return RGBA(shift(r), shift(g), shift(b), a)
    }

    /// Straight-line distance in RGB, for matching a saved color to the nearest theme.
    func distance(to o: RGBA) -> Double { ((r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b)).squareRoot() }

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

/// Lettering choices (#100): an even six, OpenDyslexic first and the default. The first two are fonts bundled in the
/// app (SIL Open Font License); the rest are system designs.
public enum CaptionFont: String, Codable, CaseIterable, Sendable {
    case openDyslexic, atkinsonHyperlegible, system, rounded, serif, monospaced
    public var label: String {
        switch self {
        case .openDyslexic: "OpenDyslexic"   // proper name, not translated
        case .atkinsonHyperlegible: "Atkinson Hyperlegible"
        case .system: String(localized: "Standard")
        case .rounded: String(localized: "Rounded")
        case .serif: String(localized: "Serif")
        case .monospaced: String(localized: "Typewriter")
        }
    }

    /// The bundled face to use, or nil for a system design.
    public func postScriptName(bold: Bool, italic: Bool) -> String? {
        let family: String
        switch self {
        case .openDyslexic: family = "OpenDyslexic"
        case .atkinsonHyperlegible: family = "AtkinsonHyperlegible"
        case .system, .rounded, .serif, .monospaced: return nil
        }
        let face = switch (bold, italic) {
        case (false, false): "Regular"
        case (true, false): "Bold"
        case (false, true): "Italic"
        case (true, true): "BoldItalic"
        }
        return "\(family)-\(face)"
    }

    /// A saved value this build doesn't know (a font removed later) falls back to the default instead of failing.
    public init(from decoder: Decoder) throws {
        self = CaptionFont(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .openDyslexic
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

public enum CaptionDeviceClass: Sendable { case phone, pad }

public enum CaptionTextSize: Int, Codable, CaseIterable, Sendable {
    case smallest, small, medium, large, largest
    private static let basePointSize = 28.0
    private static let padMultiplier = 1.25

    /// Point size for this caption text step at a given system Dynamic Type category.
    public func pointSize(for category: SystemTextSizeCategory, device: CaptionDeviceClass = .phone) -> Double {
        let relativeMultiplier: Double = switch self {
        case .smallest: 0.75
        case .small: 0.875
        case .medium: 1.0
        case .large: 1.15
        case .largest: 1.35
        }
        let deviceMultiplier = device == .pad ? Self.padMultiplier : 1.0
        return Self.basePointSize * relativeMultiplier * deviceMultiplier * category.scale
    }

    public func larger() -> CaptionTextSize { CaptionTextSize(rawValue: rawValue + 1) ?? self }
    public func smaller() -> CaptionTextSize { CaptionTextSize(rawValue: rawValue - 1) ?? self }
}

/// A theme (#103, design #96): background and text plus the colors drawn on them -- the gear, the first two speaker
/// labels and the green of [ Saved ]. A few ready-made themes (ADR 0013) beat free-form pickers. Colors are exactly
/// the approved mock-ups' (docs/design/mocks/2026-10-09); every one must stay at AAA contrast (7:1), and a test
/// enforces it. Dark themes are relaxed for older eyes: no pure black behind, no pure white text (evidence log E1-E3).
public struct CaptionPreset: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let background: RGBA
    public let text: RGBA
    public let gear: RGBA
    public let speakers: [RGBA]
    public let saved: RGBA

    init(id: String, name: String, background: String, text: String, gear: String, speakers: [String], saved: String) {
        self.id = id
        self.name = name
        self.background = RGBA(hex: background)
        self.text = RGBA(hex: text)
        self.gear = RGBA(hex: gear)
        self.speakers = speakers.map { RGBA(hex: $0) }
        self.saved = RGBA(hex: saved)
    }

    /// Three light, then three dark: an equal choice.
    public static let all: [CaptionPreset] = [
        CaptionPreset(id: "paper", name: String(localized: "Paper"), background: "#FAF5E6", text: "#141419",
                      gear: "#14514B", speakers: ["#14514B", "#7A350C"], saved: "#12512F"),
        CaptionPreset(id: "seaglass", name: String(localized: "Sea Glass"), background: "#DCEFEA", text: "#0D2F2C",
                      gear: "#0B4842", speakers: ["#0B4842", "#6E2E0A"], saved: "#12512F"),
        CaptionPreset(id: "peach", name: String(localized: "Peach"), background: "#FBE8D2", text: "#2B1A10",
                      gear: "#6E2E0A", speakers: ["#0B4842", "#6E2E0A"], saved: "#12512F"),
        CaptionPreset(id: "charcoal", name: String(localized: "Charcoal"), background: "#2B2D31", text: "#ECE6D9",
                      gear: "#E2D9C6", speakers: ["#93DCD1", "#F2C994"], saved: "#9BE3B4"),
        CaptionPreset(id: "night", name: String(localized: "Night"), background: "#1D2536", text: "#E9E3D5",
                      gear: "#C9D6F2", speakers: ["#93DCD1", "#F2C994"], saved: "#9BE3B4"),
        CaptionPreset(id: "harbor", name: String(localized: "Harbor"), background: "#173331", text: "#ECE4D3",
                      gear: "#F2DDB5", speakers: ["#A3E3D9", "#F2C994"], saved: "#A6E8BC"),
    ]

    static func named(_ id: String) -> CaptionPreset { all.first { $0.id == id }! }

    /// The theme whose two colors these are, if any.
    public static func matching(background: RGBA, text: RGBA) -> CaptionPreset? {
        all.first { $0.background == background && $0.text == text }
    }

    /// The themes before v1, by their exact saved colors: Classic and Bright (retired) become Charcoal, which replaced
    /// Classic; Paper and Night keep their names.
    private static let legacy: [(background: RGBA, text: RGBA, becomes: String)] = [
        (.black, .white, "charcoal"),
        (.black, RGBA(1.0, 0.9, 0.2), "charcoal"),
        (RGBA(0.98, 0.96, 0.90), RGBA(0.08, 0.08, 0.10), "paper"),
        (RGBA(0.05, 0.07, 0.15), RGBA(0.85, 0.90, 1.0), "night"),
    ]

    /// The closest current theme to colors saved by an older build: an old theme by name, else the nearest current
    /// theme, else by darkness.
    static func nearest(background: RGBA, text: RGBA) -> CaptionPreset {
        if let old = legacy.first(where: { $0.background.distance(to: background) < 0.01 && $0.text.distance(to: text) < 0.01 }) {
            return named(old.becomes)
        }
        func gap(_ p: CaptionPreset) -> Double { p.background.distance(to: background) + p.text.distance(to: text) }
        let best = all.min { gap($0) < gap($1) }!
        if gap(best) < 0.15 { return best }
        return named(background.isDark ? "charcoal" : "paper")
    }
}

public struct CaptionStyle: Codable, Equatable, Sendable {
    public var background: RGBA
    public var text: RGBA
    public var size: CaptionTextSize
    public var font: CaptionFont
    public var emphasisEffectsEnabled: Bool = true

    /// Charcoal replaces Classic, the old default; OpenDyslexic is the default lettering (#100).
    public static let standard = CaptionStyle(
        background: CaptionPreset.named("charcoal").background, text: CaptionPreset.named("charcoal").text,
        size: .medium, font: .openDyslexic, emphasisEffectsEnabled: true)

    /// The theme these colors belong to (nil only for colors no theme has).
    public var preset: CaptionPreset? { CaptionPreset.matching(background: background, text: text) }
    /// The gear and other small controls on this look.
    public var gear: RGBA { preset?.gear ?? text }
    /// The green of [ ✔ ] and [ Saved ] on this look.
    public var saved: RGBA { preset?.saved ?? text }

    /// How faint a caption still being heard is drawn: CaptionLine.volatileOpacity, raised just enough on a look where
    /// that would fall below 4.5:1, so unfinished words stay readable (the light Sea Glass and Peach need it).
    public var volatileOpacity: Double {
        var opacity = CaptionLine.volatileOpacity
        while opacity < 1, RGBA.contrast(RGBA(text.r, text.g, text.b, opacity).composited(over: background), background) < 4.5 {
            opacity = min(1, opacity + 0.01)
        }
        return opacity
    }

    /// A preset changes the two colors only; the user's size and font choices stay.
    public func applying(_ preset: CaptionPreset) -> CaptionStyle {
        var s = self
        s.background = preset.background
        s.text = preset.text
        return s
    }
}

/// Saves the style between launches. Unreadable saved data never blocks the app: it falls back to standard.
/// A style saved by a build before the v1 themes (#103) is moved over once: its colors become the nearest current
/// theme, and the old default lettering (Standard) becomes the new default (OpenDyslexic); a font the user picked stays.
public struct CaptionStyleStore {
    public static let key = "captionStyle.v2"
    public static let legacyKey = "captionStyle.v1"
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func load() -> CaptionStyle {
        if let data = defaults.data(forKey: Self.key) {
            guard let style = try? JSONDecoder().decode(CaptionStyle.self, from: data) else { return .standard }
            return Self.snappedToTheme(style)
        }
        guard let data = defaults.data(forKey: Self.legacyKey) else { return .standard }
        defaults.removeObject(forKey: Self.legacyKey)
        guard var style = try? JSONDecoder().decode(CaptionStyle.self, from: data) else { return .standard }
        if style.font == .system { style.font = .openDyslexic }
        style = Self.snappedToTheme(style)
        save(style)
        return style
    }

    public func save(_ style: CaptionStyle) {
        if let data = try? JSONEncoder().encode(style) { defaults.set(data, forKey: Self.key) }
    }

    /// Colors that aren't exactly a theme's are moved to the nearest one, so every look has its gear and label colors.
    static func snappedToTheme(_ style: CaptionStyle) -> CaptionStyle {
        if style.preset != nil { return style }
        return style.applying(CaptionPreset.nearest(background: style.background, text: style.text))
    }
}

/// Speaker label colors that stay readable on whatever look is chosen. Dark backgrounds get light tints,
/// light backgrounds get deep shades; any color that still falls short of 4.5:1 is replaced by the text color
/// nudged toward the background, so the labels stay distinguishable by wording even then.
public enum SpeakerPalette {
    private static let onDark: [RGBA] = [RGBA(0.45, 0.70, 1.0), RGBA(1.0, 0.65, 0.30), RGBA(0.80, 0.60, 1.0), RGBA(0.35, 0.85, 0.80)]
    private static let onLight: [RGBA] = [RGBA(0.05, 0.25, 0.65), RGBA(0.65, 0.25, 0.0), RGBA(0.40, 0.10, 0.60), RGBA(0.0, 0.40, 0.38)]

    public static func colors(on background: RGBA, text: RGBA) -> [RGBA] {
        let generic = genericColors(on: background, text: text)
        // A theme names its first two speaker colors (design #96); slots 3 and 4 keep the generic palette, skipping any
        // that would repeat a theme color.
        guard let theme = CaptionPreset.matching(background: background, text: text) else { return generic }
        let rest = generic.filter { c in !theme.speakers.contains(c) }
        return Array((theme.speakers + rest).prefix(4))
    }

    private static func genericColors(on background: RGBA, text: RGBA) -> [RGBA] {
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

    /// A quieter placeholder color for pending/unknown speaker labels. Aims for ~3.0:1 contrast on the given
    /// background, readable but noticeably muted compared to resolved speaker colors (which maintain 4.5:1+).
    public static func placeholderColor(on background: RGBA, text: RGBA) -> RGBA {
        // Start with a muted tone: blend text toward background, roughly halfway.
        let midpoint = RGBA(
            (text.r + background.r) / 2,
            (text.g + background.g) / 2,
            (text.b + background.b) / 2
        )
        let midContrast = RGBA.contrast(midpoint, background)
        if midContrast >= 3.0 { return midpoint }

        // If midpoint is too faint, nudge toward text to reach 3.0:1 target.
        var result = midpoint
        let step = 0.01
        while RGBA.contrast(result, background) < 3.0 {
            if background.isDark {
                result = RGBA(
                    min(1, result.r + step),
                    min(1, result.g + step),
                    min(1, result.b + step)
                )
            } else {
                result = RGBA(
                    max(0, result.r - step),
                    max(0, result.g - step),
                    max(0, result.b - step)
                )
            }
        }
        return result
    }
}
