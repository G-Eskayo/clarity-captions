import Foundation

/// #245: a half's language whose speech engine isn't on the device yet, being fetched for that half.
public struct FaceToFaceDownload: Equatable, Sendable {
    public enum Progress: Equatable, Sendable {
        case downloading(Double)
        case failed(DownloadProblem)
    }
    public let locale: Locale
    public var progress: Progress

    public init(locale: Locale, progress: Progress) {
        self.locale = locale
        self.progress = progress
    }
}

/// #245: the speech downloads running in the split, at most one per half. Each is known by its ticket, so one left
/// behind (another pick in that half, Stop) never shows progress or starts its language when it ends.
///
/// Space: O(1), two halves.
public struct FaceToFaceDownloads: Equatable, Sendable {
    public struct Ticket: Equatable, Hashable, Sendable {
        public let half: FaceToFaceHalf
        public let locale: Locale
        fileprivate let id: Int
    }

    public private(set) var byHalf: [FaceToFaceHalf: FaceToFaceDownload] = [:]
    private var current: [FaceToFaceHalf: Ticket] = [:]
    private var next = 0

    public init() {}

    /// `locale` tapped in `half` and not on the device: its download starts, replacing any other in that half. Nil
    /// when that half is already downloading it (a second tap starts nothing). A failed one starts again.
    public mutating func begin(_ locale: Locale, for half: FaceToFaceHalf) -> Ticket? {
        if let d = byHalf[half], d.locale == locale, case .downloading = d.progress { return nil }
        next += 1
        let ticket = Ticket(half: half, locale: locale, id: next)
        current[half] = ticket
        byHalf[half] = FaceToFaceDownload(locale: locale, progress: .downloading(0))
        return ticket
    }

    public mutating func progress(_ fraction: Double, for ticket: Ticket) {
        guard isCurrent(ticket) else { return }
        byHalf[ticket.half]?.progress = .downloading(fraction)
    }

    /// The download ended. Returns the language to pick now that it's on the device; nil when it failed (the half
    /// says so, with what to do), was cancelled, or was left behind.
    public mutating func finished(_ ticket: Ticket, outcome: DownloadOutcome) -> Locale? {
        guard isCurrent(ticket) else { return nil }
        switch outcome {
        case .installed: clear(ticket.half); return ticket.locale
        case .alreadyRunning, .cancelled: clear(ticket.half); return nil
        case .failed(let problem): byHalf[ticket.half]?.progress = .failed(problem); return nil
        }
    }

    /// Leaves `half`'s download behind (another language picked there). True when one was running, to cancel.
    @discardableResult
    public mutating func drop(_ half: FaceToFaceHalf) -> Bool {
        var running = false
        if case .downloading = byHalf[half]?.progress { running = true }
        clear(half)
        return running
    }

    /// Leaving the split: every download is left behind.
    public mutating func dropAll() {
        byHalf = [:]
        current = [:]
    }

    private func isCurrent(_ ticket: Ticket) -> Bool { current[ticket.half] == ticket }

    private mutating func clear(_ half: FaceToFaceHalf) {
        byHalf[half] = nil
        current[half] = nil
    }
}

/// #245: whether the two picked languages can be translated on the device right now.
public enum FaceToFaceTranslationReadiness: Equatable, Sendable {
    case ready
    /// Apple's language pack for the pair is being fetched (its own sheet shows the progress).
    case downloading
    /// Apple can't translate this pair on this device. Captions carry on, as said.
    case unsupported
}

/// #245 item 2, the owner's rule: the split never sits silent. What one half says is happening, in plain words.
public enum FaceToFaceStatus: Equatable, Sendable {
    case tapYourLanguage
    case tapToSwitch
    case downloading(language: String, fraction: Double)
    case downloadFailed(language: String, problem: DownloadProblem)
    case starting
    case listening
    case listeningWaitingForOther
    case translationDownloading(pair: String)
    case cantTranslate(pair: String)
    case paused
    case failed(String)

    /// What `half` says. Only her half has Start, so only hers is told to tap it.
    public func words(for half: FaceToFaceHalf) -> String {
        switch self {
        case .tapYourLanguage: String(localized: "Tap your language to start")
        case .tapToSwitch: String(localized: "Tap a language to switch")
        case .downloading(let language, let fraction):
            String(format: String(localized: "Downloading %@ (%d%%)"), language, Int((fraction * 100).rounded()))
        case .downloadFailed(let language, let problem): problem.message(language: language)
        case .starting: String(localized: "Starting…")
        case .listening: String(localized: "Listening")
        case .listeningWaitingForOther: String(localized: "Listening. Waiting for the other person to pick")
        case .translationDownloading(let pair): String(format: String(localized: "Listening. Downloading %@ translation"), pair)
        case .cantTranslate(let pair): String(format: String(localized: "Can't translate %@ on this device. Captions show as said"), pair)
        case .paused: half == .owner ? String(localized: "Paused. Tap Start to carry on") : String(localized: "Paused")
        case .failed(let reason): half == .owner ? reason + String(localized: ". Tap Start to try again") : reason
        }
    }

    /// What `half` says now. A download in that half comes first, then its list, then what the captions are doing.
    public static func of(_ half: FaceToFaceHalf, split: FaceToFaceSplit, state: CaptionState,
                          downloads: [FaceToFaceHalf: FaceToFaceDownload], translation: FaceToFaceTranslationReadiness,
                          name: (Locale) -> String) -> FaceToFaceStatus {
        if let download = downloads[half] {
            switch download.progress {
            case .downloading(let f): return .downloading(language: name(download.locale), fraction: f)
            case .failed(let problem): return .downloadFailed(language: name(download.locale), problem: problem)
            }
        }
        if split.showsList(half) { return split.language(of: half) == nil ? .tapYourLanguage : .tapToSwitch }
        if case .failed(let reason) = state { return .failed(reason) }
        if split.isPaused { return .paused }
        guard state == .listening else { return .starting }
        guard let pair = split.languagePair else { return .listeningWaitingForOther }
        let pairName = name(pair.partner) + " ↔ " + name(pair.owner)
        switch translation {
        case .ready: return .listening
        case .downloading: return .translationDownloading(pair: pairName)
        case .unsupported: return .cantTranslate(pair: pairName)
        }
    }
}

/// #245 item 1: the split's starts, restarts and Stop, one after another, except that leaving drops everything still
/// queued and never waits for work already running. Each piece of work is told whether it's still current after
/// any wait, so work left behind does nothing more.
@MainActor
public final class SplitWorkQueue {
    private var tail: Task<Void, Never>?
    private var generation = 0

    public init() {}

    /// Runs `work` after everything queued before it. `isCurrent()` turns false once `cancelAll()` is called.
    public func enqueue(_ work: @escaping @MainActor (_ isCurrent: @escaping () -> Bool) async -> Void) {
        let previous = tail
        let mine = generation
        let isCurrent: () -> Bool = { [weak self] in self?.generation == mine }
        tail = Task { @MainActor in
            await previous?.value
            guard isCurrent() else { return }
            await work(isCurrent)
        }
    }

    /// Leaves everything queued or running behind: queued work never starts, and new work doesn't wait for it.
    public func cancelAll() {
        generation += 1
        tail = nil
    }

    /// Returns once everything queued so far has finished (debug demos wait on it).
    public func drained() async { await tail?.value }
}
