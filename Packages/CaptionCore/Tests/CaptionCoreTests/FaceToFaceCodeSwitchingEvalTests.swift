@testable import CaptionCore
import Foundation
import XCTest

/// #208 item 4: the matching numbers compared on the same recorded conversations, for accuracy. Opt-in (needs the
/// Bangor Miami corpus as JSON, from scripts/codeswitch-eval/miami_to_json.py):
///
///     CAPTION_CODESWITCH_JSON=/path/miami.json CAPTION_CODESWITCH_OUT=/path/results.json \
///       swift test -c release --filter FaceToFaceCodeSwitchingEval
///
/// Each speaker is a voice; their real transcribed words go through the real `SpeakerLanguages` and Apple's
/// NaturalLanguage (English vs Spanish), a few words at a time as an engine reports them, then finished. Stand-ins:
/// the words are the corpus's human transcript (no engine errors), and the diarizer is perfect except where a
/// scenario breaks it on purpose. Results: docs/perf/face-to-face-code-switching.md.
final class FaceToFaceCodeSwitchingEvalTests: XCTestCase {
    struct Utterance: Decodable { let speaker: String; let start: Double; let end: Double; let words: [[String]] }
    struct Conversation: Decodable { let name: String; let utterances: [Utterance] }

    /// What one policy did in one scenario.
    struct Score: Encodable {
        var voices = 0
        var lines = 0
        /// Lines said while the voice sat on the wrong half (its lines all show on its current half).
        var wrongLines = 0
        /// Lines said before the voice had any half.
        var unplacedLines = 0
        /// Lines heard by both engines (matching or checking): the battery cost.
        var bothEngineLines = 0
        var firstLockRight = 0
        var linesToFirstLock: [Int] = []
        /// Moves away from the voice's language, and moves back to it.
        var wrongMoves = 0
        var rightMoves = 0
        /// Voices whose half moved more than once (a bilingual being bounced).
        var bouncedVoices = 0
        /// Lines after a break (mislabelled start, swapped slot) until the voice is on its new right half; nil: never.
        var linesToFollow: [Int?] = []
        /// The same in seconds of conversation, from the break to the line that's on the right half.
        var secondsToFollow: [Double?] = []
    }

    struct Run: Encodable {
        let name: String
        let lock: String
        let correction: String
        let natural: Score
        let bilinguals: Score
        let mislabelledStart: Score
        let swappedSlot: Score
        let swappedLate: Score
    }

    private let pair = LanguagePair(owner: Locale(identifier: "en-US"), partner: Locale(identifier: "es-ES"))
    private var cache: [String: [FaceToFaceHalf: Double]] = [:]

    private func classify(_ text: String) -> [FaceToFaceHalf: Double] {
        if let hit = cache[text] { return hit }
        let p = pair.probabilities(text)
        cache[text] = p
        return p
    }

    /// One voice's lines, its language per line (nil: no truth for that line), in time order.
    struct Voice { let id: Int; var lines: [(start: Double, end: Double, words: [String], truth: FaceToFaceHalf?)] }

    private static func half(_ lang: String) -> FaceToFaceHalf? { lang == "en" ? .owner : lang == "es" ? .partner : nil }

    /// Plays the voices' lines in time order through one `SpeakerLanguages` and scores them.
    private func play(_ voices: [Voice], policy: LanguageMatchPolicy, score: inout Score, breakAt: [Int: Double] = [:]) {
        var l = SpeakerLanguages(policy: policy)
        var events: [(voice: Int, index: Int)] = []
        for v in voices { for i in v.lines.indices { events.append((v.id, i)) } }
        let byId = Dictionary(uniqueKeysWithValues: voices.map { ($0.id, $0) })
        events.sort { byId[$0.voice]!.lines[$0.index].start < byId[$1.voice]!.lines[$1.index].start }
        var lastHalf: [Int: FaceToFaceHalf] = [:]
        var moves: [Int: Int] = [:]
        var firstLock: Set<Int> = []
        var heardLines: [Int: Int] = [:]
        var waitingSince: [Int: Int] = [:]
        for (id, i) in events {
            let line = byId[id]!.lines[i]
            let n = line.words.count
            let step = (line.end - line.start) / Double(max(n, 1))
            let timed = line.words.enumerated().map { k, w in
                TimedWord(text: w, start: line.start + Double(k) * step, end: line.start + Double(k + 1) * step)
            }
            if l.lanes(for: id).count == 2 { score.bothEngineLines += 1 }
            // A few words at a time as engines report them, then the finished line. Both engines hear a voice with
            // no language (or being checked); a locked voice only its own.
            // A Set's order changes from run to run: feed the engines in a fixed order, the caption language's first.
            func lanes() -> [FaceToFaceHalf] { l.lanes(for: id).sorted { $0 == .partner && $1 == .owner } }
            var cut = 3
            while cut < n {
                for lane in lanes() { l.heard(speaker: id, lane: lane, words: Array(timed.prefix(cut)), isFinal: false, classify: classify) }
                cut += 3
            }
            for lane in lanes() { l.heard(speaker: id, lane: lane, words: timed, isFinal: true, classify: classify) }
            heardLines[id, default: 0] += 1

            let now = l.sides.half(ofSpeaker: id)
            if let now, !firstLock.contains(id) {
                firstLock.insert(id)
                if now == line.truth { score.firstLockRight += 1 }
                else if ProcessInfo.processInfo.environment["CAPTION_CODESWITCH_DEBUG"] != nil {
                    let said = byId[id]!.lines.prefix(i + 1).suffix(3).map { $0.words.joined(separator: " ") }
                    print("WRONG FIRST LOCK voice \(id) truth \(String(describing: line.truth)) -> \(now): \(said) \(said.map { classify($0) })")
                }
                score.linesToFirstLock.append(heardLines[id]!)
            }
            if let before = lastHalf[id], let now, before != now {
                moves[id, default: 0] += 1
                if now == line.truth { score.rightMoves += 1 } else if line.truth != nil { score.wrongMoves += 1 }
            }
            if let now { lastHalf[id] = now }
            guard let truth = line.truth else { continue }
            score.lines += 1
            if now == nil { score.unplacedLines += 1 } else if now != truth { score.wrongLines += 1 }
            // Following a break: count lines from the break until the voice is on the new right half.
            if let at = breakAt[id], line.start >= at {
                if waitingSince[id] == nil { waitingSince[id] = 0 }
                if waitingSince[id]! >= 0 {
                    waitingSince[id]! += 1
                    if now == truth {
                        score.linesToFollow.append(waitingSince[id]!)
                        score.secondsToFollow.append(line.end - at)
                        waitingSince[id] = -1
                    }
                }
            }
        }
        for (_, since) in waitingSince where since >= 0 { score.linesToFollow.append(nil); score.secondsToFollow.append(nil) }
        score.voices += voices.count
        score.bouncedVoices += moves.values.filter { $0 > 1 }.count
    }

    private struct Speaker { let conversation: String; let code: String; let main: FaceToFaceHalf; let share: Double; let lines: [Utterance] }

    func testCompareThresholdsOnRecordedCodeSwitching() throws {
        guard let path = ProcessInfo.processInfo.environment["CAPTION_CODESWITCH_JSON"] else {
            throw XCTSkip("set CAPTION_CODESWITCH_JSON to the Miami corpus JSON (scripts/codeswitch-eval)")
        }
        let conversations = try JSONDecoder().decode([Conversation].self, from: Data(contentsOf: URL(fileURLWithPath: path)))

        // Each speaker's language: the majority of their tagged words over the whole conversation.
        var speakers: [Speaker] = []
        for c in conversations {
            for (code, us) in Dictionary(grouping: c.utterances, by: \.speaker) {
                let tags = us.flatMap { $0.words.map { $0[1] } }
                let en = tags.filter { $0 == "en" }.count, es = tags.filter { $0 == "es" }.count
                guard en + es >= 40 else { continue }
                speakers.append(Speaker(conversation: c.name, code: code, main: en >= es ? .owner : .partner,
                                        share: Double(max(en, es)) / Double(en + es), lines: us.sorted { $0.start < $1.start }))
            }
        }
        speakers.sort { ($0.conversation, $0.code) < ($1.conversation, $1.code) }   // the same picks every run
        let dominant = speakers.filter { $0.share >= 0.7 }
        let bilingual = speakers.filter { $0.share < 0.7 }
        // Lines that are clearly one language (4+ words, 90%+ tagged so): what a mislabelled or swapped voice says.
        func clear(_ s: [Speaker], _ half: FaceToFaceHalf) -> [Utterance] {
            s.filter { $0.main == half }.flatMap(\.lines).filter { u in
                let tags = u.words.map { $0[1] }
                return tags.count >= 4 && Double(tags.filter { Self.half($0) == half }.count) / Double(tags.count) >= 0.9
            }
        }
        let pool: [FaceToFaceHalf: [Utterance]] = [.owner: clear(dominant, .owner), .partner: clear(dominant, .partner)]
        print("speakers \(speakers.count): dominant \(dominant.count) (es \(dominant.filter { $0.main == .partner }.count)), bilingual \(bilingual.count); pool en \(pool[.owner]!.count) es \(pool[.partner]!.count)")

        func voice(_ id: Int, _ us: [Utterance], truth: FaceToFaceHalf) -> Voice {
            Voice(id: id, lines: us.map { u in (u.start, u.end, u.words.map { $0[0] }, truth) })
        }

        func evaluate(_ name: String, lock: (Int, Double), correction: LanguageMatchPolicy.Correction) -> Run {
            var policy = LanguageMatchPolicy()
            policy.minWords = lock.0
            policy.lockProbability = lock.1
            policy.correction = correction
            var natural = Score(), bilinguals = Score(), mislabelled = Score(), swapped = Score(), swappedLate = Score()
            // Natural: each conversation as recorded, every speaker a voice. Truth: the speaker's main language.
            for c in conversations {
                let mine = speakers.filter { $0.conversation == c.name }
                let dom = mine.filter { $0.share >= 0.7 }, bil = mine.filter { $0.share < 0.7 }
                if !dom.isEmpty { play(dom.enumerated().map { voice($0, $1.lines, truth: $1.main) }, policy: policy, score: &natural) }
                if !bil.isEmpty { play(bil.enumerated().map { voice($0, $1.lines, truth: $1.main) }, policy: policy, score: &bilinguals) }
            }
            for (k, s) in dominant.enumerated() {
                let other = pool[s.main.other]!
                guard !other.isEmpty else { continue }
                // Mislabelled start (#199's measured limit): the other person's first two lines land under this voice.
                let first = s.lines[0].start
                let stolen = (0..<2).map { j -> (Double, Double, [String], FaceToFaceHalf?) in
                    let u = other[(k * 2 + j) % other.count]
                    let len = u.end - u.start
                    return (first - Double(2 - j) * (len + 0.5), first - Double(2 - j) * (len + 0.5) + len, u.words.map { $0[0] }, nil)
                }
                var v = voice(0, s.lines, truth: s.main)
                v.lines = stolen + v.lines
                play([v], policy: policy, score: &mislabelled, breakAt: [0: first])
                // Swapped slot: from `after` seconds on this voice is really the other person (the other language).
                // At 3 minutes, and at 10, when a long-known voice's confidence has had time to reach its cap.
                func swap(after: Double, lines: Int, into score: inout Score) {
                    let at = first + after
                    guard s.lines.contains(where: { $0.start >= at }) else { return }
                    var v = voice(0, s.lines.filter { $0.start < at }, truth: s.main)
                    var t = at
                    for j in 0..<lines {
                        let u = other[(k * 7 + j) % other.count]
                        let len = u.end - u.start
                        v.lines.append((t, t + len, u.words.map { $0[0] }, s.main.other))
                        t += len + 1
                    }
                    play([v], policy: policy, score: &score, breakAt: [0: at])
                }
                swap(after: 180, lines: 40, into: &swapped)
                swap(after: 600, lines: 80, into: &swappedLate)
            }
            return Run(name: name, lock: "\(lock.0)+ words, \(Int(lock.1 * 100))%", correction: "\(correction)",
                       natural: natural, bilinguals: bilinguals, mislabelledStart: mislabelled, swappedSlot: swapped,
                       swappedLate: swappedLate)
        }

        let base = (4, 0.95)
        var runs: [Run] = []
        for (name, lock) in [("lock 3/90", (3, 0.90)), ("lock 4/95", base), ("lock 4/99", (4, 0.99)),
                             ("lock 6/99", (6, 0.99)), ("lock 8/95", (8, 0.95))] {
            runs.append(evaluate(name, lock: lock, correction: .confidence(cap: 8, moveBelow: 2)))
        }
        for (name, c) in [("streak 1", LanguageMatchPolicy.Correction.streak(1)), ("streak 2 (#199)", .streak(2)),
                          ("streak 3", .streak(3)), ("confidence cap 4", .confidence(cap: 4, moveBelow: 2)),
                          ("confidence cap 12", .confidence(cap: 12, moveBelow: 2)),
                          ("confidence cap 20", .confidence(cap: 20, moveBelow: 2)),
                          ("confidence cap 8, move at -3", .confidence(cap: 8, moveBelow: 3))] {
            runs.append(evaluate(name, lock: base, correction: c))
        }
        // Each lock with the stickier caps: the two interact.
        for lock in [(4, 0.95), (4, 0.99), (6, 0.99)] {
            for cap in [8, 12, 16, 20, 30, 40] where !(lock == base && [8, 12, 20].contains(cap)) {
                runs.append(evaluate("lock \(lock.0)/\(Int(lock.1 * 100)), cap \(cap)", lock: lock, correction: .confidence(cap: cap, moveBelow: 2)))
            }
        }
        if let out = ProcessInfo.processInfo.environment["CAPTION_CODESWITCH_OUT"] {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(runs).write(to: URL(fileURLWithPath: out))
        }
    }
}
