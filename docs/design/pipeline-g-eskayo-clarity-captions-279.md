## North-star fit

- **Reuses before adding anything new:** the Decisions format already live on PR #256 (`docs/agents/decisions-format.md` / `~/.agents/docs/agents/decisions-format.md`) and the ticket-filing convention in `docs/agents/issue-tracker.md`; the "waiting on MARVIN" reply pattern already used in PR #256's own addressed comment (`<!-- marvin:decisions-addressed -->`). No new type, file or abstraction — this ticket is pure documentation, not code.
- **Ground truth, not guessing:** every row of the table below is checked against the current branch's actual code (`CaptionLanguageSwitch` in `CaptionLanguage.swift`, `SpeechDownload.swift`, `FaceToFaceLanguages.swift`/`FaceToFaceStatus.swift`, `TranslationCenter.swift`) and the five issues the owner's prior reply already named (#37, #53/ADR 0031, #245, #251) plus #252's own comments, not invented.
- **Simplest sufficient approach:** the owner's chosen option *is* the whole scope — "one table... as a ticket for you to approve before more is built." Writing Swift now would contradict the decision being acted on.
- **Cost:** cheap — no `swift test`, no simulator build, no screenshots; the spend is reading and writing one document.
- **More capable, not more passive:** gives Gil one table to approve or amend instead of reconstructing behavior from five scattered issues and a PR thread each time; unblocks #251 and future From/Into work with one contract instead of tribal knowledge.

## Scope: this ticket produces no code change

Acceptance criteria from #279, mapped:
- Chosen option ("spec: Yes") → write the table, file it as a new issue.
- Owner questions answered on PR #256 with the addressed marker → only `spec` is unaddressed now (`swap-place` and `swap-notes` were already answered in the 2026-11-09T19:24:37Z reply).
- Reply states what changed and screenshot status → "no code changed; this reply files issue #N" (no screenshots apply).

The decision names a ticket, not a PR, so there is nothing to carry out on branch `fix/252-swap-languages` itself — stating this plainly rather than inventing a diff to justify a commit.

## Verification ("tests try to break it," adapted — no Swift code changes here)

#279's break-it list is about this reply itself, not Swift behavior, so the checks are:
1. Re-read PR #256 now, immediately before acting (done above): still `OPEN`/`MERGEABLE`, same file list as the decision comment's branch — no drift since 2026-11-10T04:44:11Z.
2. Cross-check every table row against the current code (done via direct read + fork survey) and the cited issues, so no row contradicts a chosen option; any contradiction gets stated, not papered over. One was found and is called out below (same-language passthrough: the PR body claims a bypass of Apple Translation that isn't actually present as a short-circuit in `TranslationCenter`).
3. Validate the new issue body parses as a legal Decisions block (`<!-- marvin:decisions -->`, unique lowercase-dash ids, ≥2 options per required question) before filing — `bin/gh`'s gate (`DECISIONS_NOT_ASKABLE`/`DECISIONS_UNPARSED`) rejects it otherwise, which doubles as a build check for this stage.
4. Confirm no commit or addressed reply landed on PR #256 between now and the decision timestamp (concurrency/stale-state case) before posting.
5. After filing, `gh issue view <N>` to confirm the number resolves before linking it from the PR reply (no dead link).

## New issue body (content to file verbatim)

**Title:** `Spec: how From, Into and face to face behave in every case (owner's Decision on #256)`
**Labels:** `needs-info`, `feature:translation`, `feature:languages` — `needs-info` because it carries a required Decisions block (per `docs/agents/issue-tracker.md`'s "a ticket labelled needs-info... moves to ready-for-agent once every required question is answered"); not `ready-for-agent`, since nothing should build against it until Gil approves.

Body:

```markdown
## What this is

Refs #252, #256, #37, #53, #245, #251, ADR 0031. The owner's Decision on #256 ("spec: Yes") asked for one table of
every From/Into/face-to-face case, as a ticket to approve before anything else changes them. This is that table,
checked against the code on `fix/252-swap-languages` and the five issues above — not a new design.

## The table

| Case | Behavior | Where | Tested |
|---|---|---|---|
| Pick an installed language | Switches at once, captions continue in the new language immediately | `CaptionLanguageSwitch` (`CaptionLanguage.swift`) | Yes |
| Pick a language that needs downloading | From/Into row shows "`<language>` · downloading N%"; old language stays active until it finishes | `CaptionLanguageSwitch.Phase.downloading`, `LanguageSettings.swift` | Yes |
| A second pick while the first is still downloading | Only the newest pick wins; the first's completion is ignored | `CaptionLanguageSwitch` (superseded-download handling) | Yes |
| Re-picking the language already mid-download | Cancels the in-flight switch; nothing changes | `CaptionLanguageSwitch` | Yes |
| Download fails or stalls (no bytes for 90s) | Old language stays active; a plain-words reason is shown ("Apple's download hasn't started. Check Wi-Fi or VPN, or try again") | `SpeechDownload`'s stall watchdog + `DownloadProblem` | Yes |
| **One pick starts two downloads of the same locale** | **Bug, not fixed.** `SpeechDownload`'s single-flight lock is per-instance, not per-locale; `CaptionLanguageCenter.choose()` and `TranslationCenter.setUpIntoSpeech()` each create a fresh instance, so two overlapping calls for the same locale can still race — this is the exact iPad log from #252's comment. Tracked here; fix is a follow-up PR once this spec is approved, no new choice needed. | `SpeechDownload.swift` | No |
| Same language on From and Into | Into's list no longer filters out the caption language | `CaptionLanguageList.Translation.yourLanguage` | Yes |
| Same language, live caption line | **Unverified claim.** PR #256's description says lines "pass through as their own translation" instead of asking Apple for a same-to-same pair, but no short-circuit was found in `TranslationCenter`'s live session path — that code is UIKit/Translation-framework and isn't unit-testable. Needs a manual check on a real device (Apple may just handle identical source/target itself); flagging rather than asserting it's correct. | `TranslationCenter.swift` | No (can't be) |
| Same language, the duplicate line on screen | The translated line still shows stacked under the original even when identical (CONTEXT.md's "folded translated caption"). Gil asked in #256's description whether the duplicate should be hidden instead — open, see Decisions below. | `TranslatedCaptionView.swift` | N/A (visual) |
| Face to face: which language pairs are offered | Only pairs with speech installed **and** the translation pair already downloaded; never starts a download itself (owner's #245 rule) | `FaceToFaceLanguages.swift` | Yes |
| Face to face: fewer than 2 ready languages | Shows the setup screen with a fixed reason, not the split | `FaceToFaceLanguages.swift` | Yes |
| Face to face: per-half status | Always says what's happening in plain words: tap-to-start, downloading, listening, waiting-for-other, paused, or failed-with-reason | `FaceToFaceStatus.swift` | Yes |
| Face to face: Stop | Always reachable and always exits the split, in every state, via `SplitWorkQueue.cancelAll()` | `FaceToFaceSplit.swift` | Logic yes; on-screen reachability only by screenshot |
| **Changing From or Into while captioning is running** | **Confirmed gap — no code handles this.** `CaptionLanguageCenter.set()` swaps `engineLocale` and warms a new engine with no check for whether captioning is active, no pause/resume state, no test. This is the case Gil's note flagged as the one "we're struggling the most with." See Decisions below. | `CaptionLanguageCenter.swift` | No |

## Decisions
<!-- marvin:decisions -->
### duplicate-line: Same language on both sides — hide the duplicate line, or keep it stacked?
- [ ] A: Hide the translated line when From and Into match; show one line, same as untranslated captions
- [ ] B: Keep both lines stacked even when identical, so the layout never changes with the language choice

### midsession-change: Picking a new From or Into language while captioning is running
- [ ] A: Pause captioning, show a brief "restarting in `<language>`" state, then resume automatically
- [ ] B: Queue the change silently; it only takes effect after the user stops and starts again
- [ ] C: Switch immediately mid-stream, same as when stopped, with no special state

### approve: Approve this as the behavior spec for From, Into and face to face — build against it until a follow-up ticket says otherwise?
- [ ] Yes
- [ ] No
```

## PR #256 reply (content to post verbatim, with the addressed marker)

```markdown
<!-- marvin:decisions-addressed -->
### Your decision, acted on

**spec: Yes.** Filed #<N> — one table of every case (a pick that downloads, stalls or fails; same language on
both sides; face to face; a change while captioning), checked against the code on this branch. It carries two open
cases as Decisions (hiding the duplicate line when From=Into; what happens when the language changes mid-session)
plus an approval gate, and flags one known bug (#252's "two downloads of one locale" log) as a tracked follow-up,
not a new choice.

No code changed on this branch — the decision asked for a ticket, not a PR, so there's nothing to commit here.
Screenshots: not applicable, nothing visual changed.
```

## Task List

1. File the new GitHub issue on `G-Eskayo/clarity-captions` with the title, labels and body above (`gh issue create`, per `docs/agents/issue-tracker.md`'s convention).
2. `gh issue view <N>` to confirm it resolves before referencing it anywhere.
3. Post the reply above on PR #256 with `<!-- marvin:decisions-addressed -->`, substituting the real issue number.
4. Re-check PR #256's description hasn't gained a new commit or reply since step 1 started (stale-state guard) before posting step 3; if it has, stop and say so instead of posting over it.

No Swift files, ADRs, or app code are touched by this ticket.