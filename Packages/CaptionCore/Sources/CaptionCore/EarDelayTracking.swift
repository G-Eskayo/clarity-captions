import Foundation

/// An in-flight phrase being tracked for ear-delay measurement.
private struct OpenInstance: Codable, Equatable {
    var phraseSpokenAt: Date?
    var translationReadyAt: Date?
    var voiceStartedAt: Date?
}

/// Tracks delays in "Speak it in my ear" (#294): when phrases are spoken, when translation arrives, voice latency.
public struct EarDelayTracker: Sendable {
    /// Delay from phrase spoken to translation received (seconds).
    private var translateDelay: PercentileHistogram
    /// Delay from translation ready to voice starting (seconds).
    private var voiceStartDelay: PercentileHistogram
    /// How far behind the speaker the voice is (seconds, negative = ahead).
    private var behindBy: PercentileHistogram

    /// Open instances, keyed by instanceID.
    private var openInstances: [Int: OpenInstance]

    public private(set) var repeats: Int
    public private(set) var translationMisses: Int
    public private(set) var voiceCutOffs: Int

    public init() {
        self.translateDelay = PercentileHistogram(lower: 0, upper: 10, binWidth: 0.05)
        self.voiceStartDelay = PercentileHistogram(lower: 0, upper: 10, binWidth: 0.05)
        self.behindBy = PercentileHistogram(lower: -5, upper: 5, binWidth: 0.1)
        self.openInstances = [:]
        self.repeats = 0
        self.translationMisses = 0
        self.voiceCutOffs = 0
    }

    /// A phrase was spoken for translation (instance ID assigned for this tracking).
    public mutating func phraseSpoken(instanceID: Int, at date: Date) {
        openInstances[instanceID] = OpenInstance(phraseSpokenAt: date, translationReadyAt: nil, voiceStartedAt: nil)
        while openInstances.count > 100 {
            if let oldestID = openInstances.keys.min() {
                openInstances.removeValue(forKey: oldestID)
            }
        }
    }

    /// The translation arrived for a spoken phrase.
    public mutating func translationReady(instanceID: Int, at date: Date) {
        guard var instance = openInstances[instanceID], let phraseSpoken = instance.phraseSpokenAt else {
            translationMisses += 1
            return
        }
        let delay = max(0, date.timeIntervalSince(phraseSpoken))
        translateDelay.add(delay)
        instance.translationReadyAt = date
        openInstances[instanceID] = instance
    }

    /// The voice started speaking the translation.
    public mutating func voiceStarted(instanceID: Int, at date: Date) {
        guard var instance = openInstances[instanceID], let translationReady = instance.translationReadyAt else {
            return
        }
        let delay = max(0, date.timeIntervalSince(translationReady))
        voiceStartDelay.add(delay)
        instance.voiceStartedAt = date
        openInstances[instanceID] = instance
    }

    /// The voice finished speaking (or was cut off); compute how far behind it was.
    public mutating func voiceFinished(instanceID: Int, at date: Date, speakerSpokeThen: Date) {
        guard let instance = openInstances[instanceID], instance.voiceStartedAt != nil else { return }
        let behind = date.timeIntervalSince(speakerSpokeThen)
        behindBy.add(behind)
        openInstances.removeValue(forKey: instanceID)
    }

    /// The voice was cut off (stopped before finishing, e.g., headphones removed, stop tapped).
    public mutating func voiceCutOff(instanceID: Int) {
        guard openInstances[instanceID] != nil else { return }
        voiceCutOffs += 1
        openInstances.removeValue(forKey: instanceID)
    }

    /// A translation failed to arrive for a spoken phrase.
    public mutating func translationFailed(instanceID: Int) {
        guard openInstances[instanceID] != nil else { return }
        translationMisses += 1
        openInstances.removeValue(forKey: instanceID)
    }

    /// Summary of delays: p50, p95, max, and sample count per metric.
    public var report: EarDelayReport {
        EarDelayReport(
            translateDelay: .init(
                p50Seconds: translateDelay.value(at: 0.5),
                p95Seconds: translateDelay.value(at: 0.95),
                maxSeconds: translateDelay.value(at: 1.0),
                samples: translateDelay.count
            ),
            voiceStartDelay: .init(
                p50Seconds: voiceStartDelay.value(at: 0.5),
                p95Seconds: voiceStartDelay.value(at: 0.95),
                maxSeconds: voiceStartDelay.value(at: 1.0),
                samples: voiceStartDelay.count
            ),
            behindBy: .init(
                p50Seconds: behindBy.value(at: 0.5),
                p95Seconds: behindBy.value(at: 0.95),
                maxSeconds: behindBy.value(at: 1.0),
                samples: behindBy.count
            ),
            repeats: repeats,
            translationMisses: translationMisses,
            voiceCutOffs: voiceCutOffs
        )
    }
}

// MARK: - Codable

extension EarDelayTracker: Codable {
    private enum CodingKeys: String, CodingKey {
        case translateDelay, voiceStartDelay, behindBy, openInstances, repeats, translationMisses, voiceCutOffs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.translateDelay = try c.decode(PercentileHistogram.self, forKey: .translateDelay)
        self.voiceStartDelay = try c.decode(PercentileHistogram.self, forKey: .voiceStartDelay)
        self.behindBy = try c.decode(PercentileHistogram.self, forKey: .behindBy)
        self.openInstances = try c.decode([Int: OpenInstance].self, forKey: .openInstances)
        self.repeats = try c.decode(Int.self, forKey: .repeats)
        self.translationMisses = try c.decode(Int.self, forKey: .translationMisses)
        self.voiceCutOffs = try c.decode(Int.self, forKey: .voiceCutOffs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(translateDelay, forKey: .translateDelay)
        try c.encode(voiceStartDelay, forKey: .voiceStartDelay)
        try c.encode(behindBy, forKey: .behindBy)
        try c.encode(openInstances, forKey: .openInstances)
        try c.encode(repeats, forKey: .repeats)
        try c.encode(translationMisses, forKey: .translationMisses)
        try c.encode(voiceCutOffs, forKey: .voiceCutOffs)
    }
}

// MARK: - Equatable

extension EarDelayTracker: Equatable {
    public static func == (lhs: EarDelayTracker, rhs: EarDelayTracker) -> Bool {
        lhs.translateDelay == rhs.translateDelay &&
        lhs.voiceStartDelay == rhs.voiceStartDelay &&
        lhs.behindBy == rhs.behindBy &&
        lhs.openInstances == rhs.openInstances &&
        lhs.repeats == rhs.repeats &&
        lhs.translationMisses == rhs.translationMisses &&
        lhs.voiceCutOffs == rhs.voiceCutOffs
    }
}

/// The final ear-delay report for a conversation.
public struct EarDelayReport: Codable, Equatable, Sendable {
    public struct Metric: Codable, Equatable, Sendable {
        public var p50Seconds: Double?
        public var p95Seconds: Double?
        public var maxSeconds: Double?
        public var samples: Int

        public init(p50Seconds: Double?, p95Seconds: Double?, maxSeconds: Double?, samples: Int) {
            self.p50Seconds = p50Seconds
            self.p95Seconds = p95Seconds
            self.maxSeconds = maxSeconds
            self.samples = samples
        }
    }

    public var translateDelay: Metric
    public var voiceStartDelay: Metric
    public var behindBy: Metric
    public var repeats: Int
    public var translationMisses: Int
    public var voiceCutOffs: Int

    public init(translateDelay: Metric, voiceStartDelay: Metric, behindBy: Metric, repeats: Int, translationMisses: Int, voiceCutOffs: Int) {
        self.translateDelay = translateDelay
        self.voiceStartDelay = voiceStartDelay
        self.behindBy = behindBy
        self.repeats = repeats
        self.translationMisses = translationMisses
        self.voiceCutOffs = voiceCutOffs
    }
}

extension EarDelayReport.Metric {
    private enum CodingKeys: String, CodingKey { case p50Seconds, p95Seconds, maxSeconds, samples }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.p50Seconds = try c.decode(Double?.self, forKey: .p50Seconds)
        self.p95Seconds = try c.decode(Double?.self, forKey: .p95Seconds)
        self.maxSeconds = try c.decode(Double?.self, forKey: .maxSeconds)
        self.samples = try c.decode(Int.self, forKey: .samples)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p50Seconds, forKey: .p50Seconds)
        try c.encode(p95Seconds, forKey: .p95Seconds)
        try c.encode(maxSeconds, forKey: .maxSeconds)
        try c.encode(samples, forKey: .samples)
    }
}
