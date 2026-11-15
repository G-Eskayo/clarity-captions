import Foundation

/// Tracks delays in the ear/translation pipeline: when translations arrive, when voice starts, how far behind the backlog grows.
/// One key per phrase (lineID + first word's start time); entries are evicted when older than the age cap.
/// Time complexity: O(1) per event; space: O(1) regardless of session length (capped tables).
public struct EarDelayRecorder: Codable, Equatable, Sendable {
    // The three measured delays, each with a PercentileHistogram and an exact running max.
    private var voiceStartDelayHistogram = PercentileHistogram(lower: 0, upper: 5, binWidth: 0.02)
    private var voiceStartDelayMax = 0.0
    private var translationReadyDelayHistogram = PercentileHistogram(lower: 0, upper: 5, binWidth: 0.02)
    private var translationReadyDelayMax = 0.0
    private var behindByHistogram = PercentileHistogram(lower: 0, upper: 5, binWidth: 0.02)
    private var behindByMax = 0.0
    private var repeatCount = 0

    /// An open phrase: timestamps for when it ended on screen and subsequent milestones.
    private struct OpenPhrase: Codable, Equatable, Sendable {
        var ended: Date
        var voiceStarted: Date?
        var voiceEnded: Date?
        var translationReady: Date?
    }

    /// Phrases not yet resolved: key = "\(lineID)|\(wordStartInterval)"
    private var open: [String: OpenPhrase] = [:]

    /// Recent finalized lines: key = hash of normalized text, value = most recent finalization time
    /// Capped at 500 entries to bound memory for a 2-hour session.
    private var recentFinals: [Int: Date] = [:]
    private static let maxRecentFinals = 500
    private static let ageCap: TimeInterval = 120  // 2 minutes, plenty for normal overlaps
    private var lastVoiceEndTime: Date?

    public init() {}

    /// Called when a phrase ends on screen, before translation/voice start are known.
    public mutating func phraseEnded(lineID: Int, wordStart: Date, at endDate: Date) {
        let key = Self.key(lineID: lineID, wordStart: wordStart)
        guard open[key] == nil else { return }  // idempotency: already tracking this phrase
        open[key] = OpenPhrase(ended: endDate, voiceStarted: nil, voiceEnded: nil, translationReady: nil)
    }

    /// Translation arrived for a phrase. If translation came before voice start, it doesn't contribute to any delay here.
    public mutating func translationReady(lineID: Int, wordStart: Date, at date: Date) {
        let key = Self.key(lineID: lineID, wordStart: wordStart)
        guard var entry = open[key] else { return }  // no matching phraseEnded: safe no-op
        guard entry.translationReady == nil else { return }  // idempotency
        entry.translationReady = date
        open[key] = entry
    }

    /// Voice started for a phrase.
    public mutating func voiceStarted(lineID: Int, wordStart: Date, at date: Date) {
        let key = Self.key(lineID: lineID, wordStart: wordStart)
        guard var entry = open[key] else { return }  // no matching phraseEnded: safe no-op
        guard entry.voiceStarted == nil else { return }  // idempotency

        let voiceStartDelay = max(0, date.timeIntervalSince(entry.ended))
        voiceStartDelayHistogram.add(voiceStartDelay)
        voiceStartDelayMax = max(voiceStartDelayMax, voiceStartDelay)

        // Translation-ready delay: only if translation arrived before voice.
        if let transReady = entry.translationReady {
            let translationDelay = max(0, transReady.timeIntervalSince(entry.ended))
            translationReadyDelayHistogram.add(translationDelay)
            translationReadyDelayMax = max(translationReadyDelayMax, translationDelay)
        }

        // Behind-by: how much is the speaker behind compared to previous phrase's voice end.
        // If previous voice hasn't ended yet, the backlog is growing.
        if let prevVoiceEnd = lastVoiceEndTime {
            let behindBy = max(0, date.timeIntervalSince(prevVoiceEnd))
            behindByHistogram.add(behindBy)
            behindByMax = max(behindByMax, behindBy)
        }

        entry.voiceStarted = date
        open[key] = entry
    }

    /// Voice ended (either finished or was cut off by the next line).
    public mutating func voiceEnded(lineID: Int, wordStart: Date, at endDate: Date) {
        let key = Self.key(lineID: lineID, wordStart: wordStart)
        guard open[key] != nil else { return }  // already closed or never opened: safe no-op
        lastVoiceEndTime = endDate
        open.removeValue(forKey: key)
        evictOldOpenPhrases(now: endDate)
    }

    /// A line finalized on screen: track it for repeat detection.
    public mutating func lineFinished(_ text: String, at now: Date) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }  // skip empty/whitespace-only
        let hash = Self.hashForRepeat(trimmed)

        // Check if this is a repeat of a recent line.
        if let lastTime = recentFinals[hash] {
            let elapsed = max(0, now.timeIntervalSince(lastTime))
            if elapsed < Self.ageCap {
                repeatCount += 1
            }
        }
        recentFinals[hash] = now

        // Evict old entries and cap the dictionary.
        evictOldFinals(now: now)
        if recentFinals.count > Self.maxRecentFinals {
            let sorted = recentFinals.sorted { $0.value > $1.value }
            recentFinals = Dictionary(uniqueKeysWithValues: sorted.prefix(Self.maxRecentFinals).map { ($0.key, $0.value) })
        }
    }

    // MARK: Reporting

    public var voiceStartDelaySamples: Int { voiceStartDelayHistogram.count }
    public var voiceStartDelayMedian: Double? { voiceStartDelayHistogram.value(at: 0.5) }
    public var voiceStartDelayP95: Double? { voiceStartDelayHistogram.value(at: 0.95) }
    public var voiceStartDelayMaxSeconds: Double { voiceStartDelayMax }

    public var translationReadyDelaySamples: Int { translationReadyDelayHistogram.count }
    public var translationReadyDelayMedian: Double? { translationReadyDelayHistogram.value(at: 0.5) }
    public var translationReadyDelayP95: Double? { translationReadyDelayHistogram.value(at: 0.95) }
    public var translationReadyDelayMaxSeconds: Double { translationReadyDelayMax }

    public var behindBySamples: Int { behindByHistogram.count }
    public var behindByMedian: Double? { behindByHistogram.value(at: 0.5) }
    public var behindByP95: Double? { behindByHistogram.value(at: 0.95) }
    public var behindByMaxSeconds: Double { behindByMax }

    public var repeats: Int { repeatCount }

    // MARK: Helpers

    private static func key(lineID: Int, wordStart: Date) -> String {
        "\(lineID)|\(wordStart.timeIntervalSince1970)"
    }

    private static func hashForRepeat(_ text: String) -> Int {
        let normalized = text.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        return normalized.hashValue
    }

    private mutating func evictOldOpenPhrases(now: Date) {
        let keysToRemove = open.filter { _, phrase in
            max(0, now.timeIntervalSince(phrase.ended)) >= Self.ageCap
        }.map { $0.key }
        for key in keysToRemove {
            open.removeValue(forKey: key)
        }
    }

    private mutating func evictOldFinals(now: Date) {
        let keysToRemove = recentFinals.filter { _, lastTime in
            max(0, now.timeIntervalSince(lastTime)) >= Self.ageCap
        }.map { $0.key }
        for key in keysToRemove {
            recentFinals.removeValue(forKey: key)
        }
    }
}
