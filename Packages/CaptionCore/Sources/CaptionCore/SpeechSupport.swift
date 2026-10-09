import Foundation
import Speech

/// Whether this device can caption at all (#80). Apple's on-device speech engine needs newer hardware than iOS 26
/// itself does, so an older iPhone or iPad can install the app and still never show a caption. Checked once per
/// launch, off the caption path (ADR 0015), and never cached: an OS update can change the answer.
public enum SpeechSupport: Equatable, Sendable {
    case supported
    /// The engine can't run on this hardware.
    case unsupportedDevice
    /// The engine runs, but not in the caption language.
    case languageUnsupported

    public var canCaption: Bool { self == .supported }

    /// The live answer from the Speech framework.
    public static func check(locale: Locale = Locale(identifier: "en-US")) async -> SpeechSupport {
        await check(locale: locale,
                    isAvailable: { SpeechTranscriber.isAvailable },
                    supportedLocale: { await SpeechTranscriber.supportedLocale(equivalentTo: $0) })
    }

    /// The decision, with the framework calls injected. A language lookup that doesn't answer within `timeout`
    /// counts as supported: not knowing isn't a reason to dead-end someone, and the download step that follows
    /// has its own visible failure and Try again.
    static func check(locale: Locale,
                      isAvailable: @Sendable () -> Bool,
                      supportedLocale: @escaping @Sendable (Locale) async -> Locale?,
                      timeout: Duration = .seconds(5)) async -> SpeechSupport {
        guard isAvailable() else { return .unsupportedDevice }
        let lookup = Task { await supportedLocale(locale) }
        let answer = await firstOf(lookup: lookup, timeout: timeout)
        switch answer {
        case .timedOut: return .supported
        case .answered(nil): return .languageUnsupported
        case .answered: return .supported
        }
    }

    private enum Answer { case answered(Locale?), timedOut }

    /// Whichever comes first, the lookup or the timeout, without waiting for a lookup that ignores cancellation.
    private static func firstOf(lookup: Task<Locale?, Never>, timeout: Duration) async -> Answer {
        let once = Once()
        return await withCheckedContinuation { continuation in
            let timer = Task {
                try? await Task.sleep(for: timeout)
                if once.claim() { lookup.cancel(); continuation.resume(returning: .timedOut) }
            }
            Task {
                let value = await lookup.value
                if once.claim() { timer.cancel(); continuation.resume(returning: .answered(value)) }
            }
        }
    }
}

/// Lets exactly one of several racing tasks resume a continuation.
final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool { lock.withLock { if claimed { return false }; claimed = true; return true } }
}
