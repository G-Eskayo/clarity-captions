import Foundation

// Beta-tester feedback and metrics (ADR 0023, #112). TestFlight installs only: testers rate each conversation and
// the app keeps measurements (lag, rewrites, speaker labels, how it ended, battery, heat). Never caption text, audio,
// speaker names or vocabulary. App Store installs record nothing (fail closed).

/// Where this install came from, as StoreKit reports it.
public enum BetaEnvironment: String, Codable, Sendable {
    /// TestFlight.
    case sandbox
    case production
    /// A development build run from Xcode.
    case xcode
    /// The check failed or couldn't be verified.
    case unknown

    /// Fail closed: only TestFlight and development builds record anything.
    public var featuresOn: Bool { self == .sandbox || self == .xcode }
}

/// How a stretch of captioning ended.
public struct ConversationEnding: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case userStop, quietStop, failure, stuck, appClosed }
    public var kind: Kind
    /// The plain-language failure text (failure only); never caption text.
    public var reason: String?

    public init(kind: Kind, reason: String? = nil) {
        self.kind = kind
        self.reason = reason
    }

    public static let userStop = ConversationEnding(kind: .userStop)
    public static let quietStop = ConversationEnding(kind: .quietStop)
    public static let appClosed = ConversationEnding(kind: .appClosed)
    public static func failure(_ reason: String) -> ConversationEnding { ConversationEnding(kind: .failure, reason: reason) }

    /// The ending a paused state implies. `.idle` after captioning means she pressed Stop.
    public static func from(_ state: CaptionState) -> ConversationEnding? {
        switch state {
        case .idle: .userStop
        case .pausedQuiet: .quietStop
        case .failed(let reason): .failure(reason)
        case .preparing, .listening: nil
        }
    }
}

/// When the 2-second rating card appears (ADR 0023 §3, owner 2026-10-09).
public enum RatingCardTiming {
    public enum Event: Sendable {
        /// She tapped [ New ] (after confirming, if it asked).
        case newTapped
        /// She came back to a paused conversation: back from another app, or a cold launch that restored it.
        case returnedToConversation
    }

    /// - A pause she made herself (Stop) may be one she wants to return to, so the card waits for [ New ].
    /// - A pause that happened without her (quiet stop, failure, the app closed or left mid-conversation) also shows
    ///   it when she comes back.
    /// - Never while captioning, never twice for one conversation, never for an empty one.
    public static func shouldShow(event: Event, ending: ConversationEnding?, leftWhileCaptioning: Bool,
                                  alreadyAsked: Bool, hasConversation: Bool, isCaptioning: Bool) -> Bool {
        guard !isCaptioning, !alreadyAsked, hasConversation else { return false }
        switch event {
        case .newTapped:
            return true
        case .returnedToConversation:
            if leftWhileCaptioning { return true }
            guard let ending else { return false }
            return ending.kind != .userStop
        }
    }
}

/// Fixed-size histogram for medians and 95th percentiles: constant memory for any length of conversation, and
/// Codable so a conversation interrupted by iOS closing the app keeps its measurements.
public struct PercentileHistogram: Codable, Equatable, Sendable {
    public let lower: Double
    public let binWidth: Double
    private(set) var bins: [Int]
    public private(set) var count = 0

    public init(lower: Double, upper: Double, binWidth: Double) {
        self.lower = lower
        self.binWidth = binWidth
        bins = Array(repeating: 0, count: max(1, Int(((upper - lower) / binWidth).rounded(.up))))
    }

    /// Values below `lower` count in the first bin and above the range in the last, so nothing is lost.
    public mutating func add(_ value: Double) {
        guard value.isFinite else { return }
        let i = Int(((value - lower) / binWidth).rounded(.down))
        bins[min(max(i, 0), bins.count - 1)] += 1
        count += 1
    }

    /// The value at a fraction (0...1), as the middle of its bin; nil when empty.
    public func value(at fraction: Double) -> Double? {
        guard count > 0 else { return nil }
        let target = max(1, Int((Double(count) * min(max(fraction, 0), 1)).rounded(.up)))
        var seen = 0
        for (i, n) in bins.enumerated() {
            seen += n
            if seen >= target { return lower + (Double(i) + 0.5) * binWidth }
        }
        return lower + (Double(bins.count) - 0.5) * binWidth
    }

    /// Share of values below `threshold`.
    public func fraction(below threshold: Double) -> Double? {
        guard count > 0 else { return nil }
        let upTo = Int(((threshold - lower) / binWidth).rounded(.down))
        let n = bins.prefix(max(0, min(upTo, bins.count))).reduce(0, +)
        return Double(n) / Double(count)
    }

    public mutating func merge(_ other: PercentileHistogram) {
        guard other.bins.count == bins.count, other.lower == lower, other.binWidth == binWidth else { return }
        for i in bins.indices { bins[i] += other.bins[i] }
        count += other.count
    }
}

/// The phone's heat, as `ProcessInfo.ThermalState` reports it, ordered.
public enum ThermalLevel: Int, Codable, Comparable, Sendable {
    case nominal, fair, serious, critical

    public var name: String {
        switch self {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        }
    }

    public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }
}

/// A battery reading: level 0...1 (negative when unknown, as UIDevice reports it) and whether it was charging.
public struct BatterySample: Codable, Equatable, Sendable {
    public var level: Double
    public var charging: Bool
    public init(level: Double, charging: Bool) {
        self.level = level
        self.charging = charging
    }
}

/// Everything measured about one conversation, from its first Start until [ New ]. It sees caption text only to
/// count rewritten words and holds none of it: no text survives an update.
public struct ConversationRecorder: Codable, Equatable, Sendable {
    public let id: UUID
    public private(set) var startedAt: Date?
    public private(set) var rating: Int?
    public private(set) var ratingSkipped = false
    public private(set) var note: String?
    /// The card was shown (answered or skipped): never again for this conversation.
    public private(set) var asked = false
    public private(set) var ending: ConversationEnding?
    /// She left for another app while captions were running; the card shows when she comes back.
    public private(set) var leftWhileCaptioning = false
    public private(set) var lowPowerModeSeen = false
    public private(set) var maxThermal: ThermalLevel?
    public private(set) var launchToStartSeconds: Double?
    public private(set) var startToFirstCaptionSeconds: Double?
    public private(set) var launch: LaunchFacts?

    private var captioningSeconds = 0.0
    private var segmentStart: Date?
    private var startPressedAt: Date?
    private var lag = PercentileHistogram(lower: 0, upper: 10, binWidth: 0.05)
    private var micLevel = PercentileHistogram(lower: -60, upper: 0, binWidth: 1)
    private var shownWordCount = 0
    /// Per-word fingerprints of the utterance on screen, so a rewrite can be counted without keeping its words.
    private var shownWordHashes: [Int] = []
    private var changedWords = 0
    private var finalWords = 0
    private var utteranceSpeaker: Int?
    private var relabels = 0
    private var speakers: Set<Int> = []
    private var batteryDrop = 0.0
    private var batteryMinutes = 0.0
    private var segmentBattery: BatterySample?

    public struct LaunchFacts: Codable, Equatable, Sendable {
        public var fullDance: Bool
        public var barShown: Bool
        public init(fullDance: Bool, barShown: Bool) {
            self.fullDance = fullDance
            self.barShown = barShown
        }
    }

    /// Quieter than this counts as "quiet" in the mic summary (the meter's floor is -60 dBFS).
    public static let quietThresholdDBFS = -50.0

    /// What's written to the phone. The utterance in progress (word fingerprints, its speaker) is deliberately left
    /// out: it exists only while the words are on screen.
    private enum CodingKeys: String, CodingKey {
        case id, startedAt, rating, ratingSkipped, note, asked, ending, leftWhileCaptioning, lowPowerModeSeen
        case maxThermal, launchToStartSeconds, startToFirstCaptionSeconds, launch
        case captioningSeconds, segmentStart, startPressedAt, lag, micLevel, changedWords, finalWords, relabels
        case speakers, batteryDrop, batteryMinutes, segmentBattery
    }

    public init(id: UUID) { self.id = id }

    // MARK: events

    /// Start was pressed. `sinceLaunch` is the time from app launch, given only for the first Start of a launch.
    public mutating func startPressed(at date: Date, sinceLaunch: Double?, launch facts: LaunchFacts?) {
        startPressedAt = date
        if startedAt == nil { startedAt = date }
        if launchToStartSeconds == nil, let sinceLaunch { launchToStartSeconds = sinceLaunch }
        if launch == nil, let facts { launch = facts }
    }

    /// Captions are running.
    public mutating func captioningStarted(at date: Date, battery: BatterySample?) {
        if startedAt == nil { startedAt = date }
        segmentStart = date
        segmentBattery = battery
        ending = nil
        leftWhileCaptioning = false
        shownWordCount = 0
        shownWordHashes = []
        utteranceSpeaker = nil
    }

    public mutating func captionUpdate(text: String, isFinal: Bool, speaker: Int?, lagSeconds: Double?, at date: Date) {
        let words = text.split(whereSeparator: \.isWhitespace)
        if startToFirstCaptionSeconds == nil, !words.isEmpty, let pressed = startPressedAt {
            startToFirstCaptionSeconds = max(0, date.timeIntervalSince(pressed))
        }
        if let lagSeconds { lag.add(lagSeconds) }

        // Rewrites: a word already on screen that changes, or disappears, counts once per change.
        let hashes = words.map { $0.hashValue }
        for i in 0..<shownWordHashes.count where i >= hashes.count || hashes[i] != shownWordHashes[i] { changedWords += 1 }
        shownWordHashes = hashes
        shownWordCount = words.count

        if let speaker {
            speakers.insert(speaker)
            if let current = utteranceSpeaker, current != speaker { relabels += 1 }
            utteranceSpeaker = speaker
        }
        if isFinal {
            finalWords += words.count
            shownWordHashes = []
            shownWordCount = 0
            utteranceSpeaker = nil
        }
    }

    public mutating func audioLevel(_ dbfs: Double) { micLevel.add(dbfs) }

    public mutating func thermal(_ level: ThermalLevel) { maxThermal = max(maxThermal ?? level, level) }

    public mutating func lowPowerMode(_ on: Bool) { if on { lowPowerModeSeen = true } }

    /// Captions stopped. A second stop for the same stretch changes nothing.
    public mutating func captioningStopped(at date: Date, battery: BatterySample?, ending newEnding: ConversationEnding) {
        guard let start = segmentStart else { ending = newEnding; return }
        let seconds = max(0, date.timeIntervalSince(start))
        captioningSeconds += seconds
        if let from = segmentBattery, let to = battery, !from.charging, !to.charging, from.level >= 0, to.level >= 0 {
            batteryDrop += max(0, from.level - to.level) * 100
            batteryMinutes += seconds / 60
        }
        segmentStart = nil
        segmentBattery = nil
        ending = newEnding
    }

    /// She left for another app while captions were running.
    public mutating func leftMidConversation() {
        if segmentStart != nil { leftWhileCaptioning = true }
    }

    /// Back on screen with captions still running: she didn't leave the conversation after all.
    public mutating func backWhileCaptioning() {
        if segmentStart != nil { leftWhileCaptioning = false }
    }

    /// A cold launch restored this conversation: captions were cut off by the app closing.
    public mutating func restoredAfterAppClosed(at date: Date) {
        if segmentStart != nil {
            captioningStopped(at: date, battery: nil, ending: .appClosed)
            leftWhileCaptioning = true
        }
    }

    public mutating func rate(_ value: Int, note: String?) {
        rating = min(max(value, 1), 10)
        ratingSkipped = false
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        asked = true
    }

    public mutating func skipRating() {
        rating = nil
        ratingSkipped = true
        asked = true
    }

    // MARK: the report

    public var hasData: Bool { startedAt != nil }

    public func entry(now: Date) -> ConversationReport {
        var seconds = captioningSeconds
        if let start = segmentStart { seconds += max(0, now.timeIntervalSince(start)) }
        let minutes = seconds / 60
        return ConversationReport(
            id: id.uuidString,
            startedAt: startedAt ?? now,
            minutes: Self.round(minutes, 1),
            rating: rating,
            ratingSkipped: ratingSkipped,
            note: note,
            lag: .init(p50Seconds: lag.value(at: 0.5).map { Self.round($0, 2) },
                       p95Seconds: lag.value(at: 0.95).map { Self.round($0, 2) },
                       samples: lag.count),
            rewriteRate: finalWords + shownWordCount > 0
                ? Self.round(min(1, Double(changedWords) / Double(max(1, finalWords + shownWordCount))), 3) : nil,
            speakers: .init(detected: speakers.count,
                            relabelsPerMinute: minutes > 0 ? Self.round(Double(relabels) / minutes, 2) : nil),
            launchToStartSeconds: launchToStartSeconds.map { Self.round($0, 2) },
            startToFirstCaptionSeconds: startToFirstCaptionSeconds.map { Self.round($0, 2) },
            ending: ending,
            battery: .init(dropPercentPer30Min: batteryMinutes >= 0.5 ? Self.round(batteryDrop / batteryMinutes * 30, 1) : nil,
                           maxThermalState: maxThermal?.name),
            micLevel: .init(medianDBFS: micLevel.value(at: 0.5).map { Self.round($0, 1) },
                            quietFraction: micLevel.fraction(below: Self.quietThresholdDBFS).map { Self.round($0, 2) }),
            launch: launch.map { .init(fullDance: $0.fullDance, barShown: $0.barShown) })
    }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let p = pow(10, Double(places))
        return (value * p).rounded() / p
    }
}

// MARK: - The report file (docs/beta/metrics-schema.md)

/// One conversation in a report. Field names are the schema's.
public struct ConversationReport: Codable, Equatable, Sendable {
    public struct Lag: Codable, Equatable, Sendable {
        public var p50Seconds: Double?
        public var p95Seconds: Double?
        public var samples: Int
    }
    public struct Speakers: Codable, Equatable, Sendable {
        public var detected: Int
        public var relabelsPerMinute: Double?
    }
    public struct Battery: Codable, Equatable, Sendable {
        public var dropPercentPer30Min: Double?
        public var maxThermalState: String?
    }
    public struct MicLevel: Codable, Equatable, Sendable {
        public var medianDBFS: Double?
        public var quietFraction: Double?
    }
    public struct Launch: Codable, Equatable, Sendable {
        public var fullDance: Bool
        public var barShown: Bool
    }

    public var id: String
    public var startedAt: Date
    public var minutes: Double
    public var rating: Int?
    public var ratingSkipped: Bool
    public var note: String?
    public var lag: Lag
    public var rewriteRate: Double?
    public var speakers: Speakers
    public var launchToStartSeconds: Double?
    public var startToFirstCaptionSeconds: Double?
    public var ending: ConversationEnding?
    public var battery: Battery
    public var micLevel: MicLevel
    public var launch: Launch?
}

public struct FeedbackReport: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public var version: String
        public var build: String
        public var environment: String
        public init(version: String, build: String, environment: BetaEnvironment) {
            self.version = version
            self.build = build
            self.environment = environment.rawValue
        }
    }
    public struct Device: Codable, Equatable, Sendable {
        public var model: String
        public var os: String
        public var lowPowerModeSeen: Bool
        public init(model: String, os: String, lowPowerModeSeen: Bool) {
            self.model = model
            self.os = os
            self.lowPowerModeSeen = lowPowerModeSeen
        }
    }
    public struct Settings: Codable, Equatable, Sendable {
        public var theme: String
        public var lettering: String
        public var textSize: String
        public var quietStop: String
        public init(theme: String, lettering: String, textSize: String, quietStop: String) {
            self.theme = theme
            self.lettering = lettering
            self.textSize = textSize
            self.quietStop = quietStop
        }
    }

    public var schema = 1
    public var app: App
    public var device: Device
    public var settings: Settings
    public var sentAt: Date
    public var conversations: [ConversationReport]

    /// Newest first, as the preview shows them.
    public init(app: App, device: Device, settings: Settings, sentAt: Date, conversations: [ConversationReport]) {
        self.app = app
        self.device = device
        self.settings = settings
        self.sentAt = sentAt
        self.conversations = conversations.sorted { $0.startedAt > $1.startedAt }
    }

    /// The JSON file, dates as local ISO 8601 with offset (schema example), keys sorted so files diff cleanly.
    public func json(timeZone: TimeZone = .current) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(formatter.string(from: date))
        }
        return try encoder.encode(self)
    }

    /// `seal-feedback-<build>-<YYYYMMDD-HHMM>.json`
    public static func fileName(build: String, date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let safeBuild = build.filter { $0.isLetter || $0.isNumber || $0 == "." }
        return String(format: "seal-feedback-%@-%04d%02d%02d-%02d%02d.json",
                      safeBuild.isEmpty ? "0" : safeBuild, c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
    }

    /// The short readable text that goes in the message with the file.
    public var summary: String {
        let ratings = conversations.map { $0.rating.map(String.init) ?? String(localized: "skipped") }
        let lags = conversations.compactMap(\.lag.p50Seconds).sorted()
        var lines = [String(format: String(localized: "Seal feedback · %lld conversations · %@ %@ (%@) · %@ · %@"),
                            conversations.count, "Seal", app.version, app.build, device.model, device.os)]
        if !ratings.isEmpty { lines.append(String(localized: "Ratings: ") + ratings.joined(separator: ", ")) }
        if !lags.isEmpty { lines.append(String(format: String(localized: "Typical caption lag: %.1f s"), lags[lags.count / 2])) }
        return lines.joined(separator: "\n")
    }
}

// MARK: - The preview: exactly what will be sent, in words

public struct FeedbackPreviewRow: Equatable, Sendable {
    public let label: String
    public let value: String
}

public struct FeedbackPreviewCard: Equatable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let rows: [FeedbackPreviewRow]
}

public enum FeedbackPreview {
    /// One card per conversation, newest first, in plain words (mock-up 04). Shows the rows that have a value.
    public static func cards(for report: FeedbackReport, locale: Locale = .current, timeZone: TimeZone = .current) -> [FeedbackPreviewCard] {
        let day = DateFormatter()
        day.locale = locale
        day.timeZone = timeZone
        day.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return report.conversations.map { c in
            var rows: [FeedbackPreviewRow] = []
            func add(_ label: String, _ value: String?) { if let value { rows.append(.init(label: label, value: value)) } }
            add(String(localized: "Your rating"), c.rating.map { "\($0) / 10" } ?? (c.ratingSkipped ? String(localized: "Skipped") : String(localized: "Not asked yet")))
            add(String(localized: "Your note"), c.note.map { "“\($0)”" })
            if let p50 = c.lag.p50Seconds {
                add(String(localized: "Caption lag"), c.lag.p95Seconds.map { String(format: String(localized: "%.1f s (worst %.1f s)"), p50, $0) } ?? String(format: "%.1f s", p50))
            }
            if c.speakers.detected > 0 {
                let steady = (c.speakers.relabelsPerMinute ?? 0) < 1.5
                add(String(localized: "Speakers"), "\(c.speakers.detected) · " + (steady ? String(localized: "labels steady") : String(localized: "labels switched often")))
            }
            add(String(localized: "Battery"), c.battery.dropPercentPer30Min.map { String(format: String(localized: "%.1f%% per 30 min"), $0) })
            if let thermal = c.battery.maxThermalState, thermal == "serious" || thermal == "critical" {
                add(String(localized: "Phone"), String(format: String(localized: "Got warm (%@)"), thermal))
            }
            add(String(localized: "Ended"), c.ending.map(endingWords))
            let minutes = max(1, Int(c.minutes.rounded()))
            return FeedbackPreviewCard(id: c.id, title: day.string(from: c.startedAt) + " · " + String(format: String(localized: "%lld min"), minutes), rows: rows)
        }
    }

    public static func endingWords(_ ending: ConversationEnding) -> String {
        switch ending.kind {
        case .userStop: String(localized: "You pressed Stop")
        case .quietStop: String(localized: "It went quiet")
        case .failure: String(localized: "Captions stopped")
        case .stuck: String(localized: "Captions got stuck")
        case .appClosed: String(localized: "The app was closed")
        }
    }
}

// MARK: - Storage on the phone

/// What's kept between sends: each conversation's recorder, and whether it's finished ([ New ] was tapped).
public struct StoredConversation: Codable, Equatable, Sendable {
    public var recorder: ConversationRecorder
    public var finished: Bool
    public init(recorder: ConversationRecorder, finished: Bool) {
        self.recorder = recorder
        self.finished = finished
    }
}

/// One small file of unsent conversations, excluded from backup (ADR 0023: kept until sent, no cap).
public final class FeedbackStore: @unchecked Sendable {
    public let directory: URL
    private let fileURL: URL
    private let lock = NSLock()

    public init(directory: URL, fileManager: FileManager = .default) throws {
        self.directory = directory
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = directory
        try dir.setResourceValues(values)
        #endif
        fileURL = directory.appendingPathComponent("unsent.json")
    }

    public func all() -> [StoredConversation] {
        lock.withLock { read() }
    }

    /// Adds or replaces a conversation by id. Empty ones (never started) aren't kept.
    public func upsert(_ recorder: ConversationRecorder, finished: Bool) {
        guard recorder.hasData else { return }
        lock.withLock {
            var list = read()
            if let i = list.firstIndex(where: { $0.recorder.id == recorder.id }) {
                list[i] = StoredConversation(recorder: recorder, finished: finished || list[i].finished)
            } else {
                list.append(StoredConversation(recorder: recorder, finished: finished))
            }
            write(list)
        }
    }

    public func recorder(id: UUID) -> ConversationRecorder? {
        all().first { $0.recorder.id == id }?.recorder
    }

    /// After Messages reports the text was sent: the finished conversations that were in it go. One still on screen
    /// stays and is sent again later with the same id (MARVIN keeps the newest per id).
    public func removeSent(ids: Set<UUID>) {
        lock.withLock { write(read().filter { !($0.finished && ids.contains($0.recorder.id)) }) }
    }

    /// App Store installs keep nothing: anything left from a TestFlight install is deleted, never sent.
    public func deleteAll() {
        lock.withLock { try? FileManager.default.removeItem(at: fileURL) }
    }

    private func read() -> [StoredConversation] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([StoredConversation].self, from: data)) ?? []
    }

    private func write(_ list: [StoredConversation]) {
        if list.isEmpty { try? FileManager.default.removeItem(at: fileURL); return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(list).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
