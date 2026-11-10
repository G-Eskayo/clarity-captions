## North-star fit

**Reuses:** the existing `chooseSlot` / `label` machinery in `SpeakerLabelSmoother.swift:51-73` (the `current`, `displayBySlot`/`numbering` state already threaded through) and the existing `overlap.max(by:)` call site in `SpeakerAligner.swift:26`. No new type, no new abstraction, no new state — just replacing the comparator each already uses with one that is a true strict total order.

**Why simplest sufficient:** the bug is that `max(by:)`'s predicate is not a total order — for two tied slots that are both ≠ `current`, the predicate treats them as "equal," so Swift's linear scan keeps whichever one it meets first in the dictionary's (per-process-random) iteration order. The fix is to make every pair of distinct slots strictly comparable by appending the two extra tie-break fields the ticket specifies, with the slot's own `Int` key as a final, always-distinguishing fallback. Once the comparator is a total order over unique keys, `max(by:)` is provably order-independent — no sort, no new loop, no extra data structure needed.

**Tokens/compute:** zero added complexity class. Both functions stay O(k) time / O(k) space in the number of overlapping segments (k), same single linear scan; the tie-break only adds two extra O(1) dictionary lookups (`current` compare, `displayBySlot[key]`) per pairwise comparison inside the existing `max(by:)`. Diff is two small comparator rewrites plus tests — no runtime behavior changes outside exact-tie cases.

**Phone-OS / user-capability fit:** directly serves "labels the person reading can trust; decisions from measured, repeatable data" (stated in the ticket). It turns the #271 scoreboard from something that has to argue around noise into a real, repeatable measurement — makes the user (Gil, reading benchmark deltas) more able to trust a number, not more passive.

**Scope check against the code:** confirmed by reading `SpeakerPathReplay.swift:74-82` — the #271 harness calls exactly `SpeakerLabelSmoother.label` and `SpeakerAligner.speaker` per emission, nothing else. A repo-wide grep for `max(by:)` turns up only these two speaker-overlap sites (`ZipformerDecoder.swift:43` is logits argmax, `FaceToFaceLanguages.swift:297` is latest-by-end-time, `ContentView.swift:707` is latest-by-savedAt — none are overlap ties, out of scope). So this ticket's fix is exactly two functions, matching its own "Suggested fix" scope. No Decisions section needed — the ticket's suggested fix is fully specified and unambiguous.

**No UI change** (ticket states this explicitly, and I confirmed no `Apps/Spike` files are touched) — the playbook's Look-proof/App-build gates don't apply. The `swift test` Build gate does.

**Untested by this session:** the ticket's own verification step — "rerun the #271 baseline once and confirm 0 repeats differ" on real AMI/CHiME-6 audio through the real FluidAudio/Sortformer model — needs real audio and a live model run (`claimed:macbook-pro`), which this coding session cannot execute. That remains a follow-up measurement step after merge, not something `swift test` can cover.

## Tests first

All new tests live in `Packages/CaptionCore/Tests/CaptionCoreTests/SpeakerLabelSmootherTests.swift` and `SpeakerAlignerTests.swift`, following the existing `seg(speaker, start, end)` helper convention in each file.

**`SpeakerAligner` (no `current`, no numbering — only the final "lowest slot index" rule applies):**
1. Two slots with exactly equal overlap, non-adjacent indices (e.g. 7 and 2) → lowest index (2) wins, asserted with the two tied segments fed in **both array orders** (this is what actually varies dictionary insertion order; per the ticket, a single fixed order could pass by luck).
2. A three-way exact tie (e.g. slots 9, 1, 5) → lowest (1) wins, checked across multiple permutations of the segment array.
3. An exact tie between two slots plus a third slot with strictly lower (non-tied) overlap present → the low-overlap slot must never win; the tie-break only applies among the actual maximum.
4. Pure-function repeat check: calling `speaker` twice with the identical tied input yields the identical result (guards against any accidental hidden state/non-determinism in the rewrite).

**`SpeakerLabelSmoother` (`current` → lowest existing display number → lowest slot index):**
5. Tie between `current` and a fresh equally-overlapping slot → `current` wins, fed in both segment orders. (Not currently covered — existing tests never construct an exact-overlap tie.)
6. First caption of a session: two brand-new slots tie exactly (neither has a number, no `current` yet) → lowest raw slot index wins, both orders.
7. A known slot (already has a display number) ties exactly against a never-seen slot, and neither is `current` → the slot with the existing number wins (a live/new slot must not win a tie against a known one), both orders.
8. Two already-known slots tie exactly, where the slot with the **lower display number** has the **higher raw slot index** (constructed so slot-index order and display-number order disagree) → the lower *display number* wins, proving the rule is number-based, not index-based; both orders.
9. A wider tie: 4+ slots all tied at once, mixing "has number"/"no number" cases, across several permutations of the segment array — catches any subtle non-transitivity in the rank function that a 2-way test could miss.
10. Loop the scenario from test 7 across many fresh `SpeakerLabelSmoother` instances in one test body (the ticket's "many fresh smoothers" check, adapted to a single process since we can't force a different hash seed per test) → result must be identical every time.

**Regression guard (not new tests, a check):** run the full existing suite after the change — every current `SpeakerLabelSmootherTests`/`SpeakerAlignerTests` case must still pass unmodified, proving the rewrite doesn't change any already-decided (non-tied) outcome.

**Deliberately not adding:** malformed/NaN timing tests (untouched by this fix, not flagged by the ticket), concurrency tests (both are plain value-type structs/pure functions with no shared mutable state — nothing to race), permission/dependency-failure tests (no I/O, no dependency in this pure logic) — these attack surfaces don't apply to a pure in-memory tie-break fix, so adding them would be test cruft, not coverage.

## Task List

1. [ ] Read current `SpeakerLabelSmoother.swift:51-73` and `SpeakerAligner.swift:19-30` once more immediately before editing (done above, re-confirm no drift).
2. [ ] Write the 10 new tests above (steps 1-4 in `SpeakerAlignerTests.swift`, steps 5-10 in `SpeakerLabelSmootherTests.swift`) and confirm they fail against the current code (red).
3. [ ] In `SpeakerAligner.swift`, replace the `overlap.max(by: { $0.value < $1.value })` comparator with one that breaks exact-value ties by lowest slot key, making the ordering a strict total order (so `max(by:)` is independent of dictionary iteration order).
4. [ ] In `SpeakerLabelSmoother.swift`, replace the `chooseSlot` comparator at line 63 with a rank-based comparator implementing: higher overlap wins; on tie, `current` wins; on tie, the slot with an existing `displayBySlot` entry wins (lower display number breaks a number-vs-number tie); on tie, lower raw slot key wins. Keep every line below (`long.isEmpty` live-scrap check, `sameUtterance`/`switchSeconds` hold logic) unchanged — only the tie-break predicate changes.
5. [ ] Run `swift test --package-path Packages/CaptionCore` and get all tests (old + new) green.
6. [ ] State the complexity note as a doc comment or PR note: both functions remain O(k) time / O(k) space in the number of overlapping segments; the tie-break adds only O(1) extra lookups per comparison, no change in asymptotic complexity.
7. [ ] Write the PR: name the ticket ("Closes #275"), state plainly that the #271 real-audio baseline rerun (AMI/CHiME-6, confirm 0 repeats differ) is the one acceptance item this session cannot execute and is a follow-up, and that there is no UI change / no screenshots needed.