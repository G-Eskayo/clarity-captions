1. File the new GitHub issue on `G-Eskayo/clarity-captions` with the title, labels and body above (`gh issue create`, per `docs/agents/issue-tracker.md`'s convention).
2. `gh issue view <N>` to confirm it resolves before referencing it anywhere.
3. Post the reply above on PR #256 with `<!-- marvin:decisions-addressed -->`, substituting the real issue number.
4. Re-check PR #256's description hasn't gained a new commit or reply since step 1 started (stale-state guard) before posting step 3; if it has, stop and say so instead of posting over it.

No Swift files, ADRs, or app code are touched by this ticket.