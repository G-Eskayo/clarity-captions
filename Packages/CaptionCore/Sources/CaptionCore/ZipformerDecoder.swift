import CoreML
import Foundation

/// The three networks of the Hebrew zipformer (#220), behind a protocol so the streaming logic is tested with fakes.
protocol ZipformerNetwork: AnyObject {
    /// One window of `ZipformerStream.window` fbank frames (row-major, 80 per frame) → `outFrames` encoder frames
    /// (row-major, `dim` each). Carries its own streaming state from call to call.
    func encode(_ frames: [Float]) throws -> [Float]
    /// The last two tokens (-1 for none) → decoder output (`dim`).
    func decode(_ context: [Int32]) throws -> [Float]
    /// One encoder frame and the decoder output → a logit per token.
    func join(_ encoderFrame: ArraySlice<Float>, _ decoderOut: [Float]) throws -> [Float]
    var dim: Int { get }
}

/// Streaming greedy search over the zipformer (#220), as sherpa-onnx and the Python scoring path do it: fbank frames
/// in, 141-frame windows 128 frames apart through the encoder, then per encoder frame one joiner call, at most one
/// token per frame. Each encoder frame is 40 ms of session time. O(frames) per audio; memory one window.
struct ZipformerStream {
    static let window = 141
    static let shift = 128
    static let outFrames = 32
    static let frameSeconds = 0.04
    static let blank = 0

    private var pending: [[Float]] = []
    private var chunk = 0
    private var context: [Int32] = [-1, Int32(blank)]
    private var decoderOut: [Float]?

    /// Feeds fbank frames; returns every token decided, with its encoder frame (25 Hz, from the stream start).
    mutating func accept(_ frames: [[Float]], network: ZipformerNetwork) throws -> [(token: Int, frame: Int)] {
        pending += frames
        var out: [(Int, Int)] = []
        if decoderOut == nil { decoderOut = try network.decode(context) }
        while pending.count >= Self.window {
            let enc = try network.encode(Array(pending[0..<Self.window].joined()))
            pending.removeFirst(Self.shift)
            let d = network.dim
            guard enc.count == Self.outFrames * d else { throw ZipformerError.badEncoderOutput(enc.count) }
            for t in 0..<Self.outFrames {
                let logits = try network.join(enc[(t * d)..<((t + 1) * d)], decoderOut!)
                guard let k = logits.indices.max(by: { logits[$0] < logits[$1] }) else { continue }
                if k != Self.blank {
                    out.append((k, chunk * Self.outFrames + t))
                    context = [context[1], Int32(k)]
                    decoderOut = try network.decode(context)
                }
            }
            chunk += 1
        }
        return out
    }

    /// Seconds of audio the encoder has finished with.
    var decodedSeconds: Double { Double(chunk * Self.outFrames) * Self.frameSeconds }
}

/// SentencePiece pieces with encoder-frame times → words (#220): a piece starting with "▁" starts a word. A word is
/// final once the next one has started, or once `settleAfter` seconds of decoded audio have passed with no new token
/// (a pause); the last word stays volatile until then.
struct ZipformerWords {
    let table: [Int: String]
    var settleAfter = 0.8
    private var open: [(text: String, start: Double, end: Double)] = []

    init(table: [Int: String]) { self.table = table }

    /// tokens.txt: "<piece> <id>" per line.
    static func table(from text: String) -> [Int: String] {
        var t: [Int: String] = [:]
        for line in text.split(separator: "\n") {
            guard let space = line.lastIndex(of: " "), let id = Int(line[line.index(after: space)...]) else { continue }
            t[id] = String(line[..<space])
        }
        return t
    }

    /// Adds tokens; returns the words that became final and the volatile tail (possibly empty).
    mutating func add(_ tokens: [(token: Int, frame: Int)], decodedSeconds: Double) -> (final: [TimedWord], volatile: [TimedWord]) {
        var final: [TimedWord] = []
        for (token, frame) in tokens {
            guard let piece = table[token], !piece.hasPrefix("<") else { continue }
            let start = Double(frame) * ZipformerStream.frameSeconds
            let end = start + ZipformerStream.frameSeconds
            if piece.hasPrefix("\u{2581}") || open.isEmpty {
                final += open.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
                open = [(String(piece.drop(while: { $0 == "\u{2581}" })), start, end)]
            } else {
                open[open.count - 1].text += piece
                open[open.count - 1].end = end
            }
        }
        open.removeAll { $0.text.isEmpty }
        if let last = open.last, decodedSeconds - last.end >= settleAfter {
            final += open.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
            open = []
        }
        return (final, open.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) })
    }

    /// Everything open becomes final (finish, settle).
    mutating func flush() -> [TimedWord] {
        defer { open = [] }
        return open.map { TimedWord(text: $0.text, start: $0.start, end: $0.end) }
    }
}

enum ZipformerError: Error, Equatable {
    case badEncoderOutput(Int)
    case missingPart(String)
}

/// The Core ML build: Encoder, Decoder and Joiner (compiled .mlmodelc in the app, or .mlpackage, compiled on load)
/// plus tokens.txt in one folder. CPU and GPU only: the ANE compiler rejects this encoder after minutes of trying
/// (docs/perf/hebrew-coreml-design.md), so asking for it would only delay the first Start.
final class CoreMLZipformer: ZipformerNetwork {
    let dim = 512
    let tokens: [Int: String]
    private let encoder: MLModel
    private let decoder: MLModel
    private let joiner: MLModel
    private var states: [String: MLMultiArray] = [:]
    private let stateNames: [String]

    init(folder: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndGPU
        func load(_ name: String) throws -> MLModel {
            let compiled = folder.appendingPathComponent("\(name).mlmodelc")
            if FileManager.default.fileExists(atPath: compiled.path) { return try MLModel(contentsOf: compiled, configuration: config) }
            let package = folder.appendingPathComponent("\(name).mlpackage")
            guard FileManager.default.fileExists(atPath: package.path) else { throw ZipformerError.missingPart(name) }
            return try MLModel(contentsOf: try MLModel.compileModel(at: package), configuration: config)
        }
        encoder = try load("Encoder")
        decoder = try load("Decoder")
        joiner = try load("Joiner")
        let tokenURL = folder.appendingPathComponent("tokens.txt")
        guard let text = try? String(contentsOf: tokenURL, encoding: .utf8) else { throw ZipformerError.missingPart("tokens.txt") }
        tokens = ZipformerWords.table(from: text)
        stateNames = encoder.modelDescription.inputDescriptionsByName.keys.filter { $0 != "x" }.sorted()
        try reset()
    }

    /// Fresh streaming state: zeros, as at the start of a session.
    func reset() throws {
        var s: [String: MLMultiArray] = [:]
        for name in stateNames {
            guard let c = encoder.modelDescription.inputDescriptionsByName[name]?.multiArrayConstraint else { continue }
            let a = try MLMultiArray(shape: c.shape, dataType: c.dataType)
            for i in 0..<a.count { a[i] = 0 }
            s[name] = a
        }
        states = s
    }

    func encode(_ frames: [Float]) throws -> [Float] {
        let x = try MLMultiArray(shape: [1, NSNumber(value: ZipformerStream.window), 80], dataType: .float32)
        frames.withUnsafeBufferPointer { src in
            x.withUnsafeMutableBytes { dst, _ in dst.copyMemory(from: UnsafeRawBufferPointer(src)) }
        }
        var inputs: [String: MLFeatureValue] = ["x": MLFeatureValue(multiArray: x)]
        for (k, v) in states { inputs[k] = MLFeatureValue(multiArray: v) }
        let out = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: inputs))
        for k in stateNames { if let v = out.featureValue(for: "new_" + k)?.multiArrayValue { states[k] = v } }
        guard let enc = out.featureValue(for: "encoder_out")?.multiArrayValue else { throw ZipformerError.missingPart("encoder_out") }
        return Self.floats(enc)
    }

    func decode(_ context: [Int32]) throws -> [Float] {
        let y = try MLMultiArray(shape: [1, 2], dataType: .int32)
        y[0] = NSNumber(value: context[0]); y[1] = NSNumber(value: context[1])
        let out = try decoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["y": MLFeatureValue(multiArray: y)]))
        guard let d = out.featureValue(for: "decoder_out")?.multiArrayValue else { throw ZipformerError.missingPart("decoder_out") }
        return Self.floats(d)
    }

    func join(_ encoderFrame: ArraySlice<Float>, _ decoderOut: [Float]) throws -> [Float] {
        let e = try MLMultiArray(shape: [1, 512], dataType: .float32)
        let d = try MLMultiArray(shape: [1, 512], dataType: .float32)
        for (i, v) in encoderFrame.enumerated() { e[i] = NSNumber(value: v) }
        for (i, v) in decoderOut.enumerated() { d[i] = NSNumber(value: v) }
        let out = try joiner.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "encoder_out": MLFeatureValue(multiArray: e), "decoder_out": MLFeatureValue(multiArray: d)]))
        guard let l = out.featureValue(for: "logit")?.multiArrayValue else { throw ZipformerError.missingPart("logit") }
        return Self.floats(l)
    }

    /// Any float array (fp16 or fp32 output) as [Float], in logical order.
    private static func floats(_ a: MLMultiArray) -> [Float] {
        if a.dataType == .float32, a.strides.last == 1 {
            return a.withUnsafeBufferPointer(ofType: Float.self) { Array($0.prefix(a.count)) }
        }
        return (0..<a.count).map { a[$0].floatValue }
    }
}
