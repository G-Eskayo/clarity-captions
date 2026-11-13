## North-star fit

**Reuses:** the `tourRow`/`canShowTour` pattern (`Apps/Spike/Sources/SettingsPage.swift:467-483`, wired from `TourGate.canReplay(state:)` in `ContentView.swift:775`) for how to describe a captioning-state-gated control later — `.disabled` + dimmed opacity + a plain-words reason line ("Pause captions first, then come back here."); `CaptionLanguageSwitch`'s own doc comments (`CaptionLanguage.swift:161-162,224-226` on the PR branch) and `TranslationCenter.setTarget()`/`captionLanguageChanged()` (`TranslationCenter.swift:175-183,216-218`) for what's actually built today; and `docs/design/smallest-install-and-language-packs.md`'s own framing ("design only... no app code changes until the owner answers") for this doc's header convention. No new type, no code change — this ticket is one markdown file plus a PR reply.

**Simplest sufficient approach:** write `docs/design/from-into-spec.md` as fact, using the owner's three locked decisions verbatim, checked line-by-line against the **real code on PR #256's own branch** (`fix/252-swap-languages`), not against `main`. That distinction is the actual reason the last three attempts failed review, not anything about the three decisions themselves — see below.

**Token/cost:** cheap — docs-only PR, no build, no tests, no screenshots (N/A, no visible effect).

**Phone-OS direction:** indirect — unblocks #251 (one source of truth for readiness) by giving it a stable base to extend.

**More capable or more passive:** more capable — one approvable table instead of re-deciding scattered edge cases per PR, which is what the owner asked for.

### Why the last three attempts failed (verified against the actual branches, not guessed)

I read the two WIP commits (`b6618d3`, `7809b4e`) preserved from today's earlier automated attempts on this same ticket. Both have a **real factual defect**, not a cosmetic one:

- They check `TranslationTargetList.rows()` against **`main`**, where the filter `!CaptionLanguage.sameLanguage($0, captions)` still excludes the caption language from the Into list. But **PR #256's own branch already removed that filter** (`CaptionLanguage.swift:242` on `fix/252-swap-languages`: `.filter { seen.insert(...).inserted }`, no same-language exclusion — doc comment: *"the one being captioned is listed too: the same language on both sides is allowed (owner, #252)"*). The latest draft (`7809b4e`) states the opposite — "every language... **except the current caption language** (not yet built)" — which contradicts both the owner's decision 3 in this ticket ("every language... This replaces 'Into list only offers ready pairs' **everywhere**") and PR #256's own description. That internal contradiction is exactly the kind of defect a code review would flag as "must-fix," and matches the generic "code review found must-fix issues" verdicts with no further detail in the issue log.
- The earlier draft (`b6618d3`) separately cites ticket **`#340`** four times as the home for "not yet built" work. **#340 does not exist** (`gh issue view 340` → "Could not resolve to an issue"). That's a fabricated reference and must not be repeated.
- `b6618d3` also committed scratch files that don't belong in a docs PR: `SPEC_FIX_STATUS.md`, `issue_body.md`, `file_issue.py`, a `.gitignore` edit, and an unrelated new Swift test file (`SpeechDownloadTests.swift`) — none of which this ticket calls for (it's a docs-and-reply ticket, no code).

I verified the three locked decisions against the real branch instead of assuming:

1. **From while captioning:** confirmed **not built** — `SettingsPage.swift`'s From row (`languagePairRow(... ) { onChooseCaptionLanguage?() }`, line 253) has no `CaptionState` gating at all today, unlike `tourRow`'s existing `canShowTour` pattern. The spec states the rule as fact and names the pattern to reuse when it's built, without claiming it's built now.
2. **Into while captioning:** confirmed **contradicted by current code** — `TranslationCenter.setTarget()` (line 178) calls `translations.reset()` unconditionally, wiping *all* in-flight translations, not just future ones. The spec states the owner's rule as fact and flags this exact line as the gap, with no invented ticket number (since none exists) rather than citing `#340` again.
3. **Into list shows every language, greyed/progress by readiness:** confirmed **already built** on `fix/252-swap-languages` (`TranslationTargetList.rows()`, `CaptionLanguageSwitch.Shown`). The spec states this as already-shipped fact, not "not yet built."

I also checked `CaptionLanguageSwitch.choose()/progress()/finished()` on the PR branch: newest-pick-wins is **already correctly implemented at the display level** (`finished()`'s guard on `wanted`/`same(l, locale)` silently drops a stale download's callback) — a materially different, more accurate claim than the earlier drafts' vague "#252 bug may start duplicate downloads." The real remaining gap is narrower: an abandoned pick's underlying `SpeechDownload` task keeps running to completion in the background even though its result is ignored — worth one line in Known Open Gaps, not a dramatic "race" framing.

## Tests first (this is a docs ticket — these are the "break it" checks applied before the PR goes up, not Swift tests)

1. **Branch-accuracy check:** every claim about current code is checked against `origin/fix/252-swap-languages` (the branch PR #256 actually ships), not `main` — the specific defect that sank the last three attempts.
2. **No fabricated references:** every ticket/ADR number cited (`#37`, `#53`, `#60`, `#245`, `#251`, `#252`, ADR 0031) is verified to exist via `gh issue view`/`docs/adr/` before use; nothing like `#340` gets invented for a gap that has no ticket — state "not yet built, no ticket filed" instead.
3. **Self-contradiction check:** grep the finished draft for "only ready pairs" / "except the current caption language" in any Into-list context — must not appear anywhere now that decision 3 replaces it everywhere in the table.
4. **Decided vs. not-yet-built, never blurred:** anywhere the owner's new rule disagrees with what the code does today (From-while-captioning, Into's `translations.reset()`), the spec says so explicitly with a file/line citation — never presents a wish as current fact.
5. **"Notes contradict a chosen option" check** (from the ticket's own break-it list): re-read PR #256 and issue #279 immediately before writing, and again immediately before posting the reply, in case either changed mid-task.
6. **No scratch files committed:** the PR contains exactly `docs/design/from-into-spec.md` (new) and nothing else — no status files, no throwaway scripts, no unrelated test additions.
7. **Reply correctness:** the PR #256 reply carries `<!-- marvin:decisions-addressed -->`, names the new PR/commit, states screenshots are N/A (no visible-effect change) per `docs/agents/pr-requirements.md`, and answers the `spec` decision precisely — not in prose for anything requiring a further owner choice.
8. **Decisions, not silent guesses:** the two genuinely unresolved rows the owner didn't lock (a replaced download's failure-recovery behavior; the `#245`-built vs. `#251`-proposed conflict over whether face-to-face may itself trigger a download) are marked as open Decisions on the new PR, in `docs/agents/decisions-format.md` format — not guessed at and not silently dropped from "one table of every case."

## Decisions

<!-- marvin:decisions -->
### from-download-recover: When a replacement From download fails, what happens to the one it replaced?
From the table: pick language A (downloading), then pick language B before A finishes (B replaces A, per "newest pick wins," already built). B's download then fails.
- [ ] A: Nothing — captions stay in the language that was current before A was ever picked; B's failure shows in the Caption language section; tapping From again retries
- [ ] B: Same as A, but From additionally offers one tap to go back to re-trying A instead of starting over
> **Note:** doesn't block approving the rest of the table — every other From case is decided. (optional)

### face-to-face-readiness: Should face to face's language list follow #245 (built: tapping a not-ready language starts its download) or #251's proposed rule (not-ready languages only ever show greyed with a reason; no feature starts a download)?
- [ ] A: Keep #245 as built until #251 ships, then switch
- [ ] B: Write the table to #251's rule now, as a stated future change to #245
- [ ] Leave this one row open in the spec and decide it when #251 ships
> **Note:** doesn't block approving the rest of the table either. (optional)

## Task List

1. Write `docs/design/from-into-spec.md`: header (owner decisions approved 2026-11-10, no app code changes until approval — matching `smallest-install-and-language-packs.md`'s convention), then sections for **From** (install/download/stall/fail cases, each checked against `SpeechDownload.swift`/`CaptionLanguageSwitch` on the PR branch; the "while captioning" rule stated as owner fact with a **not-yet-built** flag naming `SettingsPage.swift`'s From row and the `tourRow`/`canShowTour` pattern to reuse), **Into** (readiness-by-row stated as **already built**, citing `TranslationTargetList.rows()`/`CaptionLanguageSwitch.Shown` on `fix/252-swap-languages`; "while captioning, earlier lines keep theirs" stated as owner fact with a **not-yet-built** flag naming `TranslationCenter.setTarget()` line 178's `translations.reset()`), **same language on both sides** (already built, #256), and **face to face** (existing #208 rule, with the one open row deferred to the Decisions section).
2. Add a **Known Open Gaps** section: the narrower "abandoned pick's download keeps running in the background" note (not a hallucinated ticket, not a dramatic race claim), and the two Decisions above — no invented ticket numbers for anything that doesn't have one yet.
3. Cross-read the finished table once end-to-end for the "only ready pairs" contradiction and for any other claim not matched against the real branch; fix anything found.
4. Open a new PR from a new branch (not `fix/252-swap-languages` — this is docs-only) containing only `docs/design/from-into-spec.md`, linking PR #256 and `Refs #279`, carrying the two Decisions above.
5. Reply on PR #256 with `<!-- marvin:decisions-addressed -->`: name the new PR, state the `spec` decision was acted on exactly as the owner wrote it, note screenshots are N/A (no visible effect), and point to the two open Decisions on the new PR.
6. Confirm ticket #279's three acceptance criteria are satisfied by steps 4–5 alone (chosen option carried out via the new PR; owner's question answered with the marker; reply states what changed and that screenshots don't apply).