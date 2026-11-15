import Foundation

/// Tracks delays in the ear translation pipeline: when a phrase is ready, when its translation arrives,
/// and when voice starts playing. Measures translateDelay, voiceStartDelay, and backlog depth (behindBy).
public struct EarDelayTracker: Sendable {
    public struct Sample: Equatable, Sendable {
        /// Time from phrase ready to translation ready (seconds).
        public let translateDelay: Double
        /// Time from translation ready to voice started (seconds).
        public let voiceStartDelay: Double
        /// How much work is queued ahead (clamped to ≥0).
        public let behindBy: Double

        public init(translateDelay: Double, voiceStartDelay: Double, behindBy: Double) {
            self.translateDelay = max(0, translateDelay)
            self.voiceStartDelay = max(0, voiceStartDelay)
            self.behindBy = max(0, behindBy)
        }
    }

    private struct PendingPhrase: Sendable {
        let readyAt: Double
        var translationReadyAt: Double?
    }

    /// Max pending phrases to track; evict numerically-oldest keys when exceeded.
    private static let maxPending = 100

    /// Key is (lineID, wordRangeStart) to handle multiple phrases per line.
    private var pending: [(key: (lineID: Int, wordStart: Int), value: PendingPhrase)] = []
    /// When the last phrase finished translating (for `behindBy` calculation).
    private var latestEndOfPhrase: Double? = nil

    public init() {}

    /// A phrase became ready to speak. Line can emit multiple phrases; keep the first anchor.
    public mutating func phraseReady(lineID: Int, wordStart: Int, at now: Double) {
        let key = (lineID: lineID, wordStart: wordStart)
        if pending.first(where: { $0.key == key }) == nil {
            pending.append((key: key, value: PendingPhrase(readyAt: now, translationReadyAt: nil)))
            evictIfNeeded()
        }
    }

    /// The phrase's translation arrived.
    public mutating func translationReady(lineID: Int, wordStart: Int, at now: Double) {
        let key = (lineID: lineID, wordStart: wordStart)
        if let i = pending.firstIndex(where: { $0.key == key }) {
            pending[i].value.translationReadyAt = now
        }
    }

    /// Voice started for this phrase. Returns a sample if we have the data to measure.
    public mutating func voiceStarted(lineID: Int, wordStart: Int, at now: Double) -> Sample? {
        let key = (lineID: lineID, wordStart: wordStart)
        guard let i = pending.firstIndex(where: { $0.key == key }) else { return nil }
        let p = pending[i].value
        guard let translationReadyAt = p.translationReadyAt else { return nil }
        let translateDelay = translationReadyAt - p.readyAt
        let voiceStartDelay = now - translationReadyAt
        let behindBy = latestEndOfPhrase.map { max(0, now - $0) } ?? 0
        latestEndOfPhrase = translationReadyAt
        pending.remove(at: i)
        return Sample(translateDelay: translateDelay, voiceStartDelay: voiceStartDelay, behindBy: behindBy)
    }

    /// Reset pending phrases (new conversation).
    public mutating func reset() {
        pending = []
        latestEndOfPhrase = nil
    }

    private mutating func evictIfNeeded() {
        guard pending.count > Self.maxPending else { return }
        if let minIdx = pending.enumerated().min(by: { $0.element.key.lineID < $1.element.key.lineID })?.offset {
            pending.remove(at: minIdx)
        }
    }
}
