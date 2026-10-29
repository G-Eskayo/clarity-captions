import AVFoundation
#if os(macOS)
import CoreAudio
import os
#endif

/// What an audio device is, as far as choosing a microphone goes.
public struct AudioDeviceInfo: Equatable {
    public enum Transport: Equatable { case builtIn, bluetooth, usb, other }
    public let id: UInt32
    public let transport: Transport
    /// The Mac's own headphone jack (wired headphones in), or the mic of a headset plugged into it.
    public let isHeadphoneJack: Bool

    public init(id: UInt32, transport: Transport, isHeadphoneJack: Bool) {
        self.id = id
        self.transport = transport
        self.isHeadphoneJack = isHeadphoneJack
    }
}

/// Which microphone joins the call on the Mac (#172, owner 2026-10-28 ~10 a.m.).
public enum RoomMicChoice: Equatable {
    /// No headphones: the people in the room, through the Mac's input (the call plays out loud; one stream keeps its echo
    /// from doubling words).
    case room
    /// Headphones with a mic: the wearer only. The call is private, so the room is never picked up.
    case headset
    /// Headphones without a mic, or no input at all: the call only.
    case none

    public static func choose(output: AudioDeviceInfo?, input: AudioDeviceInfo?) -> RoomMicChoice {
        guard let input else { return .none }
        guard let output else { return .room }
        let sameDevice = input.id == output.id
        let headphones = output.transport == .bluetooth || output.isHeadphoneJack || (sameDevice && output.transport != .builtIn)
        if !headphones { return .room }
        if sameDevice { return .headset }
        if output.isHeadphoneJack && input.isHeadphoneJack { return .headset }
        if output.transport == .bluetooth && input.transport == .bluetooth { return .headset }
        return .none
    }
}

#if os(macOS)
/// The microphone side of call captions on the Mac (#172): follows `RoomMicChoice` for the current default devices,
/// and switches live when headphones connect or disconnect, so captions keep going. Delivers 48 kHz mono; while the
/// choice is `.none` it delivers nothing (the mixer treats it as silence).
public final class RoomMicSource: AudioSource {
    public static let format = MixedAudioSource.format
    private static let log = Logger(subsystem: "com.gileskayo.captions", category: "room-mic")

    private let queue = DispatchQueue(label: "captions.room-mic")
    private var inner: AudioSource?
    private var converter: AVAudioConverter?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var listener: AudioObjectPropertyListenerBlock?
    private let lock = NSLock()
    private var currentChoice: RoomMicChoice = .none
    private var lastInputID: UInt32?
    /// Every choice made this session, in order (the first is the starting one): lets a check see a live switch.
    public private(set) var history: [RoomMicChoice] = []

    /// Where the devices come from and which mic gets opened: the Mac's own, except in tests.
    private let route: () -> (RoomMicChoice, UInt32?)
    private let transportOf: (UInt32) -> AudioDeviceInfo.Transport?
    private let makeMic: (UInt32?) -> AudioSource
    private let silenceCheckDelay: TimeInterval

    public convenience init() {
        self.init(route: Self.currentChoice, transportOf: { Self.info($0, scope: kAudioObjectPropertyScopeInput).transport },
                  makeMic: { id in DeviceMicAudioSource(deviceUID: id.flatMap { Self.string($0, kAudioDevicePropertyDeviceUID) }) },
                  silenceCheckDelay: 2.5)
    }

    init(route: @escaping () -> (RoomMicChoice, UInt32?), transportOf: @escaping (UInt32) -> AudioDeviceInfo.Transport?,
         makeMic: @escaping (UInt32?) -> AudioSource, silenceCheckDelay: TimeInterval) {
        self.route = route
        self.transportOf = transportOf
        self.makeMic = makeMic
        self.silenceCheckDelay = silenceCheckDelay
    }

    /// Whether a mic giving only silence is closed and opened again. Never a Bluetooth one (owner, 2026-10-28): each
    /// reopen switches the headset in and out of call mode, and around an iPhone call can hand it to the phone, so the
    /// person stops hearing the call. Open it once and keep it.
    static func restartsOnSilence(_ transport: AudioDeviceInfo.Transport?) -> Bool { transport != .bluetooth }

    public var choice: RoomMicChoice { lock.withLock { currentChoice } }

    public func open() throws -> AVAudioFormat { Self.format }

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        self.onBuffer = onBuffer
        try queue.sync { try apply(route()) }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // A connect or disconnect fires output and input changes back to back and the hardware keeps switching for a
            // moment: let it settle, then decide once.
            self.queue.asyncAfter(deadline: .now() + 1) { try? self.apply(self.route()) }
        }
        listener = block
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
    }

    public func stop() {
        if let listener {
            for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultInputDevice] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, listener)
            }
        }
        listener = nil
        queue.sync {
            inner?.stop()
            inner = nil
            onBuffer = nil
        }
    }

    /// On `queue`. Swaps the microphone when the choice (or the device behind it) changed; a mic that won't start
    /// leaves the call captioned on its own rather than stopping captions.
    private func apply(_ next: (RoomMicChoice, UInt32?), attempt: Int = 1) throws {
        guard let onBuffer else { return }
        let (choice, inputID) = next
        let unchanged = !history.isEmpty && choice == lock.withLock({ currentChoice })
            && (choice == .none || (inputID == lastInputID && inner != nil))
        if unchanged { return }
        inner?.stop()
        inner = nil
        lastInputID = inputID
        if attempt == 1 {
            lock.withLock { currentChoice = choice; history.append(choice) }
            Self.log.notice("room mic: \(Self.describeRoute(), privacy: .public)")
        }
        guard choice != .none else { return }
        // The device's own mic through an AudioQueue, room or headset alike. No echo canceller: Apple's came back silent or
        // garbled after headphones came and went. The call's echo can't double words anyway: mic and call are one stream.
        let mic = makeMic(inputID)
        do {
            let inFormat = try mic.open()
            // Only the first channel is used, then the rate converted (a 7-channel echo-cancelled input once gave silence).
            guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inFormat.sampleRate, channels: 1, interleaved: false),
                  let converter = AVAudioConverter(from: mono, to: Self.format) else { throw TranscriptionError.converterUnavailable }
            Self.log.notice("room mic: \(String(describing: choice), privacy: .public) started, attempt \(attempt), \(inFormat.channelCount) ch at \(inFormat.sampleRate) Hz")
            let alive = Flag()
            try mic.start { buffer in
                guard let first = Self.firstChannel(of: buffer, as: mono) else { return }
                if !alive.isSet, let ch = first.floatChannelData, (0..<Int(first.frameLength)).contains(where: { ch[0][$0] != 0 }) {
                    alive.set()
                    Self.log.notice("room mic: sound arriving (\(String(describing: choice), privacy: .public))")
                }
                if let out = Self.convert(first, with: converter) { onBuffer(out) }
            }
            inner = mic
            // A real mic never gives exact digital silence. One that does (measured: the Mac's mic right after AirPods
            // disconnect) gets restarted; AirPods busy on an iPhone call stay silent, so it gives up after a few tries.
            // A Bluetooth mic is never restarted: it stays open, silent or not, until the route changes.
            let restarts = Self.restartsOnSilence(inputID.flatMap(transportOf))
            queue.asyncAfter(deadline: .now() + silenceCheckDelay) { [weak self] in
                guard let self, !alive.isSet, self.inner === mic else { return }
                guard restarts else {
                    Self.log.notice("room mic: \(String(describing: choice), privacy: .public) gives only silence; Bluetooth, so kept open")
                    return
                }
                guard attempt < 6 else { return }
                Self.log.notice("room mic: \(String(describing: choice), privacy: .public) gave only silence, restarting (attempt \(attempt + 1))")
                mic.stop()
                self.inner = nil
                try? self.apply(self.route(), attempt: attempt + 1)
            }
        } catch {
            mic.stop()
            Self.log.error("room mic: \(String(describing: choice), privacy: .public) failed to start, attempt \(attempt): \(String(describing: error), privacy: .public)")
            // Headphones that just connected are often still switching into headset mode: try again shortly.
            guard attempt < 6 else { return }
            queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, self.lock.withLock({ self.currentChoice }) == choice, self.inner == nil else { return }
                try? self.apply(self.route(), attempt: attempt + 1)
            }
        }
    }

    /// The first channel of a float buffer, as its own mono buffer.
    static func firstChannel(of buffer: AVAudioPCMBuffer, as mono: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let src = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: buffer.frameLength),
              let dst = out.floatChannelData else { return nil }
        out.frameLength = buffer.frameLength
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        for i in 0..<Int(buffer.frameLength) { dst[0][i] = src[0][i * stride] }
        return out
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil && out.frameLength > 0 ? out : nil
    }

    // MARK: - Reading the Mac's devices

    /// The choice for the current default devices, and the input it would use.
    public static func currentChoice() -> (RoomMicChoice, UInt32?) {
        let output = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice).map { info($0, scope: kAudioObjectPropertyScopeOutput) }
        let input = defaultDevice(kAudioHardwarePropertyDefaultInputDevice).map { info($0, scope: kAudioObjectPropertyScopeInput) }
        return (RoomMicChoice.choose(output: output, input: input), input?.id)
    }

    /// A line for logs: the devices and the choice.
    public static func describeRoute() -> String {
        let out = defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let inp = defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let name = { (id: AudioObjectID?) in id.flatMap { string($0, kAudioObjectPropertyName) } ?? "none" }
        return "output \"\(name(out))\", input \"\(name(inp))\" → \(currentChoice().0)"
    }

    private static func defaultDevice(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func info(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> AudioDeviceInfo {
        var transport: UInt32 = 0
        _ = read(device, kAudioDevicePropertyTransportType, scope: kAudioObjectPropertyScopeGlobal, into: &transport)
        let kind: AudioDeviceInfo.Transport = switch transport {
        case kAudioDeviceTransportTypeBuiltIn: .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: .bluetooth
        case kAudioDeviceTransportTypeUSB: .usb
        default: .other
        }
        // The built-in jack reports which side is in use: 'hdpn' headphones out, 'emic' a headset's mic in.
        var source: UInt32 = 0
        let jack = read(device, kAudioDevicePropertyDataSource, scope: scope, into: &source)
            && (source == fourCC("hdpn") || source == fourCC("emic"))
        return AudioDeviceInfo(id: device, transport: kind, isHeadphoneJack: kind == .builtIn && jack)
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }

    private static func read<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope, into value: inout T) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<T>.size)
        return AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
/// A one-way switch that audio threads can set and others read.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
#endif
