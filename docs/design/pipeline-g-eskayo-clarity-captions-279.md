## North-star fit

Reuses the owner's own established pattern for this exact situation: `docs/agents/decisions-format.md`'s "ticket with a Decisions section, labelled `needs-info`" flow (the same mechanism PR #256 itself used for `swap-place` and `spec`), and the existing reply pattern already used once on this PR (`<!-- marvin:decisions-addressed -->`, visible in the second PR #256 comment). No new process, tool, or file format — just running the one that's already in `decisions-format.md` and was already applied in this thread. This is the simplest sufficient approach: the owner chose "write the spec as a ticket for me to approve"; there is nothing to design, only to do it accurately and hand it back to him in the same shape he already uses.

Token/compute cost: no Swift code changes, no `swift test`, no app build — this ticket's chosen option is documentation plus process (file a ticket, reply to a PR), so it spends tokens reading the real code once (to ground the table in what's actually built, not guesses) and nothing on CI. It leaves the owner more capable, not less: instead of the From/Into rules staying scattered across #37, #53, ADR 0031, #245, #251 and #252's comments the way the prior reply described, he gets one table to approve or correct, and MARVIN stops building more of this area until he has.

Machine: this worktree only (plan + two `gh` calls); no build machine needed since nothing compiles.

## What I verified by reading the actual code (fix/252-swap-languages branch, not yet on main)

- `CaptionLanguageSwitch` (`Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift:157`) and `SpeechDownload` (`Packages/CaptionCore/Sources/CaptionCore/SpeechDownload.swift`) already give single-flight-per-instance downloads, a 90-tick stall watchdog, and three plain-words failure messages (`DownloadProblem.offline/.stalled/.failed`).
- Same-language pass-through is real and wired for one-way (`TranslationCenter.passThrough`) and face-to-face reverse (`passThroughReverse`), both via `CaptionLanguage.needsNoTranslation` (`TranslationCenter.swift:257,301,306`).
- Two gaps I found that nobody has written down, which belong in the table as open cases, not as already-solved: (1) `SpeechDownload`'s single-flight lock is per *instance* — two separate `SpeechDownload.language(locale)` calls for the same locale (e.g., first-run's download screen and `CaptionLanguageCenter.choose`) aren't mutually exclusive, which matches #252's "one pick starts two installs" log better than "already fixed" would; (2) `CaptionLanguageCenter.set()` updates the stored language and the static `engineLocale` box immediately, but an already-running engine was built with the old locale and isn't restarted — so a From change *while captioning* only takes effect on the next Start, which is undocumented behavior, not a confirmed design.

## Tests I will write first

None — this ticket's chosen option produces a GitHub issue body (the spec table) and a PR reply, not Swift code. There is no CaptionCore or app-layer behavior changing, so there is nothing for `swift test` to check and no `CaptionSessionControllerTests` to touch. I'm saying this plainly rather than inventing tests to satisfy the format: a bug fix or feature change would need them; writing down existing, already-tested behavior into a table does not change what the tests assert.

Applying the ticket's "how we'll try to break it" list to *this* task instead (since it's about correctness of the write-up, not code):
- **The notes contradict a chosen option** — checked: the `spec` decision carries no note text, and the `swap-place` note ("do we have the behaviors specced out...") was already answered in the prior reply by proposing this exact spec ticket. No contradiction to flag.
- **The PR changed since the decisions** — re-read PR #256 now: both decisions (`swap-place`, `spec`) are recorded with `[x]`, the swap removal (b479be2) and merge (f7b277b8) already happened, and nothing has acted on the `spec` decision yet. Confirmed current.
- Added check of my own: I verified the spec table's claims against the actual branch code (not just the PR description's prose), since a table built from the description alone could repeat an inaccuracy the description already had.

## Decisions

None needed from the owner on *this* ticket's plan — the owner already made the one decision this ticket acts on ("Yes: one table... as a ticket for you to approve"). The new spec ticket I file will itself carry a Decisions section (per `docs/agents/decisions-format.md`) asking him to approve, amend, or hold the table — that's the mechanism, not a prose question from me.

## Task List

1. Write the spec table body (one Markdown table, columns: Case · Trigger · What's built today (file:line) · What the owner sees · Open question) covering exactly the cases the owner named — a pick that downloads, stalls, or fails; same language on both sides; face to face; a change while captioning — grounded in the code read above (`CaptionLanguageSwitch`, `SpeechDownload`, `TranslationCenter.passThrough`/`passThroughReverse`, `CaptionLanguageCenter.set`), citing #37, #53, ADR 0031, #245, #251, #252 where each rule currently lives.
2. In that same table, include the two undocumented gaps found above (cross-instance double-download race; mid-session From change not live) as open rows rather than presenting them as solved.
3. File the table as a new GitHub issue (`gh issue create --repo G-Eskayo/clarity-captions`), titled to name both source tickets (e.g. "Spec: From/Into behavior in every case (owner's Decision on #256)"), labelled `needs-info` + `feature:translation` (matching #251/#252's label), body ending with a `<!-- marvin:decisions -->` block offering: approve as written / amend (text) / hold until #251 (readiness) lands first. Body links PR #256 and issue #252.
4. Reply on PR #256 with the `<!-- marvin:decisions-addressed -->` marker: record the `spec` decision as acted on, link the new ticket number from step 3, state plainly that no commit was made (this decision produces a ticket, not app code) and that screenshots don't apply (no change to how the app looks).
5. No `swift test` run, no app build, no screenshot capture for this ticket — stated in both the new ticket and the PR reply, consistent with step's absence of code change.