#if os(macOS)
import AVFoundation
import CoreAudio
import Foundation

/// Why call audio can't be captioned, in words the window can show.
public enum CallAudioError: Error, Equatable {
    /// Nothing to listen to: no app named, or the chosen process isn't playing any sound.
    case appNotPlayingSound
    /// Core Audio refused the tap or the device that reads it (status code kept for the log).
    case coreAudio(step: String, status: Int32)
}

/// The apps whose sound is "the call". FaceTime video calls and iPhone calls handed to the Mac (Continuity) both play
/// through FaceTime, but the far side's voice may be rendered by its conferencing service rather than the app itself,
/// so both are listed. Unverified on a live call from this Mac mini (no call can be placed headless); the
/// `.allSystemAudio` target does not depend on this list.
public enum CallApps {
    public static let faceTime: [String] = ["com.apple.FaceTime", "com.apple.avconferenced", "com.apple.TelephonyUtilities"]
}

/// Another app's sound, captured with a Core Audio process tap (macOS 14.2+) and read through a private aggregate
/// device. Needs the "System Audio Recording Only" permission, not screen recording (ADR 0026). Without that permission
/// macOS delivers silence rather than an error, which `peakLevel` makes visible.
public final class ProcessTapAudioSource: AudioSource {
    public enum Target: Equatable {
        /// Every sound the Mac plays except this app's own.
        case allSystemAudio
        /// Only these running apps, by bundle ID (FaceTime: `CallApps.faceTime`).
        case apps(bundleIDs: [String])
        /// Only these processes, by PID (tests tap an `afplay` they started).
        case processes([pid_t])
    }

    public let target: Target
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var started = false
    private var format: AVAudioFormat?
    private let queue = DispatchQueue(label: "captions.process-tap", qos: .userInteractive)
    private let lock = NSLock()
    private var peak: Float = 0
    private var frames = 0

    public init(target: Target) {
        self.target = target
    }

    /// Loudest sample seen so far (0 = only silence arrived).
    public var peakLevel: Float { lock.withLock { peak } }
    /// Frames the tap has handed over so far (0 = the tap never ran).
    public var framesDelivered: Int { lock.withLock { frames } }

    public func open() throws -> AVAudioFormat {
        if let format { return format }
        let description: CATapDescription
        switch target {
        case .allSystemAudio:
            let own = Self.processObjects().filter { Self.pid(of: $0) == getpid() }
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: own)
        case .apps(let bundleIDs):
            guard !bundleIDs.isEmpty else { throw CallAudioError.appNotPlayingSound }
            // By bundle ID (macOS 26), not by process: FaceTime's call audio usually starts after captions do, and
            // restore keeps the tap on an app that quits and comes back mid-session.
            description = CATapDescription(stereoMixdownOfProcesses: [])
            description.bundleIDs = bundleIDs
            description.isProcessRestoreEnabled = true
        case .processes(let pids):
            let objects = pids.compactMap(Self.processObject(for:))
            guard !objects.isEmpty else { throw CallAudioError.appNotPlayingSound }
            description = CATapDescription(stereoMixdownOfProcesses: objects)
        }
        description.name = "Seal Speak call captions"
        description.isPrivate = true
        description.muteBehavior = .unmuted   // the person still hears the call

        do {
            try check("create tap", AudioHardwareCreateProcessTap(description, &tapID))
            var asbd = AudioStreamBasicDescription()
            try read(tapID, kAudioTapPropertyFormat, into: &asbd, step: "read tap format")
            guard let tapFormat = AVAudioFormat(streamDescription: &asbd) else {
                throw CallAudioError.coreAudio(step: "tap format", status: -1)
            }

            var subDevices: [[String: Any]] = []
            if let outputUID = Self.defaultOutputUID() { subDevices = [[kAudioSubDeviceUIDKey: outputUID]] }
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Seal Speak call captions",
                kAudioAggregateDeviceUIDKey: "com.gileskayo.captions.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: subDevices,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapDriftCompensationKey: true,
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                ]],
            ]
            try check("create aggregate device", AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID))
            format = tapFormat
            return tapFormat
        } catch {
            stop()
            throw error
        }
    }

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        guard let format, aggregateID != kAudioObjectUnknown else { throw CallAudioError.appNotPlayingSound }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: input, deallocator: nil),
                  buffer.frameLength > 0 else { return }
            self?.notePeak(buffer)
            // The tap reuses its memory after this block returns: hand on a copy.
            if let copy = Self.copy(buffer) { onBuffer(copy) }
        }
        try check("create IO proc", status)
        try check("start device", AudioDeviceStart(aggregateID, procID))
        started = true
    }

    /// Returns at once. Core Audio's teardown can block for a minute when the tap never ran (no permission yet), so it
    /// runs on its own queue; `waitForTeardown` lets a test see it finish.
    public func stop() {
        let (aggregate, tap, proc, wasRunning) = (aggregateID, tapID, procID, started && framesDelivered > 0)
        procID = nil
        started = false
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        format = nil
        guard aggregate != kAudioObjectUnknown || tap != kAudioObjectUnknown else { return }
        DispatchQueue.global(qos: .utility).async(group: teardown) {
            if aggregate != kAudioObjectUnknown {
                if let proc {
                    if wasRunning { AudioDeviceStop(aggregate, proc) }
                    AudioDeviceDestroyIOProcID(aggregate, proc)
                }
                AudioHardwareDestroyAggregateDevice(aggregate)
            }
            if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        }
    }

    private let teardown = DispatchGroup()

    /// True once every device and tap this source made is gone.
    @discardableResult
    public func waitForTeardown(timeout: TimeInterval) -> Bool { teardown.wait(timeout: .now() + timeout) == .success }

    deinit { stop() }

    // MARK: - Helpers

    private func notePeak(_ buffer: AVAudioPCMBuffer) {
        guard let ch = buffer.floatChannelData else { return }
        var m: Float = 0
        for c in 0..<Int(buffer.format.channelCount) {
            for i in 0..<Int(buffer.frameLength) { m = max(m, abs(ch[c][i])) }
        }
        lock.withLock { peak = max(peak, m); frames += Int(buffer.frameLength) }
    }

    private static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let out = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        out.frameLength = buffer.frameLength
        let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let dst = UnsafeMutableAudioBufferListPointer(out.mutableAudioBufferList)
        for (s, d) in zip(src, dst) {
            guard let sp = s.mData, let dp = d.mData else { continue }
            memcpy(dp, sp, Int(min(s.mDataByteSize, d.mDataByteSize)))
        }
        return out
    }

    private func check(_ step: String, _ status: OSStatus) throws {
        guard status == noErr else { throw CallAudioError.coreAudio(step: step, status: status) }
    }

    private func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, into value: inout T, step: String) throws {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        try check(step, AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value))
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    /// Core Audio's objects for processes that currently have audio clients.
    static func processObjects() -> [AudioObjectID] { objectList(kAudioHardwarePropertyProcessObjectList) }

    static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    static func pid(of object: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var pid: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid) == noErr ? pid : nil
    }

    static func bundleID(of object: AudioObjectID) -> String? { string(object, kAudioProcessPropertyBundleID) }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func defaultOutputUID() -> String? {
        var address = address(kAudioHardwarePropertyDefaultSystemOutputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return string(device, kAudioDevicePropertyDeviceUID)
    }

    /// Every audio device's UID, private aggregates included: lets a test prove `stop()` left nothing behind.
    static func deviceUIDs() -> [String] { objectList(kAudioHardwarePropertyDevices).compactMap { string($0, kAudioDevicePropertyDeviceUID) } }
}
#endif
