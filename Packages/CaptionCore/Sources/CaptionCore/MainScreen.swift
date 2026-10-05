import Foundation

/// What the captioning engine is doing, in the only terms the main screen needs.
public enum CaptionState: Equatable, Sendable {
    case idle, preparing, listening
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
    public var accessibilityLabel: String { presentation == .compact ? "Stop captions" : title }

    public static func `for`(_ state: CaptionState) -> PrimaryControl {
        switch state {
        case .idle: PrimaryControl(title: "Start captions", action: .start, isEnabled: true)
        case .preparing: PrimaryControl(title: "Getting ready…", action: .none, isEnabled: false)
        case .listening: PrimaryControl(title: "Stop", action: .stop, isEnabled: true, presentation: .compact)
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

    /// Combines headline and detail into a single accessible announcement.
    public static func announcement(for state: CaptionState) -> String {
        let head = headline(for: state)
        if let det = detail(for: state) { return "\(head). \(det)" }
        return head
    }
}
