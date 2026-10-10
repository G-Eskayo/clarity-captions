import Foundation

/// The conversation on screen, kept across pauses until [ New ] (#102, replacing ADR 0022's automatic save).
/// It is saved only when she taps [ Save ], and saving again updates the same saved conversation.
public struct ConversationSession: Equatable, Sendable {
    /// What the retro save button shows.
    public enum SaveButton: Equatable, Sendable {
        /// Nothing to save yet.
        case unavailable
        /// [ Save ]
        case save
        /// [ Saved ], held until the conversation's content changes (never because time passed).
        case saved
    }

    public let id: UUID
    public private(set) var startedAt: Date?
    /// The transcript as last saved; the conversation counts as changed whenever its transcript differs.
    public private(set) var savedTranscript: String?

    public init(id: UUID = UUID(), startedAt: Date? = nil, savedTranscript: String? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.savedTranscript = savedTranscript
    }

    /// Records when the conversation began; resuming never moves it.
    public mutating func captioningStarted(at date: Date) {
        if startedAt == nil { startedAt = date }
    }

    public func saveButton(lines: [CaptionLine], names: SpeakerNames) -> SaveButton {
        guard Self.hasContent(lines) else { return .unavailable }
        return Self.transcript(lines, names) == savedTranscript ? .saved : .save
    }

    /// True when there is something on screen that isn't saved as it stands. [ New ] asks first in that case.
    public func hasUnsavedChanges(lines: [CaptionLine], names: SpeakerNames) -> Bool {
        saveButton(lines: lines, names: names) == .save
    }

    /// The conversation to write to the saved list, or nil if there is nothing to save. Marks it saved.
    public mutating func makeSaved(lines: [CaptionLine], names: SpeakerNames, now: Date) -> SavedConversation? {
        guard Self.hasContent(lines) else { return nil }
        let transcript = Self.transcript(lines, names)
        savedTranscript = transcript
        return SavedConversation(id: id, startedAt: startedAt ?? now, savedAt: now, transcript: transcript)
    }

    public static func hasContent(_ lines: [CaptionLine]) -> Bool {
        lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func transcript(_ lines: [CaptionLine], _ names: SpeakerNames) -> String {
        TranscriptFormatter.plainText(lines: lines, speakerNames: names)
    }
}

/// The dim over a paused conversation, with [ Save ] and [ New ] on it. A tap clears it so she can scroll and copy;
/// a press-and-hold on empty space (not on words) brings it back. Starting captions resets it for the next pause.
public struct PauseVeil: Equatable, Sendable {
    private var cleared = false

    public init() {}

    public func isVisible(state: CaptionState, hasConversation: Bool) -> Bool {
        Self.isPaused(state) && hasConversation && !cleared
    }

    public mutating func tap(state: CaptionState) {
        if Self.isPaused(state) { cleared = true }
    }

    public mutating func holdOnEmptySpace(state: CaptionState) {
        if Self.isPaused(state) { cleared = false }
    }

    public mutating func captioningStarted() { cleared = false }

    public static func isPaused(_ state: CaptionState) -> Bool {
        switch state {
        case .idle, .failed, .pausedQuiet: true
        case .preparing, .listening: false
        }
    }
}

/// What happens on a cold launch to a conversation that wasn't saved (Decision "coldlaunch" on #102). iOS can't tell
/// "she swiped Seal away" from "iOS closed it in the background", so the time away decides.
public enum ColdLaunchRule: Equatable, Sendable {
    case restoreIfAwayLessThan(minutes: Int)
    case alwaysClear
    case alwaysKeep

    /// The rule in force. Recommended option, pending the owner's answer on #102; switching is this one line.
    public static let current: ColdLaunchRule = .restoreIfAwayLessThan(minutes: 30)

    public func shouldRestore(leftAt: Date, now: Date) -> Bool {
        switch self {
        case .alwaysClear: false
        case .alwaysKeep: true
        // By distance, not sign: a clock set backwards shouldn't keep a conversation forever.
        case .restoreIfAwayLessThan(let minutes): abs(now.timeIntervalSince(leftAt)) < Double(minutes) * 60
        }
    }
}

/// The on-screen conversation written to the phone while she is in another app, so it survives iOS closing Seal in
/// the background. Text only; never backed up or synced (ADR 0022).
public struct CurrentConversationSnapshot: Codable, Equatable, Sendable {
    struct Line: Codable, Equatable, Sendable {
        var speaker: Int?
        var sound: String?
        var text: String
    }

    var lines: [Line]
    var names: [Int: String]
    var sessionID: UUID
    var startedAt: Date?
    var savedTranscript: String?
    public let leftAt: Date

    public init(lines: [CaptionLine], names: SpeakerNames, session: ConversationSession, leftAt: Date) {
        self.lines = lines.map { Line(speaker: $0.speaker, sound: $0.soundLabel.map(Self.soundName), text: $0.text) }
        var byID: [Int: String] = [:]
        for speaker in Set(lines.compactMap(\.speaker)) { if let n = names.name(for: speaker) { byID[speaker] = n } }
        self.names = byID
        self.sessionID = session.id
        self.startedAt = session.startedAt
        self.savedTranscript = session.savedTranscript
        self.leftAt = leftAt
    }

    /// Rebuilds the conversation. Each line comes back finished, as its own line.
    public func restore() -> (stream: CaptionStream, names: SpeakerNames, session: ConversationSession) {
        var stream = CaptionStream()
        for line in lines {
            if let sound = line.sound.flatMap(Self.sound(named:)) { stream.insertSoundLabel(sound) }
            else { stream.apply(text: line.text, isFinal: true, speaker: line.speaker); stream.breakLine() }
        }
        var speakerNames = SpeakerNames()
        for (speaker, name) in names { speakerNames.apply(name, to: speaker) }
        return (stream, speakerNames, ConversationSession(id: sessionID, startedAt: startedAt, savedTranscript: savedTranscript))
    }

    private static func soundName(_ kind: SoundLabelKind) -> String {
        switch kind {
        case .laughter: "laughter"
        case .applause: "applause"
        case .doorbell: "doorbell"
        case .phoneRinging: "phoneRinging"
        case .knock: "knock"
        }
    }

    private static func sound(named name: String) -> SoundLabelKind? {
        switch name {
        case "laughter": .laughter
        case "applause": .applause
        case "doorbell": .doorbell
        case "phoneRinging": .phoneRinging
        case "knock": .knock
        default: nil
        }
    }
}

/// One file holding the current conversation, in its own folder, excluded from backup like the saved ones.
public final class CurrentConversationStore: @unchecked Sendable {
    public let fileURL: URL

    public init(directory: URL, fileManager: FileManager = .default) throws {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        #if os(iOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var dir = directory
        try dir.setResourceValues(values)
        #endif
        fileURL = directory.appendingPathComponent("current.json")
    }

    public func save(_ snapshot: CurrentConversationSnapshot) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// The saved snapshot, or nil. A file that can't be read is removed rather than kept around.
    public func load() -> CurrentConversationSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snapshot = try? decoder.decode(CurrentConversationSnapshot.self, from: data) else { delete(); return nil }
        return snapshot
    }

    public func delete() { try? FileManager.default.removeItem(at: fileURL) }

    /// On a cold launch: the conversation to show paused, or nil. One that's too old is deleted from the phone.
    public func restoreOnColdLaunch(now: Date, rule: ColdLaunchRule = .current) -> CurrentConversationSnapshot? {
        guard let snapshot = load() else { return nil }
        guard rule.shouldRestore(leftAt: snapshot.leftAt, now: now) else { delete(); return nil }
        return snapshot
    }
}

/// The green of [ ✔ ] and [ Saved ] (#96 mock-ups): a deep green on light themes, a soft green on dark ones, both
/// at AAA contrast.
public enum SavedGreen {
    public static func color(on background: RGBA) -> RGBA {
        background.isDark ? RGBA(0x9B / 255, 0xE3 / 255, 0xB4 / 255) : RGBA(0x12 / 255, 0x51 / 255, 0x2F / 255)
    }
}
