@preconcurrency import AVFoundation
import Foundation

/// Plays a buffer through the default output while recording the default input, on one AVAudioEngine. With voice
/// processing on, Apple's echo canceller removes the engine's own playback from the mic, which is how the app would
/// keep its spoken translation out of the captions when it plays through the phone's speaker (#233).
public enum Acoustic {
    public struct Take { public let recording: AVAudioPCMBuffer; public let voiceProcessing: Bool; public let error: String? }

    public static func playAndRecord(_ play: AVAudioPCMBuffer, voiceProcessing: Bool, tail: Double = 1.5) async -> Take {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        var vpError: String?
        if voiceProcessing {
            do { try input.setVoiceProcessingEnabled(true) } catch { vpError = "\(error)" }
        }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: play.format)
        let inFormat = input.outputFormat(forBus: 0)
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inFormat.sampleRate, channels: 1,
                                 interleaved: false)!
        let seconds = Double(play.frameLength) / play.format.sampleRate + tail + 0.5
        let rec = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(seconds * inFormat.sampleRate + 8192))!
        let lock = NSLock()
        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { b, _ in
            lock.lock(); defer { lock.unlock() }
            let n = min(Int(b.frameLength), Int(rec.frameCapacity - rec.frameLength))
            guard n > 0, let src = b.floatChannelData?[0] else { return }
            memcpy(rec.floatChannelData![0] + Int(rec.frameLength), src, n * 4)
            rec.frameLength += AVAudioFrameCount(n)
        }
        do { try engine.start() } catch {
            return Take(recording: rec, voiceProcessing: voiceProcessing, error: "engine start: \(error)")
        }
        try? await Task.sleep(for: .milliseconds(500))
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            player.scheduleBuffer(play, at: nil, options: [], completionCallbackType: .dataPlayedBack) { _ in c.resume() }
            player.play()
        }
        try? await Task.sleep(for: .seconds(tail))
        engine.stop()
        input.removeTap(onBus: 0)
        return Take(recording: rec, voiceProcessing: voiceProcessing, error: vpError)
    }
}
