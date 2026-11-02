@preconcurrency import AVFoundation
import Foundation

public enum AudioFiles {
    /// Mono float at `rate`, from any PCM buffers (the synthesizer hands out 22.05 kHz int16 or float).
    public static func resample(_ buffers: [AVAudioPCMBuffer], to rate: Double) throws -> AVAudioPCMBuffer {
        let out = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let total = buffers.reduce(0) { $0 + Double($1.frameLength) / $1.format.sampleRate }
        let result = AVAudioPCMBuffer(pcmFormat: out, frameCapacity: AVAudioFrameCount(total * rate + 4096))!
        for b in buffers where b.frameLength > 0 {
            let conv = AVAudioConverter(from: b.format, to: out)!
            let chunk = AVAudioPCMBuffer(pcmFormat: out,
                                         frameCapacity: AVAudioFrameCount(Double(b.frameLength) * rate / b.format.sampleRate + 1024))!
            var fed = false
            var err: NSError?
            conv.convert(to: chunk, error: &err) { _, status in
                if fed { status.pointee = .endOfStream; return nil }
                fed = true; status.pointee = .haveData; return b
            }
            if let err { throw err }
            append(chunk, to: result)
        }
        return result
    }

    public static func silence(_ seconds: Double, rate: Double) -> AVAudioPCMBuffer {
        let f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false)!
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(seconds * rate))!
        b.frameLength = b.frameCapacity
        memset(b.floatChannelData![0], 0, Int(b.frameLength) * 4)
        return b
    }

    public static func append(_ src: AVAudioPCMBuffer, to dst: AVAudioPCMBuffer) {
        let n = min(Int(src.frameLength), Int(dst.frameCapacity - dst.frameLength))
        memcpy(dst.floatChannelData![0] + Int(dst.frameLength), src.floatChannelData![0], n * 4)
        dst.frameLength += AVAudioFrameCount(n)
    }

    public static func concat(_ parts: [AVAudioPCMBuffer]) -> AVAudioPCMBuffer {
        let f = parts[0].format
        let b = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: parts.reduce(0) { $0 + $1.frameLength })!
        for p in parts { append(p, to: b) }
        return b
    }

    public static func write(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    }

    /// Narrowband: down to 8 kHz and back up, the band an older Bluetooth headset (CVSD) carries.
    public static func narrowband(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        try resample([try resample([buffer], to: 8000)], to: buffer.format.sampleRate)
    }

    /// White noise mixed in at `snrDb` below the signal's RMS. Seeded, so runs repeat.
    public static func noisy(_ buffer: AVAudioPCMBuffer, snrDb: Double, seed: UInt64 = 233) -> AVAudioPCMBuffer {
        let b = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)!
        b.frameLength = buffer.frameLength
        let level = rms(buffer) / pow(10, snrDb / 20) * 3.0.squareRoot() // uniform in -a...a has RMS a/sqrt(3)
        var state = seed
        let src = buffer.floatChannelData![0], dst = b.floatChannelData![0]
        for i in 0..<Int(buffer.frameLength) {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let u = Double(state >> 11) / Double(1 << 53) * 2 - 1
            dst[i] = src[i] + Float(u * level)
        }
        return b
    }

    public static func rms(_ b: AVAudioPCMBuffer) -> Double {
        guard b.frameLength > 0, let f = b.floatChannelData?[0] else { return 0 }
        var s = 0.0
        for i in 0..<Int(b.frameLength) { s += Double(f[i] * f[i]) }
        return (s / Double(b.frameLength)).squareRoot()
    }
}
