I now have enough grounded detail. Here is the plan.

## North-star fit

**Reuses before adding anything new:** the Decisions-block mechanism already live on PR #256 (`docs/agents/decisions-format.md`, same `<!-- marvin:decisions -->` / `<!-- marvin:decisions-addressed -->` pattern the earlier `swap-place` reply already used on this PR) and this repo's existing "topic-named design doc" convention (`docs/design/v1-polish-spec.md`, `docs/design/smallest-install-and-language-packs.md` — a spec doc gets a plain slug, not a ticket number). No new mechanism, label, or file type.

**Why this failed five times before, and what's different this time:** the dangling WIP from the attempt just before mine (`git show 5e0e4bd:docs/design/from-into-spec.md`) regenerated the *exact* contradiction-laden table the owner's "Parked" review already rejected on issue #266 — it still listed "Change From while captioning" / "Change Into while captioning" as open "owner questions," even though issue #279's own body settled both three days later ("They're decided now. Write them into `docs/design/from-into-spec.md` as fact, not as open questions"). None of the five prior attempts seem to have re-derived the table from the actual code; they recycled the same claims (some wrong) draft to draft. I read the real code on `fix/252-swap-languages` (`CaptionLanguage.swift`, `TranslationCenter.swift`, `SpeechDownload.swift`, `CaptionLanguagePage.swift`, `CaptionTranslations.swift`, `FaceToFaceStatus.swift`) and found the earlier drafts were wrong in three places I can point at a line number for:
- The "same-language passthrough" was marked **"unverified claim"** in the dangling WIP — it isn't: `TranslationCenter.refreshConfiguration()` and `.passesThrough` call `CaptionLanguage.needsNoTranslation` directly and `passThrough(latest)` sets each line's translation to its own text. Verified, not a claim.
- "A second From pick **cancels** the first download" — it doesn't. `CaptionLanguageCenter.choose()` has no cancellation; the old `SpeechDownload.run()` keeps running until it finishes or stalls, its result just gets discarded by `change.finished()`'s locale guard. Two overlapping downloads of the *same* locale are exactly how the owner's own iPad log (#252) reproduces, because `SpeechDownload.language(_:)` makes a fresh instance (fresh single-flight lock) every call — I can cite the exact lines.
- The owner's now-decided fact "earlier lines stay as they were" when Into changes mid-session is **not true of the code today** — `TranslationCenter.setTarget()` calls `translations.reset()`, and `CaptionTranslations.reset()` wipes `done`, which blanks every already-shown line's translation, not just future ones. This is the kind of self-contradiction the "Parked" review was watching for, except between the owner's fact and the *code*, not between two rows of the table. I write it as: decided fact (owner's words, verbatim) + "not built yet, needs a follow-up ticket" — same pattern already used for #251/readiness, so the table states one target behavior per case and marks build status separately, never two behaviors for one case.

**Simplest sufficient approach:** the owner's chosen option *is* the scope — "one table... as a ticket for you to approve before more is built." This is a docs-only deliverable; writing Swift now would contradict the decision being acted on (acceptance criteria don't ask for behavior changes, only for the spec and the reply).

**Cost:** cheap — no `swift test`, no simulator build, no screenshots (pr-requirements.md: "N/A is only acceptable for changes with no visible effect (docs, tests, internal logic)" — this is docs-only).

**More capable, not more passive:** gives Gil one table to approve once, grounded in what the code actually does today vs. what's decided-but-not-built, instead of a sixth attempt he has to find the same contradictions in by hand.

**Machine:** none — no build required.

## Scope: no Swift changes

This ticket touches no file under `Packages/CaptionCore` or `Apps/Spike`. `swift test` and the app build are unaffected and not re-run — the untested-behavior note is "all of it," since nothing in the app changes.

## Verification ("tests try to break it," adapted — this produces no code)

1. **Contradiction check** (the exact failure mode that parked this three times): every row that touches "From/Into while captioning" or "what the Into list shows" is checked against the owner's three settled facts in #279's body and against the real `CaptionLanguage.swift`/`TranslationCenter.swift`/`CaptionTranslations.swift` behavior — stated above, not reused from any prior draft unchecked.
2. **Freshness check:** re-fetch `gh pr view 256` and `gh pr view 256 --comments` immediately before posting the reply, to confirm no newer commit or `-addressed` reply landed since 2026-11-10T04:44:11Z (concurrent-agent misuse case — another run could be dispatched on the same ticket).
3. **Staleness-of-branch check** (new this attempt): `fix/252-swap-languages`'s merge-base with current `origin/main` is `bade016`, four commits behind `origin/main`'s tip (`050e54f`) — but `git diff --stat origin/main origin/fix/252-swap-languages` shows ~18,900 deleted lines, because the branch never picked up the large voice/speaker-match work merged to main after 2026-11-09. The spec cites code *on that branch* for From/Into behavior (where PR #256's changes live) but doesn't commit anything there — committing the new file to the stale branch would be wrong.
4. **Gate check:** the new PR's Decisions block (one question, below) validated against `bin/gh`'s parser (`DECISIONS_NOT_ASKABLE`/`DECISIONS_UNPARSED`) before pushing — a malformed block is a real failure to fix, not something to route around.
5. **Idempotency check:** no open PR or issue already carries this spec — `gh pr list --search "from-into-spec"` and `gh issue list --search "From Into spec"` both came back empty (checked above); re-run immediately before opening the PR, since 5 prior attempts ran on this exact ticket.
6. **Completeness check:** the table covers every category the owner named (download/stall/fail, same language both sides, face to face, mid-captioning change) plus the two misuse cases from #252's comments that aren't fixed (two downloads of one locale; a stalled download with no explanation — the second of which turns out to already be built, see below) — verified against the draft before filing, not assumed.
7. **Failure-is-not-silence check:** if `git push`, PR creation, or `gh pr comment` fails (auth, network, gate refusal), the task reports the failure plainly rather than treating it as "nothing to change" — this is literally how one of the five prior attempts failed ("Final verdict: nothing changed").

## Decisions (goes in the new PR's description)

Only one case has no owner answer anywhere in #279, #256, or #252 — everything else is either already decided (owner's three facts) or already built and unambiguous from the code. This is the only genuine open question:

```markdown
## Decisions
<!-- marvin:decisions -->
### duplicate-reveal: Same language on both sides — when a line is tapped open, "what was said" repeats the translation above it word for word. Keep that, or skip the reveal when there's nothing new to show?
- [ ] A: Keep it — every folded line behaves the same way, tap always reveals "what was said" (consistent, even if it repeats)
- [ ] B: Skip it — a same-language line isn't tappable (or tapping does nothing), since there's nothing under the translation that isn't already on screen
<!-- /marvin:decisions -->
```

(Reframed from every prior draft's "hide the duplicate line" — that described two lines always stacked, which hasn't been true since PR #255/#246's "Folded" look: only the translation shows by default; a tap reveals "what was said" underneath. When From=Into, the revealed line and the translation are identical text, which is the real redundancy — verified against `TranslatedCaptionView.swift`.)

## Task List

1. Write `docs/design/from-into-spec.md` on this branch (`pipeline/g-eskayo/clarity-captions#279`) with:
   - A short intro citing #37, #53, #245 (closed, built), #251 (open, not built), #252, PR #256, ADR 0031 (proposed, not built).
   - **From (caption language) table:** install-immediately, download-with-real-%, download-fails/stalls (including that the 90-tick stall watchdog and its message are already built — `SpeechDownload.swift`'s `StallWatch` / `DownloadProblem.stalled`, shown via `CaptionLanguageDownloadLine`'s `.failed` case — correcting every prior draft's "not yet handled" claim), a second pick on the same locale while one downloads (not cancelled — discarded on completion by `change.finished()`'s locale guard; and this is the confirmed mechanism behind the owner's #252 double-download log, since `SpeechDownload.language(_:)` makes a fresh single-flight lock per call), and **"change From while captioning" — decided (owner, #279): not allowed, must stop first, control states why; not built — `CaptionLanguageCenter.choose()`/`set()` has no such check today, needs a follow-up ticket.**
   - **Into (translation target) table:** install-immediately, same-language-allowed-and-verified-passthrough (`CaptionLanguage.needsNoTranslation`, `TranslationCenter.passThrough`), Into's speech-model download (real %, `TranslationCenter.setUpIntoSpeech`) kept distinct from Into's translation-pair download (Apple's sheet, no percentage — "Downloading, Apple shows progress," #251's own words), unsupported pair (`unsupportedPair`, said plainly but not yet greyed-out-with-reason in the list itself), and **"what the Into list shows" — decided (owner, #279): every language, not-yet-downloaded show the same "· downloading N%" as From, unsupported ones greyed out with a reason; replaces "only ready pairs" everywhere. Not built — `TranslationTargetList.rows` only ever sees a pre-filtered `supported` list today; tracked by #251.** And **"change Into while captioning" — decided (owner, #279): allowed, new lines use the new language, earlier lines stay as they were; not built — `TranslationCenter.setTarget()` calls `translations.reset()`, which wipes already-shown lines' translations too (`CaptionTranslations.reset()`), needs a follow-up ticket.**
   - **Face to face table:** only ready pairs offered, never starts a download itself, always-reachable Stop, per-half plain-words status — all built and closed under #245 (`FaceToFaceReadyLanguages`, `FaceToFaceStatus`), cited, not re-litigated.
   - **Known gaps, flagged but not fixed here** (each needs its own ticket, not folded into this spec or built now): the two-downloads-of-one-locale bug (#252's log; root cause above); same-language's tap-reveal redundancy (the one Decision above).
   - The Decisions block above.
2. Re-run the idempotency and freshness checks (step 5/2 above) immediately before pushing.
3. Commit (`Refs #279`, per `docs/agents/pr-requirements.md`'s "commits name the ticket") and push the branch.
4. Open the PR against `main` if the pipeline hasn't already opened one from this branch — title "Spec: how From, Into and face to face behave (owner's 'spec' decision on PR #256)" — body states no app files changed, "N/A: docs only, nothing visible changed," links PR #256 and #279, and carries the Decisions block.
5. Confirm the PR's Decisions block parses (gate check, step 4 above) — fix and re-push if `bin/gh` refuses it.
6. Reply on PR #256 with `<!-- marvin:decisions-addressed -->`: states the `spec` decision was carried out by opening PR #<N> (linked), summarizes the three corrected claims above so Gil doesn't have to re-derive them, says no code changed on `fix/252-swap-languages` (the decision asked for a ticket/PR, not a commit there), and screenshots don't apply (nothing visual changed).
7. If any step fails (push, PR creation, or the reply), stop and report the failure plainly rather than calling it "nothing to change."