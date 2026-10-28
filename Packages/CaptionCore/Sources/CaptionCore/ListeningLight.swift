import Foundation

/// The Listening light (#180): red, breathing in colour, never in size. The colours and timings live here, free of
/// any UI framework, so the iPhone and Mac apps draw the same light.
public enum ListeningLight {
    /// How the light breathes. The owner picks one (#180 Decisions); the others are mock-up options.
    public enum Pulse: String, CaseIterable, Sendable {
        /// A slow breathe: bright red to a soft red and back, 2.4 s a breath.
        case gentle
        /// The same breathe, quicker and deeper: 1.4 s a breath.
        case steady
        /// No timer: brighter when the room is louder, softer when it's quiet (the old grey dot's behaviour, in red).
        case room
    }

    /// Seconds for one breath (bright → soft → bright); nil when the light follows the room instead.
    public static func period(_ pulse: Pulse) -> Double? {
        switch pulse {
        case .gentle: 2.4
        case .steady: 1.4
        case .room: nil
        }
    }

    /// How far the soft end of a breath fades toward the background, 0...1.
    public static func depth(_ pulse: Pulse) -> Double {
        switch pulse {
        case .gentle: 0.55
        case .steady: 0.7
        case .room: 0.7
        }
    }

    /// The bright end: the Stop circle's red on a light look, a lighter red on a dark look so it still reads.
    public static func red(on background: RGBA) -> RGBA {
        background.isDark ? RGBA(1.0, 0.36, 0.33) : RGBA(0.80, 0.12, 0.12)
    }

    /// The soft end of a breath: the red faded `depth` of the way toward the background.
    public static func soft(on background: RGBA, pulse: Pulse) -> RGBA {
        red(on: background).mixed(with: background, by: depth(pulse))
    }

    /// For `.room`: 0 (quiet, soft end) ... 1 (loud, bright end), from the room level in dBFS (-60 quiet, -30 loud).
    public static func brightness(roomLevelDBFS: Double?) -> Double {
        min(max(((roomLevelDBFS ?? -60) + 60) / 30, 0), 1)
    }
}

extension RGBA {
    /// This colour moved `amount` (0...1) of the way to `other`.
    public func mixed(with other: RGBA, by amount: Double) -> RGBA {
        let t = min(max(amount, 0), 1)
        return RGBA(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t, a + (other.a - a) * t)
    }
}
