import Foundation

/// Emphasis level for a word: none, raised (slight emphasis), or loud (strong emphasis).
public enum EmphasisLevel: Equatable, Sendable {
    case none
    case raised
    case loud
}

/// Classifies a loudness level against a speaker's baseline.
public struct EmphasisClassifier: Sendable {
    private let raisedThreshold: Double = 3.0
    private let loudThreshold: Double = 6.0

    /// Classify a loudness level relative to baseline; returns .none during cold start.
    public func classify(level: Double, baseline: LoudnessBaseline) -> EmphasisLevel {
        guard baseline.isTrusted, let baselineLevel = baseline.current else { return .none }
        let delta = level - baselineLevel
        if delta >= loudThreshold { return .loud }
        if delta >= raisedThreshold { return .raised }
        return .none
    }
}

/// Styling for emphasized words: font weight, size multiplier, and color.
public struct EmphasisStyle: Sendable {
    public let fontWeight: Double
    public let sizeMultiplier: Double
    public let accentColor: RGBA

    /// Map emphasis level to visual styling against a specific background/text color.
    /// Size is capped to prevent accessibility override.
    public static func style(for level: EmphasisLevel, background: RGBA, text: RGBA) -> EmphasisStyle {
        switch level {
        case .none:
            return EmphasisStyle(fontWeight: 400, sizeMultiplier: 1.0, accentColor: text)

        case .raised:
            let color = deriveAccentColor(level: .raised, background: background, text: text)
            return EmphasisStyle(fontWeight: 600, sizeMultiplier: 1.05, accentColor: color)

        case .loud:
            let color = deriveAccentColor(level: .loud, background: background, text: text)
            return EmphasisStyle(fontWeight: 700, sizeMultiplier: 1.12, accentColor: color)
        }
    }

    /// Derive a high-contrast accent color for the emphasis level.
    /// Uses the same strategy as SpeakerPalette: start with a tinted candidate, verify contrast, fallback to text nudge if needed.
    private static func deriveAccentColor(level: EmphasisLevel, background: RGBA, text: RGBA) -> RGBA {
        let candidates: [RGBA] = background.isDark
            ? [RGBA(1.0, 0.7, 0.3), RGBA(0.5, 0.9, 1.0), RGBA(1.0, 0.5, 0.8)]
            : [RGBA(0.9, 0.5, 0.1), RGBA(0.0, 0.5, 0.8), RGBA(0.7, 0.0, 0.5)]
        let candidate = candidates[level == .loud ? 0 : 1]

        if RGBA.contrast(candidate, background) >= 4.5 { return candidate }

        var result = text
        let step = background.isDark ? 0.05 : -0.05
        while RGBA.contrast(result, background) < 4.5 {
            result = RGBA(
                min(1, max(0, result.r + step)),
                min(1, max(0, result.g + step)),
                min(1, max(0, result.b + step))
            )
        }
        return result
    }
}
