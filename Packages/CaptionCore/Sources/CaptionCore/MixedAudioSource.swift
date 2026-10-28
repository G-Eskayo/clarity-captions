import AVFoundation

/// Sums several inputs' samples (all in one format) into one stream (#172: the room mic and the call together, so one
/// engine and one speaker model caption everybody). Every moment goes out exactly once, in order. An input that goes
/// quiet (no permission yet, no call yet) counts as silence once another input is more than `maxLagFrames` ahead, so it
/// never holds the others up; when it wakes, its samples count from then on.
public struct AudioMixer {
    private var queues: [[Float]]
    private let maxLag: Int

    public init(inputs: Int, maxLagFrames: Int) {
        queues = Array(repeating: [], count: inputs)
        maxLag = maxLagFrames
    }

    /// Adds `samples` to input `index` and returns whatever is now ready to go out (often nothing).
    public mutating func push(_ samples: [Float], into index: Int) -> [Float] {
        guard queues.indices.contains(index) else { return [] }
        queues[index] += samples
        var out = take(queues.map(\.count).min() ?? 0)
        if let longest = queues.map(\.count).max(), longest > maxLag { out += take(longest) }
        return out
    }

    /// Mixes the next `n` frames, treating an input with fewer queued as silent for the rest.
    private mutating func take(_ n: Int) -> [Float] {
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        for q in queues.indices {
            let k = min(n, queues[q].count)
            for i in 0..<k { out[i] += queues[q][i] }
            queues[q].removeFirst(k)
        }
        for i in out.indices { out[i] = min(1, max(-1, out[i])) }
        return out
    }
}

/// Several sources heard as one (#172): on the Mac, the room microphone plus the call. Each source's buffers are
/// converted to 48 kHz mono and summed by `AudioMixer`. Starting fails only if every source fails; one that can't open
/// (no microphone, say) is left out and the rest carry on.
public final class MixedAudioSource: AudioSource {
    public static let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!

    private let sources: [AudioSource]
    private var opened: [(index: Int, source: AudioSource, converter: AVAudioConverter)] = []
    private let lock = NSLock()
    private var mixer: AudioMixer
    private let maxLagFrames: Int

    /// `maxLagSeconds`: how long one source may run ahead before a quiet one counts as silence.
    public init(_ sources: [AudioSource], maxLagSeconds: Double = 0.25) {
        self.sources = sources
        maxLagFrames = Int(maxLagSeconds * Self.format.sampleRate)
        mixer = AudioMixer(inputs: sources.count, maxLagFrames: maxLagFrames)
    }

    public func open() throws -> AVAudioFormat {
        var firstError: Error?
        opened = []
        for (i, source) in sources.enumerated() {
            do {
                let inFormat = try source.open()
                guard let converter = AVAudioConverter(from: inFormat, to: Self.format) else {
                    throw TranscriptionError.converterUnavailable
                }
                opened.append((i, source, converter))
            } catch {
                source.stop()
                firstError = firstError ?? error
            }
        }
        if opened.isEmpty { throw firstError ?? TranscriptionError.converterUnavailable }
        // Inputs that never opened are silent from the start, not something to wait for.
        mixer = AudioMixer(inputs: opened.count, maxLagFrames: maxLagFrames)
        return Self.format
    }

    public func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        var started = 0
        var firstError: Error?
        for (slot, entry) in opened.enumerated() {
            do {
                try entry.source.start { [weak self] buffer in
                    guard let self, let samples = Self.convert(buffer, with: entry.converter) else { return }
                    let out = self.lock.withLock { self.mixer.push(samples, into: slot) }
                    if !out.isEmpty, let mixed = Self.buffer(out) { onBuffer(mixed) }
                }
                started += 1
            } catch {
                entry.source.stop()
                firstError = firstError ?? error
            }
        }
        if started == 0 { throw firstError ?? TranscriptionError.converterUnavailable }
    }

    public func stop() {
        for source in sources { source.stop() }
        opened = []
    }

    private static func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> [Float]? {
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var fed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let ch = out.floatChannelData else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
    }

    private static func buffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let ch = b.floatChannelData else { return nil }
        b.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { ch[0].update(from: $0.baseAddress!, count: samples.count) }
        return b
    }
}
