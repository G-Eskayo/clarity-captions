import Foundation

public enum CaptionSessionLifecycle {
    public enum Action: Equatable {
        case save(SavedConversation)
        case discard
        case none
    }

    public static func action(
        for state: CaptionState,
        sessionStartedAt: Date?,
        lines: [CaptionLine],
        speakerNames: SpeakerNames = SpeakerNames()
    ) -> Action {
        guard let startedAt = sessionStartedAt else { return .none }

        switch state {
        case .preparing, .listening, .paused:
            return .none
        case .idle, .failed:
            if SessionRetention.shouldSave(lines: lines) {
                let conversation = SavedConversation.from(sessionStart: startedAt, lines: lines, speakerNames: speakerNames)
                return .save(conversation)
            } else {
                return .discard
            }
        }
    }
}
