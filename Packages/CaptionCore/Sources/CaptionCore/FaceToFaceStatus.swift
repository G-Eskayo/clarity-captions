import Foundation

/// #245 item 3, the owner's rule (2026-10-30): everything a language needs is set up up front, in Settings, and the
/// split never downloads. Its lists offer only fully ready languages: the speech model on the device, and a
/// translation pair downloaded with at least one other ready language. Fewer than two ready, and Face to face opens
/// the setup instead of the split.
///
/// Space: O(n + p) for n candidates and p downloaded pairs. Built in O(n²) pair lookups, n being a handful.
public struct FaceToFaceReadyLanguages: Equatable, Sendable {
    /// What the Face to face button opens.
    public enum Opening: Equatable, Sendable { case split, setup }

    /// The ready languages, each as the region whose speech model is on the device, one per language.
    public let languages: [Locale]
    private let pairs: Set<String>

    /// The one line Settings shows when Face to face opened it instead of the split.
    public static var setupReason: String {
        String(localized: "Face to face needs two languages ready on this device. Set them up here first.")
    }

    /// `candidates` in order (`FaceToFace.offered`); `pairInstalled(a, b)` says whether Apple's translation for the pair
    /// is downloaded, either way round.
    public init(candidates: [Locale], speechInstalled: [Locale], pairInstalled: (Locale, Locale) -> Bool) {
        var seen: Set<String> = []
        let onDevice = candidates.compactMap { FaceToFace.readyLocale(for: $0, speechInstalled: speechInstalled) }
            .filter { seen.insert(Self.code($0)).inserted }
        var pairs: Set<String> = []
        for (i, a) in onDevice.enumerated() {
            for b in onDevice[(i + 1)...] where pairInstalled(a, b) || pairInstalled(b, a) { pairs.insert(Self.pairKey(a, b)) }
        }
        self.pairs = pairs
        languages = onDevice.filter { a in onDevice.contains { b in Self.code(b) != Self.code(a) && pairs.contains(Self.pairKey(a, b)) } }
    }

    /// One key per pair of languages, whatever the regions or the order.
    public static func pairKey(_ a: Locale, _ b: Locale) -> String { [code(a), code(b)].sorted().joined(separator: "|") }

    public func pairReady(_ a: Locale, _ b: Locale) -> Bool { pairs.contains(Self.pairKey(a, b)) }

    public var opening: Opening { languages.count >= 2 ? .split : .setup }

    /// A half's list: the ready languages, without the other half's pick, and only those that translate with it.
    public func choices(for half: FaceToFaceHalf, in split: FaceToFaceSplit, name: (Locale) -> String) -> [Locale] {
        let other = split.language(of: half.other)
        return split.choices(for: half, downloaded: languages, name: name).filter { l in other.map { pairReady(l, $0) } ?? true }
    }

    private static func code(_ l: Locale) -> String { l.language.languageCode?.identifier ?? l.identifier }
}

/// #245 item 2, the owner's rule: the split never sits silent. What one half says is happening, in plain words.
public enum FaceToFaceStatus: Equatable, Sendable {
    case tapYourLanguage
    case tapToSwitch
    case starting
    case listening
    case listeningWaitingForOther
    case paused
    case failed(String)

    /// What `half` says. Only her half has Start, so only hers is told to tap it.
    public func words(for half: FaceToFaceHalf) -> String {
        switch self {
        case .tapYourLanguage: String(localized: "Tap your language to start")
        case .tapToSwitch: String(localized: "Tap a language to switch")
        case .starting: String(localized: "Starting…")
        case .listening: String(localized: "Listening")
        case .listeningWaitingForOther: String(localized: "Listening. Waiting for the other person to pick")
        case .paused: half == .owner ? String(localized: "Paused. Tap Start to carry on") : String(localized: "Paused")
        case .failed(let reason): half == .owner ? reason + String(localized: ". Tap Start to try again") : reason
        }
    }

    /// What `half` says now: its list, then what the captions are doing.
    public static func of(_ half: FaceToFaceHalf, split: FaceToFaceSplit, state: CaptionState) -> FaceToFaceStatus {
        if split.showsList(half) { return split.language(of: half) == nil ? .tapYourLanguage : .tapToSwitch }
        if case .failed(let reason) = state { return .failed(reason) }
        if split.isPaused { return .paused }
        guard state == .listening else { return .starting }
        return split.languagePair == nil ? .listeningWaitingForOther : .listening
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
