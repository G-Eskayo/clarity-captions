## North-star fit

- **Reuses before adding anything new:** `MacTranslation`/`MacAudioSide`/`CaptionLanguageStore.callLanguage`/`TranslationPurchase.macProductID` (`Packages/CaptionCore/Sources/CaptionCore/MacTranslation.swift`, `origin/feature/213-mac-call-translation`) and `TranslationMockup.swift` (`Apps/Mac/Sources/TranslationMockup.swift`, same branch) already implement and already screenshot exactly what the owner approved — 13 green `MacTranslationTests`, demo data that already shows `name: "You"` on the user's own line and `Room`/`Calls` rows in `SettingsPage`. None of that needs to be rewritten. For the one open design question, I reuse the exact `<!-- marvin:decisions -->` block syntax already proven on this same PR (comment `6517778806`), and point at `FaceToFaceLanguages.swift`'s `SpeakerLanguages`/`LanguagePair`/`VoiceRouter` (#60, already shipped) as the one existing pattern that could ever answer "multiple languages in one audio stream" — instead of inventing a new mechanism.
- **Simplest sufficient approach:** no new Swift behavior is required to carry out "look" and "you‑label" and the "from-labels" *label text* — they're already built, on a branch, unmerged. The only mechanical work is rebuilding PR #231 on current `main` (its own comment already asked for this: "once #239 is in main, rebuild this PR's own commits on current main"). I checked: `main` has moved 34 commits past the feature branch's base, but only one (`4f14de8`, Hebrew captions) touches any file in scope, and it's additive (new `MacCaptionLanguage` enum) — no real conflict expected. The one thing that *does* need a human choice (what happens when a room or a call has more than one spoken language) gets a Decisions block, not a guess, per ADR 0013 and the ticket's own rule.
- **Where it spends/saves tokens:** cheap — a git cherry-pick/rebuild plus one PR comment, no new architecture, no new dependency, no device testing attempted.
- **User capability:** unblocks a PR that's been sitting un-acted-on since 2026-10-30 (now recycled ~9 times on unrelated infra/rate-limit failures per the issue's comment history) and gives the owner a clean choice on the one real open question instead of a silent guess, so he stays in control of the harder trade-off.

## What's actually true about the three decisions (checked against code, not assumed)

| Decision | Chosen | Already true in code? |
|---|---|---|
| **look** | Approve as shown, go ahead and wire it | Mock-up (`TranslationMockup.swift`) and `CallPopupView.Line.translation`/`SettingsPage` Room/Calls rows already match the approved screenshots. Nothing to change. |
| **from-labels** (label text) | Room / Calls (as shown) | Already implemented in `SettingsPage.swift` + the mock-up. Nothing to change. |
| **from-labels** (behavior note) | *"Figure out what to do"* — not a choice yet | **Open.** Current `MacTranslation` gives the room and the call exactly one "From" language each (Apple's engine can't detect language, so it must be told one). A room or a call with more than one spoken language — the owner's own example — breaks that assumption. Needs a Decisions block (below). |
| **you-label** | Yes, "You" | Already the mock-up's answer (`CallPopupMockup`/`TranslationMockup` hard-codes `name: String(localized: "You")` for the owner's own line). **Not wired into live captions**, and can't be yet: today's live `CaptionMacModel.popupLines` only tags lines with a diarizer speaker number, never a `MacAudioSide`. Knowing a line is "yours" requires the "two streams, not one" work PR #231 itself lists as **not wired yet** — out of #243's scope (see below). |

So carrying out the decisions is mostly confirming nothing needs to change, rebuilding the branch so that confirmation is actually mergeable, and answering the one open note properly instead of guessing.

## Decisions

<!-- marvin:decisions -->
### room-call-multi-language: A room or a call with more than one spoken language — what should happen?
Today `MacTranslation` gives the room one From language and the call one From language (Apple's speech engine can't detect a language, so it has to be told one, E27). The owner's own example — a Spanish speaker and an English speaker in the room, calling a French speaker — has three languages across two sides, which the current one-language-per-side model can't represent.
- [ ] **Ship the limit as-is for #213.** Room and Calls each stay a single From language; picking the one that's currently right and switching manually (already possible today) is the answer for a mixed room or call. Add one plain line of text under the Room/Calls rows saying only one language plays at a time there, so a second language is seen to garble rather than silently mistranslate (ADR 0012, dim don't dismiss).
- [ ] **File a follow-up ticket to extend the room to several simultaneous languages**, reusing the Face to Face per-voice language-matching already shipped for #60 (`SpeakerLanguages`/`LanguagePair`/`VoiceRouter` in `FaceToFaceLanguages.swift`): each voice in the room is matched to one of several room languages instead of the room having one language. Real engineering (more than one engine running on the room's audio, more CPU/battery); scoped separately from #213, not attempted here.
- [ ] **Same as above, but for calls too** — a multi-language call (e.g. two people on the same Zoom call speaking different languages) gets the same per-voice treatment, not just the room.
> Note: the owner's example only needs this for the room (Spanish + English sitting together); the call side in his example is single-language (French). Option 3 is only needed if a single call can itself carry more than one language, which he also raised ("multiple different languages on the same call").
<!-- /marvin:decisions -->

## Tests (none new — stated, not guessed)

The ticket's two misuse cases, checked now rather than assumed:
1. **"The notes contradict a chosen option"** — checked: the from-labels note doesn't contradict the chosen label text (`Room`/`Calls` stands); it raises a separate behavior question, answered above via Decisions rather than folded silently into the label choice.
2. **"The PR changed since the decisions"** — checked: `git log origin/feature/213-mac-call-translation..HEAD` shows 34 commits, only `4f14de8` touches files in scope, and it's additive. Re-check this again immediately before cherry-picking (main moves daily).

Additional misuse, per the general list:
- **Malformed Decisions block:** reused the exact `<!-- marvin:decisions -->` syntax already parsed successfully on this PR — not inventing new syntax.
- **Dependency failing:** `gh` auth/rate-limit when posting the reply; the Spike-app build hitting the same "missing `Resources/Models/ParakeetUltra`" failure that stalled 3 earlier attempts on this ticket — if it recurs, say so plainly as a pre-existing infra gap, don't silently skip verify.
- **Repeats/idempotency:** this ticket has recycled ~9 times already (3 build crashes, 1 unchanged-verdict, 5 weekly-limit releases) — before posting, check PR #231's comments for an existing `<!-- marvin:decisions-addressed -->` reply so a retry doesn't double-post.
- **Stale state / wrong history:** cherry-pick only the two #213-specific commits (`81113d8`, `67f506f`) from the feature branch, not the whole branch — its own PR body warns its history still carries #230's old commits that conflict with `main`'s `ci.yml`.
- **A person's mistake:** before claiming "the look didn't change, so the images stand," diff `SettingsPage.swift`/`CallPopupView.swift`/`LanguageSettingsState+Mac.swift` between the feature branch's merge-base and current `main` — done above, confirmed no look-affecting change — and re-confirm after the actual cherry-pick resolves any conflict.
- **No new Swift tests needed:** no new behavior is introduced; the existing 13 `MacTranslationTests` plus the full `CaptionCore` suite are the regression check that the rebuild didn't change anything. `swift test --package-path Packages/CaptionCore` and the Mac/iOS builds must still pass after the rebuild.

Time/space complexity: unaffected — no new algorithmic code, only a one-time git rebuild.

## Task List

1. Re-fetch PR #231 and re-check its comments for an existing `<!-- marvin:decisions-addressed -->` reply (idempotency) and re-diff `origin/feature/213-mac-call-translation..main` for any new conflicting commits since this plan was written.
2. On a fresh branch off current `main`, cherry-pick `81113d8` (`MacTranslation`, `MacAudioSide`, `TranslationPurchase.macProductID`, `CaptionLanguageStore.callLanguage`) and `67f506f` (`TranslationMockup.swift`, `CallPopupView.Line.translation`, `SettingsPage`/`LanguageSettings` Room/Calls rows), resolving any conflicts against `main`'s intervening Hebrew (`4f14de8`) changes.
3. Run `swift test --package-path Packages/CaptionCore`; confirm all tests green including the 13 `MacTranslationTests`, and run the Mac app build and the iOS Simulator Spike-app build (watching specifically for the earlier "missing `Resources/Models/ParakeetUltra`" failure; report plainly if it recurs rather than retry silently).
4. Diff the rebuilt `SettingsPage.swift`/`CallPopupView.swift` against the originally-approved commits to confirm no pixel-affecting change; if confirmed, no new screenshots are needed — the pinned images on PR #231 stand.
5. Push the rebuilt branch to update PR #231 (replacing its stale, #230-tainted history per the PR's own request), and confirm the PR diff now shows a clean, mergeable set of #213 commits on top of current `main`.
6. Post one PR comment on #231 carrying `<!-- marvin:decisions-addressed -->`: confirm "look" and the "from-labels" label text are carried out unchanged (images stand); confirm "you-label" is already the mock-up's answer but can't be wired into live captions without the still-unbuilt two-stream `MacAudioSide`-per-line work (tracked under #213, out of #243's scope — say so plainly); answer the "from-labels" behavior note with the `room-call-multi-language` Decisions block above instead of guessing.
7. State explicitly, in both the PR reply and this ticket's closing note, that the "Not wired yet" items from PR #231 (two streams, one translation path, the Mac's StoreKit purchase, a real FaceTime/Zoom call test) remain #213's own future work — owner-gated (new architecture, an Apple-side StoreKit product, device testing this agent can't run) — and are not attempted in #243.