import Foundation

/// Why the one-time speech download didn't finish, in words a first-time user can act on (ADR 0013).
public enum DownloadProblem: Equatable, Sendable {
    case offline
    /// Nothing moved for a long stretch: a dead connection, or a download that never started.
    case stalled
    case failed

    public var message: String { message(language: String(localized: "English")) }

    /// #37: the offline words name the language being downloaded.
    public func message(language: String) -> String {
        switch self {
        case .offline: String(format: String(localized: "Seal needs the internet once, for Apple's %@ speech files. Turn on Wi-Fi and try again."), language)
        case .stalled: String(localized: "The download stopped moving. Check that Wi-Fi is on and try again.")
        case .failed: String(localized: "Seal couldn't finish the download. Check that Wi-Fi is on and try again.")
        }
    }

    static func from(_ error: Error) -> DownloadProblem {
        let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                                                 .cannotFindHost, .cannotConnectToHost, .timedOut, .internationalRoamingOff]
        if let url = error as? URLError, offlineCodes.contains(url.code) { return .offline }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, offlineCodes.contains(URLError.Code(rawValue: ns.code)) { return .offline }
        return .failed
    }
}

public enum DownloadOutcome: Equatable, Sendable {
    case installed
    case failed(DownloadProblem)
    /// A download is already in progress; nothing new was started.
    case alreadyRunning
    /// #245: the task waiting for it was cancelled (Stop in the split); the install was told to stop too.
    case cancelled
}

/// Counts watchdog ticks with no forward progress. Progress that goes backwards is not movement.
struct StallWatch {
    let limit: Int
    private var best = -Double.infinity
    private var flatTicks = 0
    init(limit: Int) { self.limit = limit }

    /// Returns true once progress hasn't moved forward for more than `limit` ticks in a row.
    mutating func tick(progress: Double) -> Bool {
        if progress > best { best = progress; flatTicks = 0; return false }
        flatTicks += 1
        return flatTicks >= limit
    }
}

/// Runs the speech download (#81) so it always ends: installed, or a plain-words problem the screen can show with
/// Try again. One download at a time; a stalled one is abandoned (and cancelled) rather than waited on.
public final class SpeechDownload: @unchecked Sendable {
    public typealias Install = @Sendable (_ progress: @escaping @Sendable (Double) -> Void) async throws -> Void

    private let install: Install
    private let tick: Duration
    private let stallTicks: Int
    private let sleep: @Sendable (Duration) async -> Void
    private let lock = NSLock()
    private var running = false

    /// Default: give up after 90 seconds without any forward progress.
    public init(install: @escaping Install,
                tick: Duration = .seconds(1),
                stallTicks: Int = 90,
                sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        self.install = install
        self.tick = tick
        self.stallTicks = stallTicks
        self.sleep = sleep
    }

    /// The real download of Apple's English speech files.
    public static func english() -> SpeechDownload { language(Locale(identifier: "en-US")) }

    /// The real download of Apple's speech files for one caption language (#37).
    public static func language(_ locale: Locale) -> SpeechDownload {
        SpeechDownload(install: { progress in try await SpeechModelInstaller.install(locale: locale, onProgress: progress) })
    }

    public func run(onProgress: @escaping @Sendable (Double) -> Void) async -> DownloadOutcome {
        let started: Bool = lock.withLock { if running { return false }; running = true; return true }
        guard started else { return .alreadyRunning }
        defer { lock.withLock { running = false } }

        let latest = Latest()
        let once = FirstWins()
        let install = self.install
        let work = WorkBox()
        // #245: Stop in the split cancels the task waiting here. The install is cancelled with it, and this returns at
        // once whether or not the install notices.
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                work.resume = { if once.claim() { continuation.resume(returning: .cancelled) } }
                if Task.isCancelled { work.cancel(); return }
                work.set(Task {
                    do {
                        try await install { p in latest.set(p); onProgress(p) }
                        if once.claim() { continuation.resume(returning: Task.isCancelled ? .cancelled : .installed) }
                    } catch {
                        if once.claim() {
                            continuation.resume(returning: Task.isCancelled ? .cancelled : .failed(DownloadProblem.from(error)))
                        }
                    }
                })
                Task { [tick, stallTicks, sleep] in
                    var watch = StallWatch(limit: stallTicks)
                    while !work.isCancelled {
                        await sleep(tick)
                        if once.isClaimed { return }
                        if watch.tick(progress: latest.value) {
                            if once.claim() { work.cancel(); continuation.resume(returning: .failed(.stalled)) }
                            return
                        }
                    }
                }
            }
        } onCancel: {
            work.cancel()
        }
    }
}

/// The install's task, and how to end the wait for it, for a cancel that can arrive before either exists.
private final class WorkBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var cancelled = false
    private var _resume: (() -> Void)?

    var resume: (() -> Void)? {
        get { lock.withLock { _resume } }
        set { lock.withLock { _resume = newValue } }
    }

    func set(_ task: Task<Void, Never>) {
        let late = lock.withLock { () -> Bool in self.task = task; return cancelled }
        if late { task.cancel() }
    }

    var isCancelled: Bool { lock.withLock { cancelled || (task?.isCancelled ?? false) } }

    /// Cancels the install, if started, and ends the wait.
    func cancel() {
        let (task, resume) = lock.withLock { () -> (Task<Void, Never>?, (() -> Void)?) in cancelled = true; return (self.task, _resume) }
        task?.cancel()
        resume?()
    }
}

private final class Latest: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0.0
    func set(_ v: Double) { lock.withLock { stored = v } }
    var value: Double { lock.withLock { stored } }
}

/// Lets exactly one of several racing tasks resume a continuation.
private final class FirstWins: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { if claimed { return false }; claimed = true; return true } }
    var isClaimed: Bool { lock.withLock { claimed } }
}
