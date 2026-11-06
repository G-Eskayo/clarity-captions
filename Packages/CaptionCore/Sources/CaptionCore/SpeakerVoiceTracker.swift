import Foundation

// #247: Tracks each speaker's voice profile from audio and caption samples, thread-safe.
// Keeps per-speaker voice assignment sticky across calls: once assigned, a speaker's voice doesn't change.
// Speakers are processed in the order they first appear, not sorted by ID.

public actor SpeakerVoiceTracker {
    private var profiles: [Int: SpeakerProfile] = [:]
    private var speakerInsertionOrder: [Int] = []  // Track order speakers first appear
    private var stickyVoiceAssignment: [Int: String] = [:]  // Speaker ID -> voiceID (locked after first match)

    public init() {}

    /// Add audio samples for a speaker, broken into 16 kHz mono. Only frames with a valid speaker ID are tracked.
    public func add(samples: [Float], sampleRate: Double, speaker: Int?) {
        guard let speakerID = speaker else { return }
        if profiles[speakerID] == nil {
            speakerInsertionOrder.append(speakerID)
        }
        var profile = profiles[speakerID] ?? SpeakerProfile()
        profile.add(samples, sampleRate: sampleRate)
        profiles[speakerID] = profile
    }

    /// Record a finished caption line for a speaker, with its speaking duration (pauses out).
    /// Used only after about 1.5 seconds of audio has been recorded, for steadier pace measurement.
    public func addLine(_ text: String, speechSeconds: Double, speaker: Int?, language: String? = nil) {
        guard let speakerID = speaker else { return }
        if profiles[speakerID] == nil {
            speakerInsertionOrder.append(speakerID)
        }
        var profile = profiles[speakerID] ?? SpeakerProfile()
        profile.addLine(text, speechSeconds: speechSeconds, language: language)
        profiles[speakerID] = profile
    }

    /// Match each tracked speaker to a voice. Returns one per speaker ID found, in the order first seen.
    /// Voice assignments are sticky: once a speaker is assigned a voice, that assignment is kept across calls.
    /// Speakers without enough speech yet get the default voice.
    public func matchedVoices(voices: [VoiceCalibration], normalSyllablesPerSecond: Double,
                              defaultVoiceID: String? = nil) -> [Int: MatchedVoice] {
        // Use speakers in insertion order, not sorted ID order
        let orderedIDs = speakerInsertionOrder.filter { profiles[$0] != nil }
        let speakers: [SpeakerTraits?] = orderedIDs.map { profiles[$0]?.traits }
        let matches = VoiceMatch.match(speakers, voices: voices, normalSyllablesPerSecond: normalSyllablesPerSecond,
                                       defaultVoiceID: defaultVoiceID)

        var result: [Int: MatchedVoice] = [:]
        for (i, id) in orderedIDs.enumerated() {
            if i < matches.count {
                let matched = matches[i]

                // If we have a sticky assignment, construct a new MatchedVoice with that voice
                // but preserve the recalculated pitch/rate from the fresh match
                if let stickyVoiceID = stickyVoiceAssignment[id] {
                    result[id] = MatchedVoice(voiceID: stickyVoiceID,
                                             pitchMultiplier: matched.pitchMultiplier,
                                             rate: matched.rate)
                } else {
                    // First time matching this speaker - lock the assignment
                    stickyVoiceAssignment[id] = matched.voiceID
                    result[id] = matched
                }
            }
        }

        return result
    }
}
