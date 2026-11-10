## North-star fit

**Reuses:** `SpeakerLabelSmoother.chooseSlot` (`Packages/CaptionCore/Sources/CaptionCore/SpeakerLabelSmoother.swift:51-73`) and `SpeakerAligner.speaker` (`Packages/CaptionCore/Sources/CaptionCore/SpeakerAligner.swift:20-30`) both already build an `[Int: Double]` overlap dictionary the same way; rather than writing two separate tie-break implementations, both will call one new internal helper (`SpeakerAligner.bestSlot(_:current:numbering:)`), added next to the existing `speaker` function it's reused by. No new file, no new type — composability over duplication.

**Simplest sufficient approach:** `SpeakerAligner.speaker` is explicitly documented as "Pure logic -- no FluidAudio, no audio" and none of its three call sites (`FaceToFace.swift:131`, `FaceToFaceEngine.swift:206`, `SpeakerPathReplay.swift:80`) thread a "current" or "numbering" context into it today. Extending its public signature to accept those would be scope creep for a bug that's really about removing a dependency on Dictionary iteration order, not about giving the aligner new state it doesn't have callers for. So `bestSlot` takes `current`/`numbering` as defaulted optional params (`nil` / `[:]`); `SpeakerAligner.speaker` calls it with the defaults (collapsing to tier 3, lowest index — its whole fix), and `SpeakerLabelSmoother.chooseSlot` calls it with its real `current` and `displayBySlot` (all three tiers). This is a judgment call I'm confident in, not something that needs the owner's input: it fixes exactly the bug described ("no tie-break at all") without inventing unused plumbing.

**Where it spends/saves:** the fix replaces `Dictionary.max(by:)` (which was already O(n) and already order-independent except at exact ties) with: find max value (O(k)), filter tied keys (O(k)), check `current` then `numbering` then `.min()` (O(k)) — k is the distinct-speaker count, ADR-capped at 4. Same asymptotic time (O(n + k) ≈ O(n)) and space (O(k)) as today; no measurable cost.

**User impact:** directly serves "labels the person reading can trust" — the same recording stops renumbering two people mid-session depending on process luck, which is what #271 step 2 needs to compare builds without arguing around noise. No UI, no network, no new dependency; purely internal determinism.

## Tests to write first

All in `Packages/CaptionCore/Tests/CaptionCoreTests/SpeakerLabelSmootherTests.swift` and `SpeakerAlignerTests.swift`, run via `swift test --package-path Packages/CaptionCore`.

From the ticket's suggested-fix test description, built from both insertion orders (this is the realistic proxy for "random dictionary order" inside a single `swift test` process, since the seed is fixed per process and can't be varied from inside one test target run):

1. **Two-way tie, neither slot is current, neither numbered** → lowest slot index wins, same answer whether segments are given `[A, B]` or `[B, A]`. (This is the exact bug: today this depends on luck.)
2. **Two-way tie, one slot is `current`** → `current` wins, both insertion orders. (Must still pass — this already worked before the fix, by accident of the old predicate; must not regress.)
3. **Two-way tie, neither is `current`, exactly one already has a display number** → the numbered slot wins, both insertion orders.
4. **Two-way tie, both already have display numbers** → the *lower* display number wins even when its raw slot index is higher (e.g. raw slot 5 → display 0, raw slot 2 → display 1: slot 5 wins), both insertion orders.
5. **Three-way tie, no current, none numbered** → lowest raw index wins, tested across all 6 permutations of segment order.
6. **`SpeakerAligner.speaker` two-way tie** (no current/numbering available to it at all) → lowest raw index wins, both insertion orders.
7. **`SpeakerAligner.speaker` three-way tie** → lowest raw index wins, across permutations.
8. **Zero-length caption range at a tie boundary** → confirms the existing `end <= start` fallback path (unchanged) still wins over the new tie logic, i.e. a tie among `covering` segments never reaches the fallback.
9. **Tie inside a live (non-final) in-progress utterance**, combined with the existing `switchSeconds`/`sameUtterance` hold logic — confirms the tie-break and the live-hold rule compose correctly (a tie must still resolve via tiers 1–3 before the hold logic ever sees it, since the hold logic only runs once a `bestKey` already exists).
10. **Full existing suite as a regression check** — every already-passing test in both files and the non-integration parts of `SpeakerStabilityReplayTests.swift` must still pass unchanged, proving all non-tied cases are untouched.

Not applicable, stated rather than silently skipped: both types are pure value-type logic with no I/O, no permissions, no shared mutable state of their own (`SpeakerLabelSmoother` is a `struct`; the one place its output crosses a concurrency boundary, `FaceToFaceEngine.numbering`, is already guarded by `lock.withLock` and this change doesn't touch that), so "each dependency failing", "wrong permissions", "concurrency", and "a person's mistakes" don't apply here the way they would to I/O-touching code.

**Untested by this plan:** the ticket's own closing step — "rerun the #271 baseline once and confirm 0 repeats differ" — needs the real Sortformer model over the AMI/CHiME-6 corpora on the Mac mini (`CAPTION_INTEGRATION=1`), which this run can't execute. I'll leave that as a follow-up for whoever runs the next #271 step-2 pass, not part of this task list.

## Task List

1. Add `SpeakerAligner.bestSlot(_ overlap: [Int: Double], current: Int? = nil, numbering: [Int: Int] = [:]) -> Int?` in `SpeakerAligner.swift`: max value via `overlap.values.max()`, tied keys via equality filter, then `current` → lowest-numbered tied key → `tied.min()`.
2. Write tests 6–7 (`SpeakerAlignerTests.swift`) against the still-unchanged `speaker(start:end:segments:)` signature.
3. Change `SpeakerAligner.speaker` to resolve its tie via `bestSlot(overlap)` (defaults only) instead of `overlap.max(by:)`; keep the existing zero-length-range fallback as-is.
4. Write tests 1–5, 8–9 (`SpeakerLabelSmootherTests.swift`) against the still-unchanged `label`/`chooseSlot` behavior.
5. In `SpeakerLabelSmoother.chooseSlot`, replace the `overlap.max(by:)` call with `SpeakerAligner.bestSlot(overlap, current: current, numbering: displayBySlot)`, then look up `overlap[bestKey]` for the value previously read off `best.value`; update the two remaining `best.key` references to `bestKey`.
6. Update the doc comments at the top of both files to note the deterministic tie order (current → lowest display number → lowest slot index) and reference #275, matching the existing "measured" comment style.
7. Run `swift test --package-path Packages/CaptionCore`; confirm every new test and the full existing suite (including `SpeakerStabilityReplayTests.swift`'s non-integration parts) pass.
8. In the PR description, state plainly that the #271 real-audio repeat-run verification is not re-run here (no model/corpora access in this environment) and is a follow-up.