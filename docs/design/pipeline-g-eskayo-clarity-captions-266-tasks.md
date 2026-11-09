1. Create/checkout a local branch tracking `origin/fix/252-swap-languages` in this worktree (do not touch `main`).
2. Delete the `LanguageSwap` struct and its doc comment from `Packages/CaptionCore/Sources/CaptionCore/CaptionLanguage.swift`.
3. Delete `Packages/CaptionCore/Tests/CaptionCoreTests/LanguageSwapTests.swift`.
4. Remove `DemoMode.swap` from `Apps/Spike/Sources/DemoMode.swift`.
5. Remove `DemoMode.swap` stub from `Apps/Mac/Sources/IPhoneViewShims.swift` (after confirming no Mac call site reads it).
6. Remove the two `#if DEBUG ... DemoMode.swap ...` blocks and the `swapProposal(systemName:)` helper from `Apps/Spike/Sources/SettingsPage.swift`.
7. `git rm` the four swap screenshots: `swap-a-light.png`, `swap-a-dark.png`, `swap-b-light.png`, `swap-b-dark.png` under `docs/images/pr/fix-252-swap-languages/`.
8. Run `swift test --package-path Packages/CaptionCore`; confirm it's still green (no `LanguageSwap` references left to break the build) and note the pass count change (fewer tests than PR #256's reported 1023, by exactly the removed `LanguageSwapTests` cases).
9. Grep sweep for `LanguageSwap`, `ClarityDemoSwap`, `swapProposal`, `DemoMode.swap` across the repo to confirm zero remaining references.
10. Commit the removal on the branch with a message naming #252/#256 and the owner's decision.
11. Push the branch.
12. Edit PR #256's body "What changed" bullet to say the swap button was removed per the owner's decision (via the gated `gh` wrapper), keeping the existing ticked Decisions section untouched as the record.
13. Post the PR #256 reply with `<!-- marvin:decisions-addressed -->`: what changed, the commit, the screenshot disposition (two stand, four deleted), and the answer to the owner's UX-spec question.
14. Close out ticket #266 once the reply and commit are both in place (it self-closes per the ticket's own filing rule once PR #256 is addressed).