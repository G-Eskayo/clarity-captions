import Foundation

/// What the captioning engine is doing, in the only terms the main screen needs.
public enum CaptionState: Equatable, Sendable {
    case idle, preparing, listening, paused(String)
    case failed(String)
}

/// The single primary control on the main screen (ADR 0013: one obvious action).
public struct PrimaryControl: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case start, stop, none }
    /// While captioning, Stop shrinks to a small circle so captions get the room.
    public enum Presentation: Equatable, Sendable { case large, compact }
    public static let compactDiameter: Double = 56

    public let title: String
    public let action: Action
    public let isEnabled: Bool
    public var presentation: Presentation = .large

    /// What VoiceOver says; the compact circle shows only an X, so it needs a real name.
    public var accessibilityLabel: String { presentation == .compact ? String(localized: "Stop captions") : title }

    public static func `for`(_ state: CaptionState) -> PrimaryControl {
        switch state {
        case .idle: PrimaryControl(title: String(localized: "Start captions"), action: .start, isEnabled: true)
        case .preparing: PrimaryControl(title: String(localized: "Getting ready…"), action: .none, isEnabled: false)
        case .listening, .paused: PrimaryControl(title: String(localized: "Stop"), action: .stop, isEnabled: true, presentation: .compact)
        case .failed: PrimaryControl(title: String(localized: "Start again"), action: .start, isEnabled: true)
        }
    }
}

/// Plain-language state. Technical reasons are `detail`, never the headline.
/// Final wording for silence vs failure is decided in the design session; this is the baseline.
public enum StatusWords {
    public static func headline(for state: CaptionState) -> String {
        switch state {
        case .idle: String(localized: "Ready")
        case .preparing: String(localized: "Getting ready…")
        case .listening: String(localized: "Listening")
        case .paused: String(localized: "Captions paused")
        case .failed: String(localized: "Captions stopped")
        }
    }

    /// Activity-aware headline: same for all activities except can't hear.
    public static func headline(for state: CaptionState, activity: ListeningActivity) -> String {
        guard case .listening = state else { return headline(for: state) }
        switch activity {
        case .activelyListening, .noOneTalking:
            return String(localized: "Listening")
        case .cantHearAnything:
            return String(localized: "I can't hear anything")
        }
    }

    public static func detail(for state: CaptionState) -> String? {
        if case .paused(let reason) = state { return reason }
        if case .failed(let reason) = state { return reason }
        return nil
    }

    /// Activity-aware detail line for listening state.
    public static func secondLine(for state: CaptionState, activity: ListeningActivity) -> String? {
        guard case .listening = state else { return detail(for: state) }
        switch activity {
        case .activelyListening:
            return nil
        case .noOneTalking:
            return String(localized: "No one is talking right now")
        case .cantHearAnything:
            return String(localized: "Is something covering the microphone?")
        }
    }

    /// Combines headline and detail into a single accessible announcement.
    public static func announcement(for state: CaptionState) -> String {
        let head = headline(for: state)
        if let det = detail(for: state) { return "\(head). \(det)" }
        return head
    }

    /// Activity-aware announcement combining headline and second line.
    public static func announcement(for state: CaptionState, activity: ListeningActivity) -> String {
        let head = headline(for: state, activity: activity)
        if let line = secondLine(for: state, activity: activity) { return "\(head). \(line)" }
        return head
    }
}
