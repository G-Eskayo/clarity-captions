import Foundation

/// One process's sound, as Core Audio reports it: who (bundle ID, or the executable's name for a daemon without one)
/// and whether it is recording and playing right now.
public struct CallAudioActivity: Equatable, Sendable {
    public let name: String
    public let isRunningInput: Bool
    public let isRunningOutput: Bool

    public init(name: String, isRunningInput: Bool, isRunningOutput: Bool) {
        self.name = name
        self.isRunningInput = isRunningInput
        self.isRunningOutput = isRunningOutput
    }
}

/// How the Mac app knows a call is live (#178). CallKit's call observer is unavailable on macOS, so it reads Core
/// Audio instead: a call is up while FaceTime or its call services are using the microphone. Public API, no
/// permission needed.
public enum CallSignal {
    /// FaceTime video and audio calls, and iPhone calls handed to the Mac (Continuity), which run through FaceTime.
    public static let callProcesses: Set<String> = ["com.apple.FaceTime", "avconferenced", "com.apple.avconferenced",
                                                    "callservicesd", "com.apple.TelephonyUtilities"]

    public static func isCallLive(_ activity: [CallAudioActivity]) -> Bool {
        activity.contains { $0.isRunningInput && callProcesses.contains($0.name) }
    }
}

#if os(macOS)
import CoreAudio
import Darwin

/// Tells the app when a call starts and ends, from Core Audio's change notifications (no polling). An end must hold
/// for `endGrace` seconds, so a call's audio route changing (headphones in, a Bluetooth switch) doesn't end it.
public final class CallWatcher {
    /// On the main queue: true when a call starts, false when it ends.
    public var onChange: (Bool) -> Void = { _ in }
    public private(set) var isCallLive = false
    public var endGrace: TimeInterval = 2

    private let queue = DispatchQueue(label: "seal.callwatcher")
    private var watched: Set<AudioObjectID> = []
    private var pendingEnd: DispatchWorkItem?
    private lazy var listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.reevaluate() }

    public init() {}

    public func start() {
        var list = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, queue, listener)
        queue.async { self.reevaluate() }
    }

    public func stop() {
        var list = Self.address(kAudioHardwarePropertyProcessObjectList)
        AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &list, queue, listener)
        queue.sync {
            for object in watched { unwatch(object) }
            watched = []
            pendingEnd?.cancel()
        }
    }

    /// What every process with audio is doing right now (also handy for a diagnostic line in the log).
    public static func snapshot() -> [CallAudioActivity] {
        ProcessTapAudioSource.processObjects().map { activity(of: $0) }
    }

    private func reevaluate() {
        let objects = Set(ProcessTapAudioSource.processObjects())
        for object in objects.subtracting(watched) { watch(object) }
        for object in watched.subtracting(objects) { unwatch(object) }
        watched = objects

        let live = CallSignal.isCallLive(objects.map { Self.activity(of: $0) })
        if live {
            pendingEnd?.cancel()
            pendingEnd = nil
            publish(true)
        } else if isCallLive, pendingEnd == nil {
            let end = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingEnd = nil
                if !CallSignal.isCallLive(Self.snapshot()) { self.publish(false) }
            }
            pendingEnd = end
            queue.asyncAfter(deadline: .now() + endGrace, execute: end)
        }
    }

    private func publish(_ live: Bool) {
        guard live != isCallLive else { return }
        isCallLive = live
        DispatchQueue.main.async { self.onChange(live) }
    }

    private static let watchedSelectors = [kAudioProcessPropertyIsRunningInput, kAudioProcessPropertyIsRunningOutput]

    private func watch(_ object: AudioObjectID) {
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectAddPropertyListenerBlock(object, &address, queue, listener)
        }
    }

    private func unwatch(_ object: AudioObjectID) {
        for selector in Self.watchedSelectors {
            var address = Self.address(selector)
            AudioObjectRemovePropertyListenerBlock(object, &address, queue, listener)
        }
    }

    private static func activity(of object: AudioObjectID) -> CallAudioActivity {
        CallAudioActivity(name: name(of: object), isRunningInput: flag(object, kAudioProcessPropertyIsRunningInput),
                          isRunningOutput: flag(object, kAudioProcessPropertyIsRunningOutput))
    }

    private static func name(of object: AudioObjectID) -> String {
        if let id = ProcessTapAudioSource.bundleID(of: object), !id.isEmpty { return id }
        guard let pid = ProcessTapAudioSource.pid(of: object) else { return "" }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return "" }
        return (String(cString: path) as NSString).lastPathComponent
    }

    private static func flag(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Bool {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr && value != 0
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
#endif
