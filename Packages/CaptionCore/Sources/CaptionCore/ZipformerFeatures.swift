import Accelerate
import Foundation

/// The Hebrew engine's front end (#220): 80-bin Kaldi fbank exactly as icefall trained the zipformer (lhotse's
/// defaults, which sherpa-onnx and the Python scoring path use too): 25 ms Povey windows every 10 ms, DC removed,
/// pre-emphasis 0.97, a 512-point power spectrum, 80 mel bins from 20 Hz to 7,600 Hz, natural log floored at float
/// epsilon, no dither. Samples are 16 kHz in [-1, 1].
///
/// Streaming: like Kaldi with snip_edges off, the first window is centred on sample 80, the 120 samples before the
/// stream are its first samples mirrored, and each later frame is emitted as soon as its whole window has arrived.
/// Memory is bounded by one window; each frame costs one 400 × 514 matrix product (about 0.2 M multiply-adds).
struct ZipformerFeatures {
    static let rate = 16_000
    static let window = 400
    static let shift = 160
    static let bins = 80
    private static let fft = 512
    private static let lead = window / 2 - shift / 2  // 120 mirrored samples before the stream

    /// Samples not yet fully consumed, starting at stream position `bufferStart` (negative while the mirror is in).
    private var buffer: [Float] = []
    private var bufferStart = 0
    private var started = false
    private var nextFrame = 0

    var bufferedSamples: Int { buffer.count }

    mutating func append(_ samples: [Float]) {
        if !started {
            buffer.append(contentsOf: samples)
            guard buffer.count >= Self.lead else { return }
            // Kaldi's reflection: x[119], ..., x[0], then the stream.
            buffer = Array(buffer[0..<Self.lead].reversed()) + buffer
            bufferStart = -Self.lead
            started = true
        } else {
            buffer.append(contentsOf: samples)
        }
    }

    /// Every frame whose window is complete, each `bins` log mel energies, in order, once.
    mutating func takeFrames() -> [[Float]] {
        guard started else { return [] }
        var out: [[Float]] = []
        while true {
            let first = nextFrame * Self.shift - Self.lead - bufferStart
            guard first + Self.window <= buffer.count else { break }
            out.append(Self.frame(Array(buffer[first..<first + Self.window])))
            nextFrame += 1
        }
        let keepFrom = nextFrame * Self.shift - Self.lead - bufferStart
        if keepFrom > 0 {
            buffer.removeFirst(min(keepFrom, buffer.count))
            bufferStart += keepFrom
        }
        return out
    }

    // MARK: one frame

    private static func frame(_ raw: [Float]) -> [Float] {
        var x = raw
        let mean = vDSP.mean(x)
        vDSP.add(-mean, x, result: &x)
        // Pre-emphasis, Kaldi style: the first sample is its own predecessor.
        var y = [Float](repeating: 0, count: window)
        y[0] = x[0] - 0.97 * x[0]
        for i in 1..<window { y[i] = x[i] - 0.97 * x[i - 1] }
        vDSP.multiply(y, povey, result: &y)
        // Real and imaginary parts of the 257 bins of a 512-point DFT (the window zero-padded), as one product.
        var spectrum = [Float](repeating: 0, count: 2 * (fft / 2 + 1))
        y.withUnsafeBufferPointer { yp in
            basis.withUnsafeBufferPointer { bp in
                spectrum.withUnsafeMutableBufferPointer { sp in
                    vDSP_mmul(yp.baseAddress!, 1, bp.baseAddress!, 1, sp.baseAddress!, 1, 1, vDSP_Length(2 * (fft / 2 + 1)),
                              vDSP_Length(window))
                }
            }
        }
        let n = fft / 2 + 1
        var power = [Float](repeating: 0, count: n)
        for k in 0..<n { power[k] = spectrum[k] * spectrum[k] + spectrum[n + k] * spectrum[n + k] }
        var mel = [Float](repeating: 0, count: bins)
        power.withUnsafeBufferPointer { pp in
            melBanks.withUnsafeBufferPointer { mp in
                mel.withUnsafeMutableBufferPointer { op in
                    vDSP_mmul(pp.baseAddress!, 1, mp.baseAddress!, 1, op.baseAddress!, 1, 1, vDSP_Length(bins), vDSP_Length(n))
                }
            }
        }
        return mel.map { log(max($0, Float.ulpOfOne)) }
    }

    /// Hann (symmetric) to the power 0.85.
    private static let povey: [Float] = (0..<window).map {
        Float(pow(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(window - 1)), 0.85))
    }

    /// window × (cos for bins 0…256, then −sin for bins 0…256), row-major.
    private static let basis: [Float] = {
        let n = fft / 2 + 1
        var b = [Float](repeating: 0, count: window * 2 * n)
        for t in 0..<window {
            for k in 0..<n {
                let a = 2 * Double.pi * Double(k * t % fft) / Double(fft)
                b[t * 2 * n + k] = Float(cos(a))
                b[t * 2 * n + n + k] = Float(-sin(a))
            }
        }
        return b
    }()

    /// 257 × 80 triangular filters on Kaldi's mel scale (1127 ln(1 + f/700)), row-major; the Nyquist row is zero.
    private static let melBanks: [Float] = {
        let n = fft / 2 + 1
        func mel(_ f: Double) -> Double { 1127 * log(1 + f / 700) }
        let lo = mel(20), hi = mel(Double(rate) / 2 - 400)
        let delta = (hi - lo) / Double(bins + 1)
        var m = [Float](repeating: 0, count: n * bins)
        for b in 0..<bins {
            let left = lo + Double(b) * delta, centre = left + delta, right = centre + delta
            for k in 0..<(fft / 2) {
                let f = mel(Double(rate) / Double(fft) * Double(k))
                let w = max(0, min((f - left) / (centre - left), (right - f) / (right - centre)))
                m[k * bins + b] = Float(w)
            }
        }
        return m
    }()
}
