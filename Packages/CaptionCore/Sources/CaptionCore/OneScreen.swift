import Foundation

/// Round 2 (#118, design #117): the app is one screen. These are the pages it can show. Each replaces the last on the
/// same background with a fade, never a sheet or a push.
public enum AppScreen: Hashable, Sendable {
    case captions
    case settings
    case saved
    case savedConversation(UUID)
    case credits
    case licenseText
    /// Beta installs only (ADR 0023): "What will be sent".
    case feedbackPreview

    /// Where going back lands. Settings goes back to the captions; its own pages go back to Settings.
    public var parent: AppScreen? {
        switch self {
        case .captions: nil
        case .settings: .captions
        case .saved, .credits, .feedbackPreview: .settings
        case .savedConversation: .saved
        case .licenseText: .credits
        }
    }
}

/// Which page is showing, and the only ways to move between them (mock-ups round2/01–02).
public struct ScreenNavigator: Equatable, Sendable {
    public private(set) var current: AppScreen

    public init(_ start: AppScreen = .captions) { current = start }

    /// The captions, with the Start control, show only on the captions page.
    public var showsCaptions: Bool { current == .captions }
    /// The gear stays where it is on the captions and on Settings, where it takes her back. Deeper pages have a
    /// "‹ Settings" (or "‹ Saved", "‹ Credits") word instead.
    public var showsGear: Bool { current == .captions || current == .settings }

    /// The gear: opens Settings from the captions, and goes back from Settings. Nothing anywhere else.
    public mutating func gearTapped() {
        switch current {
        case .captions: current = .settings
        case .settings: current = .captions
        default: break
        }
    }

    /// Opens a page from the page it lives on; anything else is ignored, so a stray call can't jump around.
    public mutating func open(_ screen: AppScreen) {
        guard screen.parent == current else { return }
        current = screen
    }

    /// One step back.
    public mutating func back() {
        if let parent = current.parent { current = parent }
    }

    /// Straight back to the captions, e.g. to start the tour from Settings.
    public mutating func close() { current = .captions }
}

/// A question asked in place, in the retro words style, instead of a pop-up box ([ Start new ] / [ Keep it ],
/// [ Delete all ] / [ Keep ]). It acts once: answering clears it.
public struct InPlaceQuestion<Subject: Equatable & Sendable>: Equatable, Sendable {
    public private(set) var asking: Subject?

    public init() {}

    public var isAsking: Bool { asking != nil }

    public mutating func ask(_ subject: Subject) { asking = subject }

    /// The yes answer: returns what to act on, once.
    public mutating func confirm() -> Subject? {
        defer { asking = nil }
        return asking
    }

    /// The no answer ([ Keep it ], [ Keep ]): nothing happens.
    public mutating func keep() { asking = nil }
}

/// [ New ]'s one question (#106, asked in place since #118).
public enum NewConversationQuestion: Equatable, Sendable {
    case startNew

    public enum Outcome: Equatable, Sendable { case ask, startNow }

    /// With unsaved changes she's asked first; with nothing to lose, it starts a new conversation at once.
    public static func request(hasUnsavedChanges: Bool, question: inout InPlaceQuestion<NewConversationQuestion>) -> Outcome {
        guard hasUnsavedChanges else { question.keep(); return .startNow }
        question.ask(.startNew)
        return .ask
    }
}

/// The saved list's questions, asked in place at the bottom of the list or the conversation.
public enum SavedListQuestion: Equatable, Sendable {
    case deleteAll
    case delete(UUID)
}
