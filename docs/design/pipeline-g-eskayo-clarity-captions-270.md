## North-star fit

Reuses the existing *Decisions* reply pattern (`docs/agents/decisions-format.md` → "After the owner answers: it is MARVIN's move", `lib/owner_decisions.py`): a PR is "addressed" by either a commit after the decision comment **or** an owner-account reply carrying `<!-- marvin:decisions-addressed -->`. The owner's chosen option here ("Keep 1.1.0 (10) for the Korea tester; feedback goes through the share sheet or TestFlight's screenshot feedback") requires no code, no new build, and no new screenshots — build 10 already behaves that way today (confirmed: `Beta.xcconfig.local`'s absence at archive time is exactly what makes "Send feedback to Gil" fall back to the share sheet, per PR #267's own "Known gap" note). So the simplest sufficient action is a single PR comment, not a commit — spending no Swift build/test cycle on a decision that changes nothing. It leaves Gil more informed (the loop closes, and the unrelated merge-gate denial is surfaced rather than silently dropped) without taking any choice away from him.

No file in `CaptionCore` or `Apps/Spike` needs to change for this ticket.

## Verification steps (no XCTest applies — nothing in CaptionCore/Spike changes)

Mapped to "How we'll try to break it":

1. **"The notes contradict a chosen option"** — checked: the decision comment's note is `(no notes)`; the single ticked option is unambiguous. No contradiction to flag.
2. **"The PR changed since the decisions"** — checked: a second comment landed *after* the decision ("Denied by dashboard review", `GATE_TESTS_FAILED`, missing source directory `Apps/Spike/Resources/Models/ParakeetUltra`). Traced the cause: that path is gitignored (`.gitignore` line `Apps/Spike/Resources/Models/`) and is only populated by `scripts/fetch-asr-models.sh` (ADR 0025, referenced in `Apps/Spike/project.yml:42`). The merge gate's temp worktree (`mr-merge-gate-89969-…`) never runs that fetch before `xcodegen generate`/`xcodebuild`, so the failure is structural and independent of build 10's content or of this decision — must say so plainly, not guess.
3. Re-confirm, immediately before posting, that no new commit landed on `release/1.1.0-10` and no further comments were added (re-read PR #267 fresh, not from this plan's snapshot).
4. Confirm the only commit on the branch (`a603240`) touches just `Apps/Spike/project.yml` (1 line, version bump) — so "no look change, images stand" is a verified fact, not an assumption. (Already confirmed via `git show a603240 --stat`.)

Untested behavior: none — no runtime/app behavior is being changed by this ticket.

No Decisions section needed: nothing here requires the owner to choose between options — the gate failure has one obvious remedy (fix the gate's model-fetch step) and isn't a product choice.

## Task List

1. Immediately before posting, re-read PR #267's current description and comment list in full (guards against further changes since this plan was drafted).
2. Draft the reply comment for PR #267 containing `<!-- marvin:decisions-addressed -->`, stating:
   - the chosen option is carried out: 1.1.0 (10) stands as the released artifact for the Korea tester; no new build/upload; feedback continues through the share sheet / TestFlight's screenshot feedback, which is already how build 10 behaves;
   - no commit was made (none was needed) and no screenshots were retaken — the PR carries no look-changing content, so there's nothing to re-pin;
   - the separate "Denied by dashboard review" `GATE_TESTS_FAILED` status is unrelated to this decision: it's caused by the merge gate's temp worktree not running `scripts/fetch-asr-models.sh` before building, so `Resources/Models/ParakeetUltra` (gitignored, ADR 0025) is missing — a pipeline/merge-gate defect, not a defect in build 10.
3. Post it with `gh pr comment 267 --repo G-Eskayo/clarity-captions --body-file <tmp>` (no `marvin:decisions` block needed — the comment only reports, it asks nothing new).
4. Surface the merge-gate's missing model-fetch step to Gil as a separate, out-of-repo infra gap (it lives in the pipeline's merge-gate script, not in `clarity-captions`) rather than silently leaving it to keep blocking every future PR that touches `Apps/Spike` — flag, don't fix unilaterally, since it's outside this ticket's scope and this repo.
5. No clarity-captions commit is required to close ticket #270; per `lib/owner_decisions.py`, the marker-bearing reply alone counts as "addressed."