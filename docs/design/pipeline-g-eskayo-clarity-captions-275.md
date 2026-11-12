## North-star fit

**Reuses:** the existing `chooseSlot`/`speaker` overlap-accumulation code in `SpeakerLabelSmoother.swift` and `SpeakerAligner.swift` (`Packages/CaptionCore/Sources/CaptionCore/`) — same `[Int: Double]` overlap map, same filtering logic. The only change is *how the max is selected*, not how overlap is computed. No new file, no new type beyond one small static helper per file.

**Simplest sufficient approach:** replace the single-pass `overlap.max(by:)` (whose result depends on `Dictionary`'s per-process random iteration order whenever two keys tie) with an explicit two-step pick: find the max *value* first (order-independent), then break ties among the keys holding that value using a fixed, total order. This is the minimum change that makes the result a pure function of the overlap *values*, not of hash-seed-dependent iteration order — no new data structures, no sorting of the whole map, just a filter over the (small, ≤4-element, per CONTEXT.md's "Sortformer... maxes out at 4") tied set.

**Tokens:** this is a plan for a pure-logic bug fix in `Packages/CaptionCore` — no runtime/API cost either way; the only token cost is the one-time fix. Re-running the #271 AMI/CHiME-6 baseline (mentioned in the ticket and in `docs/perf/speaker-scoreboard.md`'s "Follow-ups") needs real datasets and the Sortformer model on the Mac Mini — outside what `swift test` here can do, so I'm not putting it in the task list; it's a post-merge step for whoever owns #271.

**Capability, not passivity:** this makes an existing automated measurement (the speaker scoreboard, #271) trustworthy — the person reading a DER number or a repeat-run diff no longer has to argue around noise that was actually a bug. No UI change, confirmed by the ticket.

## Existing pattern reused

- `SpeakerLabelSmoother.chooseSlot` (`SpeakerLabelSmoother.swift:51-73`) and `SpeakerAligner.speaker` (`SpeakerAligner.swift:20-30`) — both already build an `[Int: Double]` overlap-by-slot map via the same `min(end,...) - max(start,...)` accumulation. I'm not introducing a different overlap model, only replacing `overlap.max(by:)` in each with an explicit max-value-then-tiebreak helper.
- `SpeakerLabelSmoother`'s existing partial tie-break toward `current` (`$1.key == current`) is the seed of tier 1 of the new rule; I'm completing it rather than replacing the idea.

## Time/space complexity

Both functions already do one O(n) pass over `segments` to build the overlap map (n = segments covering the caption, bounded in practice but not literally capped). The fix adds: one O(k) pass to find `maxValue` and one O(k) filter for the tied set, where k = number of distinct speaker slots with any overlap (bounded at 4 by the bundled Sortformer model, CONTEXT.md). So overall still O(n), extra O(k) with k ≤ 4 — no asymptotic change. Space: same O(k) map as today, no new per-call allocation beyond a tiny tied-keys array.

## Why some adversarial categories don't apply

This is pure, non-outward-facing logic (no network, no user input, no file I/O, no concurrency — `SpeakerLabelSmoother` is driven sequentially by one caller per session). Injection/XSS/CSRF/auth/flooding/secrets-in-logs don't apply. The relevant misuse axis here is specifically what the ticket describes: **the same input must give the same output every time**, regardless of incidental factors (dictionary iteration order) that today leak through.

## Tests to write FIRST

All in `Packages/CaptionCore/Tests/CaptionCoreTests/`, existing files (`SpeakerLabelSmootherTests.swift`, `SpeakerAlignerTests.swift`), following the existing `seg(_:_:_:)` helper convention:

1. **`SpeakerAligner`, two-way tie, neither slot special** — `seg(3, 0, 2), seg(1, 0, 2)` (equal overlap, raw slots 3 and 1): asserts result is always `1` (lowest raw index), fed with the segments array in **both orders** (`[seg(3,...), seg(1,...)]` and `[seg(1,...), seg(3,...)]`) — this is the ticket's "build the dictionary from both insertion orders" proxy for process-level dictionary-order randomness, since a single test run can't fork processes to re-roll the hash seed.
2. **`SpeakerAligner`, three-way tie** — three slots with identical overlap: asserts the lowest of the three wins, both with ascending and descending segment-array order. (Covers n>2 ties, where the old ad hoc `max(by:)` predicate was least constrained.)
3. **`SpeakerLabelSmoother`, tie with neither slot = `current`, neither numbered yet** — first caption ever, two segments tying: asserts lowest raw slot wins, both insertion orders.
4. **`SpeakerLabelSmoother`, tie where `current` is one of the tied slots** — after an initial label, a later caption ties between `current`'s slot and a different never-seen slot: asserts `current` always wins, both insertion orders. (Regression for the one tier that already partially existed.)
5. **`SpeakerLabelSmoother`, tie where `current` is nil but one tied slot already has a display number and the other doesn't** — e.g. two people already shown, then a third raw slot appears and ties with a known one: asserts the slot with an existing display number wins over the brand-new one.
6. **`SpeakerLabelSmoother`, tie between two slots that *both* already have display numbers, where the raw slot index would pick the wrong one** — construct history so raw slot 5 got display number 0 and raw slot 2 got display number 1 (first-appearance order can invert raw index); then a tie between 5 and 2: asserts the slot with the **lower display number** (5, "Speaker 1") wins, not the lower raw index (2) — this is the test that actually distinguishes tiers 2 and 3 of the rule.
7. **`SpeakerLabelSmoother`, three-way tie, none current/numbered** — generalizes test 3 to n>2 tied raw slots, both ascending/descending segment order.
8. **Repeat-run determinism, end-to-end** — the literal shape of the bug report: run the *same* sequence of `label(...)` calls (including a tie) on two fresh `SpeakerLabelSmoother` instances and assert the full sequence of returned labels is identical. This is the regression test that would have caught #275 as reported (two repeat runs on the same audio producing different labels).
9. Confirm (no new test needed, just must stay green) that all existing `SpeakerLabelSmootherTests` and `SpeakerAlignerTests` cases — which never hit an exact tie — are unaffected, since the fix only changes behavior when `overlap` values are exactly equal.

## Decisions

None. The ticket's suggested fix is unambiguous and directly implementable; `SpeakerAligner` has no `current` or display-numbering state available to it (it's a stateless pure function used for raw per-word slot lookup in `FaceToFace.swift`/`FaceToFaceEngine.swift`), so "do the same in `SpeakerAligner`" resolves to applying the one tie-break tier that's actually meaningful there — lowest raw slot index.

## Task List

1. [ ] Add tests 1–2 (new) to `SpeakerAlignerTests.swift`.
2. [ ] Add tests 3–8 (new) to `SpeakerLabelSmootherTests.swift`.
3. [ ] Confirm all new tests fail against current code (red), run `swift test --package-path Packages/CaptionCore`.
4. [ ] Implement the tie-break in `SpeakerAligner.speaker`: compute `maxValue = overlap.values.max()`, then `overlap.keys.filter { overlap[$0] == maxValue }.min()`, replacing the `overlap.max(by: { $0.value < $1.value })` call; keep the existing zero-length-range fallback unchanged.
5. [ ] Implement the tie-break in `SpeakerLabelSmoother.chooseSlot`: extract a small static helper (e.g. `bestSlot(overlap:current:numbering:)`) that finds `maxValue`, then among the tied keys returns `current` if present, else the tied key with the lowest value in `displayBySlot` (if any are numbered), else the lowest raw key; call it in place of the current `overlap.max(by:)` line, and use the returned slot's own `overlap[...]` value where the old code used `best.value` (for the `switchSeconds` check).
6. [ ] Run `swift test --package-path Packages/CaptionCore` — all new and existing tests green.
7. [ ] Update the comment block atop `SpeakerLabelSmoother.swift` (currently documents the smoothing rules but not the tie-break) to note the deterministic tie order, so a future reader doesn't reintroduce `max(by:)`.
8. [ ] In the PR description, note as a follow-up (not done by this change): once merged, #271's owner should rerun the AMI/CHiME-6 baseline once on the Mac Mini and confirm 0 repeats differ, DER unchanged (per `docs/perf/speaker-scoreboard.md` "Follow-ups") — this needs the real datasets/model and can't be run from this worktree.
9. [ ] State plainly in the PR which behavior is untested here: the fix itself is fully covered by `swift test` (pure logic, no UI), but the real-world "0 repeats differ" claim from the ticket's evidence section can only be confirmed by the #271 baseline rerun in step 8, not by this agent.