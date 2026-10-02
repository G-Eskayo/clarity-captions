import Foundation

/// What the captioning engine is doing, in the only terms the main screen needs.
public enum CaptionState: Equatable, Sendable {
    case idle, preparing, listening
    case failed(String)
}

/// The single primary control on the main screen (ADR 0013: one obvious action).
public struct PrimaryControl: Equatable, Sendable {
    public enum Action: Equatable, Sendable { case start, stop, none }
    public let title: String
    public let action: Action
    public let isEnabled: Bool

    public static func `for`(_ state: CaptionState) -> PrimaryControl {
        switch state {
        case .idle: PrimaryControl(title: "Start captions", action: .start, isEnabled: true)
        case .preparing: PrimaryControl(title: "Getting ready…", action: .none, isEnabled: false)
        case .listening: PrimaryControl(title: "Stop", action: .stop, isEnabled: true)
        case .failed: PrimaryControl(title: "Try again", action: .start, isEnabled: true)
        }
    }
}

/// Plain-language state. Technical reasons are `detail`, never the headline.
/// Final wording for silence vs failure is decided in the design session; this is the baseline.
public enum StatusWords {
    public static func headline(for state: CaptionState) -> String {
        switch state {
        case .idle: "Ready"
        case .preparing: "Getting ready…"
        case .listening: "Listening"
        case .failed: "Stopped"
        }
    }

    public static func detail(for state: CaptionState) -> String? {
        if case .failed(let reason) = state { return reason }
        return nil
    }
}
