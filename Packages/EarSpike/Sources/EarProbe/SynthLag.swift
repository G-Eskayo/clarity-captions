@preconcurrency import AVFoundation
import EarSpikeKit
import Foundation

/// How long AVSpeechSynthesizer takes from being handed a finished translation to the first sound (#233).
public struct SynthSample: Codable, Sendable {
    public let firstBufferMs: Double    // write() called -> first buffer with audio frames
    public let leadingSilenceMs: Double // quiet at the start of the audio before the voice is audible
    public let audibleMs: Double        // firstBuffer + leadingSilence: lag to sound if played as buffers arrive
    public let synthesisMs: Double      // write() called -> last buffer
    public let audioMs: Double          // length of the spoken audio
}

public struct SpeakSample: Codable, Sendable {
    public let didStartMs: Double       // speak() called -> delegate didStart (system playback path)
    public let didFinishMs: Double
}

public enum SynthLag {
    /// Renders `text` with `voice` to buffers (no speaker), timing the first audible sample.
    @MainActor
    public static func render(_ text: String, voice: AVSpeechSynthesisVoice?, synth: AVSpeechSynthesizer,
                              keep: ((AVAudioPCMBuffer) -> Void)? = nil) async -> SynthSample {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        let t0 = CFAbsoluteTimeGetCurrent()
        return await withCheckedContinuation { (done: CheckedContinuation<SynthSample, Never>) in
            var first: Double?
            var frames = 0.0
            var silentFrames = 0.0
            var heard = false
            var rate = 22050.0
            var finished = false
            synth.write(utterance) { buffer in
                guard !finished, let pcm = buffer as? AVAudioPCMBuffer else { return }
                let now = CFAbsoluteTimeGetCurrent()
                if pcm.frameLength == 0 {
                    finished = true
                    done.resume(returning: SynthSample(
                        firstBufferMs: ((first ?? now) - t0) * 1000, leadingSilenceMs: silentFrames / rate * 1000,
                        audibleMs: ((first ?? now) - t0) * 1000 + silentFrames / rate * 1000,
                        synthesisMs: (now - t0) * 1000, audioMs: frames / rate * 1000))
                    return
                }
                rate = pcm.format.sampleRate
                if first == nil { first = now }
                keep?(pcm)
                let n = Int(pcm.frameLength)
                if !heard {
                    var quiet = 0
                    if let f = pcm.floatChannelData?[0] {
                        while quiet < n && abs(f[quiet]) < 0.01 { quiet += 1 }
                    } else if let i = pcm.int16ChannelData?[0] {
                        while quiet < n && abs(Int(i[quiet])) < 328 { quiet += 1 }
                    }
                    silentFrames += Double(quiet)
                    heard = quiet < n
                }
                frames += Double(n)
            }
        }
    }

    /// The system's own playback path: speak() to didStart, as the app would use it.
    @MainActor
    public static func speak(_ text: String, voice: AVSpeechSynthesisVoice?) async -> SpeakSample {
        let probe = SpeakProbe()
        return await probe.run(text, voice: voice)
    }
}

@MainActor
final class SpeakProbe: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var t0 = 0.0
    private var started = 0.0
    private var done: CheckedContinuation<SpeakSample, Never>?

    func run(_ text: String, voice: AVSpeechSynthesisVoice?) async -> SpeakSample {
        synth.delegate = self
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        return await withCheckedContinuation { c in
            done = c
            t0 = CFAbsoluteTimeGetCurrent()
            synth.speak(u)
        }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        let now = CFAbsoluteTimeGetCurrent()
        MainActor.assumeIsolated { started = now }
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        let now = CFAbsoluteTimeGetCurrent()
        MainActor.assumeIsolated {
            done?.resume(returning: SpeakSample(didStartMs: (started - t0) * 1000, didFinishMs: (now - t0) * 1000))
            done = nil
        }
    }
}
