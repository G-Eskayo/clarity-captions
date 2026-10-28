import Foundation

/// The Listening light (#180): red, following the room in colour, never in size (owner, 2026-10-28: option C).
/// Brighter while people talk, softer when it's quiet. The colours live here, free of any UI framework, so the
/// iPhone and Mac apps draw the same light.
public enum ListeningLight {
    /// How far the quietest room fades the light toward the background. 0.2 keeps it at 3:1 or better on every look
    /// (WCAG 1.4.11 non-text contrast), so a quiet room never makes it look switched off.
    static let quietDepth = 0.2

    /// The light's colour for this room level. Reduce Motion: steady full red, whatever the room does.
    public static func color(on background: RGBA, roomLevelDBFS: Double?, reduceMotion: Bool) -> RGBA {
        let red = red(on: background)
        if reduceMotion { return red }
        return red.mixed(with: background, by: quietDepth * (1 - brightness(roomLevelDBFS: roomLevelDBFS)))
    }

    /// Full red: the Stop circle's red on a light look, a lighter red on a dark look so it still reads.
    static func red(on background: RGBA) -> RGBA {
        background.isDark ? RGBA(1.0, 0.36, 0.33) : RGBA(0.80, 0.12, 0.12)
    }

    /// 0 (quiet, -60 dBFS or below, or no reading) ... 1 (loud, -30 dBFS or above).
    static func brightness(roomLevelDBFS: Double?) -> Double {
        guard let level = roomLevelDBFS, !level.isNaN else { return 0 }
        return min(max((level + 60) / 30, 0), 1)
    }
}

/// How buttons answer a press (#180, approved as shown 2026-10-28), shared so the iPhone and Mac apps feel the same.
public enum PressFeedback {
    /// Icon buttons (gear, saved list, close, back): dim and give a little.
    public static let iconPressedOpacity = 0.5
    public static let iconScale = 0.88
    /// The round highlight behind an icon on Mac hover: the icon's colour at this opacity.
    public static let hoverOpacity = 0.12
    /// The Stop circle: darkens and gives a little.
    public static let stopDarken = 0.22
    public static let stopScale = 0.92
    /// The spring every press uses; Reduce Motion drops the give and keeps a quick fade.
    public static let springResponse = 0.22
    public static let springDamping = 0.55
}

extension RGBA {
    /// This colour moved `amount` (0...1) of the way to `other`.
    func mixed(with other: RGBA, by amount: Double) -> RGBA {
        let t = min(max(amount, 0), 1)
        return RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }
}
