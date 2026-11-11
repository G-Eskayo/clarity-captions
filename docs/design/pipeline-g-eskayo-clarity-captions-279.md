## North-star fit

**Reuses:** the owner-decisions reply pattern already used on this PR (the `<!-- marvin:decisions-addressed -->` comment that closed out the `swap-place` decision) and the `docs/agents/decisions-format.md` Decisions-block mechanism, which `decisions-format.md` itself says works on tickets, not just PRs ("a ticket labelled `needs-info` with a Decisions section moves to `ready-for-agent` once every required question is answered"). No new mechanism needed.

**Simplest sufficient approach:** the owner's own chosen option for the `spec` decision is explicit — *"as a ticket for you to approve before more is built"* — not a code change. `CaptionLanguage.swift` on `main` still has the same-language filter (`TranslationTargetList.rows`, line 219) because PR #256 (which removes it) hasn't merged; that removal is already built and reviewed on `fix/252-swap-languages` and isn't this ticket's job to touch. This ticket's entire scope is: write the behavior table, file it as a new GitHub issue for approval, and reply on PR #256. No Swift, no commit on the PR branch — `decisions-format.md` confirms a commit isn't required, only a commit *or* an addressed reply *or* a completed follow-up ticket.

**Why the first two attempts failed:** attempt 1 ("code review found must-fix issues") likely treated this as a code task and wrote something unneeded. Attempt 2 ("nothing changed") likely correctly saw no code was needed but then did nothing GitHub-side either — a silent no-op, which the acceptance criteria don't allow ("Every chosen option is carried out... every owner question is answered in a reply"). This plan's deliverable is two concrete GitHub artifacts (an issue + a PR reply), not a diff.

**Token/compute cost:** cheap — no builds, no simulator, no Swift changes. `swift test` isn't affected by this ticket at all (stated plainly below as untested-because-untouched, not "untested because unverifiable").

**User capability:** this keeps Gil in control of a cross-cutting UX spec before more From/Into code gets built on top of ambiguous rules — directly serves north star 3 (raises the human's judgment on a decision that's genuinely his to make) and north star 1 (resolving ambiguity once in a table beats re-deciding it piecemeal on every future PR, which is what's been happening — #252, #245, #251 each hit a slice of the same unanswered questions).

**Machine:** none — no build required, runs anywhere `gh` is authenticated.

## Decisions I surface (owner must choose on the GitHub issue I create — handled as a Decisions block there, not here)

<!-- marvin:decisions -->
### same-language-display: When From and Into are the same language, show the duplicate translated line, or hide it?
- [ ] Show: the translated line stays under the original, even though it repeats it (current build)
- [ ] Hide: when From and Into match, show one line, no repeat

### spec-approve: Approve this behavior table as the spec for From/Into, or does it need changes first?
- [ ] Approve: build against this table
- [ ] Needs changes: use the note to say what

These two questions go on the **new ticket I file**, not on PR #256 — PR #256's reply only reports that the ticket exists and links it; it asks nothing new (a reply with a question can't carry the `-addressed` marker and get the PR unstuck).

## Verification (no code, so no unit tests — here's what stands in for them)

1. **No-contradiction check:** the `spec` decision's note field is empty (only the earlier `swap-place` decision had a note, already answered in the existing `-addressed` reply) — confirmed by rereading both decision comments; nothing to flag as contradicting.
2. **Freshness check:** re-fetch `gh pr view 256` and `gh pr view 256 --comments` immediately before posting, to confirm no newer decision/reply landed since this read (stale-state misuse case — another agent or Gil could act on PR #256 concurrently).
3. **Idempotency check:** `gh issue list --search` for an existing "From/Into spec" ticket before creating one — already run once, no match (`251, 266, 220, 260, 104` are the only hits, all unrelated). Re-run immediately before creating, in case attempt 1 left a stray partial issue.
4. **Gate check:** `bin/gh`'s decisions rule (`DECISIONS_NOT_ASKABLE` / `_UNPARSED`) will refuse the new issue body if the Decisions block is malformed — treat a refusal as a real failure to fix and retry, not something to route around with `MARVIN_DECISIONS_OK`.
5. **Completeness check:** the table must literally cover every category the owner named — "a pick that downloads, stalls or fails; the same language on both sides; face to face; a change while captioning" — plus the two misuse cases from #252's own comments that aren't yet fixed (one pick firing two downloads of the same locale; a stalled Apple asset server with no explanation). Verified against the table draft below before filing.
6. **Failure-is-not-silence check:** if `gh issue create` or `gh pr comment` fails (auth, network, gate refusal), the reply/report says so plainly — it does not get treated as "nothing to change" (this is exactly how attempt 2 went wrong).

## The table's row categories (content to assemble into the new issue, per source)

| Case | Today's behavior / source | Open question |
|---|---|---|
| Pick an installed caption language | Switches immediately, no download (`CaptionLanguageSwitch.choose`) | none |
| Pick a non-installed caption language | Old language stays until done; From row shows "`<language> · downloading N%`" (#252, this PR) | none |
| Download fails | `phase = .failed`, bottom Caption-language section says why | none |
| A second pick arrives mid-download | Newest pick wins (tested) | none |
| One pick fires two installs of the same locale | **Bug, not fixed** — iPad log in #252's comments; `SpeechDownload` claims single-flight but a second caller slips through | needs a bug ticket, not this spec |
| Apple's asset server never starts the download | No watchdog message surfaced to the From row today (#252 comment) | needs building, not yet done |
| Same language on both sides | Allowed (#252 decision, built in this PR); `TranslationCenter` passes lines through untranslated | **same-language-display** (above) |
| Translation pair needs downloading | Apple's sheet, indeterminate progress — "Downloading, Apple shows progress" (#251) | none |
| Unsupported pair on this OS version | Plain message, e.g. "Can't translate this pair on this iPad (needs iOS 27)" (#245) | none |
| Face to face, either half not ready | Must never trap or go silent; Stop always visible and works in every state; only ready languages offered or marked (#245) | none — #245 already specifies this, table just cross-references it |
| No feature starts a download itself | Owner's standing rule, repeated in #251 and #252 — only Settings downloads | none |
| Deleting the last translation language | Blocked while translation is owned (ADR 0031 §3) | none |
| From or Into changed while captioning is running | **Not specified anywhere today** — this is the owner's own named gap | needs the owner's call: take effect immediately mid-session, or require a pause? Proposed default in the ticket, owner can override via `spec-approve`'s note |

## Task List

1. Draft the full behavior table (above, filled out in prose per row with file/issue citations) as the body of a new GitHub issue, titled e.g. *"Spec: From/Into behavior in every case (owner approval before more is built)"*, linking #37, #53, #245, #251, #252, PR #256, and ADR 0031, labeled `needs-info` (not `ready-for-agent` — it can't be worked until approved) plus `feature:translation`, `feature:languages`.
2. Include the `same-language-display` and `spec-approve` Decisions block from above in that new issue, validated against `bin/gh`'s parser before filing.
3. Re-run the idempotency and freshness checks (duplicate-issue search, re-fetch PR #256 state) immediately before filing/posting.
4. File the issue via `gh issue create`; capture its number.
5. Post a reply on PR #256 carrying `<!-- marvin:decisions-addressed -->`: states the `spec` decision was carried out by filing issue #N (linked), that no code changed on `fix/252-swap-languages` because this decision asked for a ticket rather than a code change, and that screenshots stand unchanged (nothing visual changed).
6. If step 4 or 5 fails for any reason (auth, network, gate refusal), stop and report the failure plainly in the final summary rather than treating it as "nothing to change."

No Swift/test changes: this ticket does not touch `Packages/CaptionCore` or `Apps/Spike`, so `swift test` and the app build are unaffected and are not re-run as part of this ticket's own verification — the untested-behavior note for this ticket is "all of it," since there is no behavior change, only a documentation/process artifact.