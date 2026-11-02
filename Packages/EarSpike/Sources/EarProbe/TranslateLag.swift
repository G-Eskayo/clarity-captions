import Foundation
@preconcurrency import Translation

public struct TranslateTiming: Codable, Sendable {
    public let target: String
    public let coldMs: Double        // first call on a new session (model load)
    public let warm: [Double]        // each caption line after that
    public let lines: [String]       // the translations, reused as the voices' sample text
}

public enum TranslateLag {
    /// Installed pairs only: an installedSource session never shows the download sheet, so it fails fast instead.
    public static func run(target: String, lines: [String]) async throws -> TranslateTiming {
        let session = TranslationSession(installedSource: Locale.Language(identifier: "en"),
                                         target: Locale.Language(identifier: target))
        let c0 = CFAbsoluteTimeGetCurrent()
        let first = try await session.translate(lines[0]).targetText
        let cold = (CFAbsoluteTimeGetCurrent() - c0) * 1000
        var warm: [Double] = []
        var out = [first]
        for line in lines.dropFirst() {
            let t0 = CFAbsoluteTimeGetCurrent()
            out.append(try await session.translate(line).targetText)
            warm.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        return TranslateTiming(target: target, coldMs: cold, warm: warm, lines: out)
    }

    /// Apple's translation when the pair is installed, else the reference translation with no timing.
    public static func linesOrReference(target: String, lines: [String]) async -> (TranslateTiming?, [String]?) {
        if let t = try? await run(target: target, lines: lines) { return (t, t.lines) }
        return (nil, ReferenceTranslations.lines[target])
    }
}
