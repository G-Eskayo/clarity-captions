# From and Into: every case

What translation's **From** (the caption language) and **Into** (the language she reads) do in every case, for the
owner to approve before more From/Into behaviour is built (his "spec" answer on PR #256, ticket #279). One target
behaviour per row. **Status** says whether it is built: **Built on main**, **Built in PR #256** (not merged yet), or
**Decided, not built**. Evidence is a file and line, a test or a PR.

Line numbers are for main at `e935b46` and for PR #256 (branch `fix/252-swap-languages`) at `b479be2`. Paths are
short: `App/` is `Apps/Spike/Sources/`, `Core/` is `Packages/CaptionCore/Sources/CaptionCore/`, `Tests/` is
`Packages/CaptionCore/Tests/CaptionCoreTests/`.

Where the behaviour comes from: #37 (caption language), #53 (Into), #245 (Into's speech model, set up in Settings),
#208 (face to face), #252 and PR #256 (same language allowed, From shows its download, no swap button), and the owner's
2026-11-10 decisions in #279 (a change while captioning, and what the Into list shows). The owner's rule over all of
it: languages are set up in Settings beforehand, and nothing in a feature starts a download.

"From" here means one-way translation's caption language. Face to face's two halves pick their own languages
(rows 21 to 23).

| # | Case | Target behaviour | Status | Evidence |
|---|------|------------------|--------|----------|
| 1 | From: pick a language already on the device | From switches at once, with no download. | Built on main | `Core/CaptionLanguage.swift:181`, `App/CaptionLanguageCenter.swift:61`; test `testAnInstalledLanguageSwitchesAtOnceWithNoDownload` |
| 2 | From: pick a language whose speech files aren't on the device | Its download starts there, in Settings. Captions stay in the old language until it finishes, then switch. | Built on main | `Core/CaptionLanguage.swift:182`, `:194`; `App/CaptionLanguageCenter.swift:65-68`; test `testANewLanguageDownloadsFirstAndCaptionsKeepTheOldOneMeanwhile` |
| 3 | From row while that download runs | From reads "French (France) · downloading 40%" from the moment it's tapped, then just "French (France)". | Built in PR #256 | PR #256 `App/SettingsPage.swift:252`, `:287-290`; `Core/CaptionLanguage.swift:194-200`; tests `testAPickDuringADownloadShowsItsProgressThenSettles`, `testOnlyTheNewestPickShows` |
| 4 | Caption language section and page while that download runs | A progress bar and "Downloading French (France) · 40%". | Built on main | `App/CaptionLanguagePage.swift:238-241`; shown at `App/SettingsPage.swift:68` and `App/CaptionLanguagePage.swift:28` |
| 5 | From: the download stalls | After 90 seconds with no forward progress it's abandoned and says "The download stopped moving. Check that Wi-Fi is on and try again." Tapping the language again tries again. | Built on main | `Core/SpeechDownload.swift:68`, `:106-107`, `:16`; `App/CaptionLanguagePage.swift:229-230` |
| 6 | From row after a stalled or failed download | The From row says the download didn't finish and why, as the Caption language section does, not only the old language's name. | Decided, not built (#252, the iPad log comment) | On PR #256 a failed pick shows the language still in use (`Core/CaptionLanguage.swift:200-202`) and the reason appears only in `CaptionLanguageDownloadLine` (`App/CaptionLanguagePage.swift:246-248`) |
| 7 | From: the download fails (offline, or another error) | Nothing changes: captions stay in the language they were in, and the reason is shown. The offline message names the language. | Built on main | `Core/CaptionLanguage.swift:195`; `Core/SpeechDownload.swift:15-17`; test `testAFailedDownloadChangesNothingAndSaysWhy` |
| 8 | From row after a failed pick | From names the language captions are really in. | Built in PR #256 | PR #256 `Core/CaptionLanguage.swift:200-202`; test `testAFailedPickShowsTheLanguageCaptionsAreReallyIn` |
| 9 | From: another pick while a download runs | Only the newest pick counts. An older download's end changes nothing. | Built on main | `Core/CaptionLanguage.swift:192`; test `testOnlyTheNewestChoiceCounts` |
| 10 | From: the current language picked again mid-download | The switch is cancelled. Captions stay as they are. | Built on main | `Core/CaptionLanguage.swift:180`; test `testChoosingTheCurrentLanguageMidDownloadCancelsTheSwitch` |
| 11 | One pick, one download | A pick starts exactly one download of its language, however many callers ask for it. | Decided, not built (#252, the iPad log comment) | Each caller builds its own `SpeechDownload` (`App/CaptionLanguageCenter.swift:65`, `App/TranslationCenter.swift:203`), so its one-at-a-time lock (`Core/SpeechDownload.swift:85`) covers only that one instance |
| 12 | The same language on both sides | Allowed. Into lists the caption language too. Each line shows itself as its translation (and the ear voice speaks it), with nothing asked of Apple, so no "can't be translated" message. | Built in PR #256 | PR #256 `Core/CaptionLanguage.swift:242`, `:53`; `App/TranslationCenter.swift:257`, `:309`; tests `testIntoListsEveryTranslationLanguageIncludingTheOneBeingCaptioned`, `testTheSameLanguageNeedsNoTranslation`. Main still filters it out at `Core/CaptionLanguage.swift:219` |
| 13 | From list while translating | Each language says whether it translates into Into, is captions only (Apple's Translation lacks it), or is "your language, nothing to translate". | Built on main | `Core/CaptionLanguage.swift:113-116`; `App/CaptionLanguagePage.swift:219-223` |
| 14 | Into list: what it lists | Every language, the current one first with a tick. | Built on main for every language Apple's Translation has on this device. Languages it lacks: row 18 | `App/CaptionLanguagePage.swift:110`, `:116-120`; `Core/CaptionLanguage.swift:223-227` |
| 15 | Into list: a language whose pack is on the device, or isn't yet | "On this iPhone" (or iPad), or "Downloads once". | Built on main | `App/CaptionLanguagePage.swift:161-162` |
| 16 | Into list: a language that is downloading | The row shows "· downloading N%", the same words as From (row 3). | Decided, not built (owner, 2026-11-10, #279) | The row's detail has no download state (`App/CaptionLanguagePage.swift:156-167`); progress shows only below Into in Settings (row 19) |
| 17 | Into list: a language Apple can't translate the caption language into | Greyed out and can't be picked, with the reason "can't translate from Spanish yet". | Built on main | `App/CaptionLanguagePage.swift:134`, `:151`, `:163` |
| 18 | Into list: a language this device can't do at all | Listed, greyed out, with the reason (for example "Needs iOS 27"). | Decided, not built (owner, 2026-11-10, #279) | The list is only what `LanguageAvailability().supportedLanguages` returns (`App/CaptionLanguagePage.swift:110`), so these languages never appear |
| 19 | Into picked, its language pack not yet on the device | Settings shows "Downloading the language pack · N%", or "Getting the language pack ready…" while Apple's own sheet runs it with no progress. | Built on main | `App/SettingsPage.swift:269-280` |
| 20 | Into picked, its speech model not on the device | Into's speech model downloads in Settings, with its own line under Into, so face to face never downloads. | Built on main | `App/TranslationCenter.swift:175-212`; `App/SettingsPage.swift:258` |
| 21 | Face to face with fewer than two languages ready | Face to face opens Settings instead, saying "Face to face needs two languages ready on this device. Set them up here first." A language counts as ready when its speech model and its pair's pack are both on the device. | Built on main | `Core/FaceToFaceStatus.swift:18-19`, `:24-33`; `App/SettingsPage.swift:202-204` |
| 22 | Face to face: what a half picks from | Downloaded languages only, without the other half's language. So the two halves are never the same language, and nothing downloads in the split. | Built on main | `Core/FaceToFace.swift:54-58`; `Core/FaceToFaceSplit.swift:47-50` |
| 23 | Face to face: a half picks again while captioning | A different language restarts captions in the new pair. The same language again only closes the list. | Built on main | `Core/FaceToFaceSplit.swift:77-84`; `App/ContentView.swift:373-390` |
| 24 | From changed while captioning | Not allowed: stop first. The From row and the Caption language row say why ("Stop captions to change"), not just greyed out. | Decided, not built (owner, 2026-11-10, #279) | Settings opens over running captions (`Core/OneScreen.swift:46-49` only changes the screen), and `choose` has no captioning check (`App/CaptionLanguageCenter.swift:58`) |
| 25 | Into changed while captioning | Allowed. New lines are translated into the new language. Earlier lines keep the translation they had. | Decided, not built (owner, 2026-11-10, #279) | `setTarget` drops every translation (`App/TranslationCenter.swift:178`), so earlier lines are translated again into the new language |
| 26 | A swap button between From and Into | None. From and Into are changed one at a time, each from its own list. | Built in PR #256 | Commit `b479be2` (owner's "Neither" on PR #256) |
| 27 | On the Mac | No From or Into: the Translate captions and Caption language sections are iPhone and iPad only. The Mac captions in US English, or Hebrew when the Mac's first language is Hebrew. | Built on main | `App/SettingsPage.swift:52-53`, `:65-66`; `Core/CaptionLanguage.swift:234-240` |

## Not covered

Nobody has decided these yet. Each one needs the owner before it's built.

- **A From download that finishes while captions run** (picked before Start). Does the switch wait for the next
  Start? Row 24 covers picking during captioning, not a download that was already running.
- **The From row's words for a stall** (row 6): the Caption language section's existing line, or the iPad log
  comment's "Apple's download hasn't started. Check the Wi-Fi or VPN, or try again".
- **Every reason a device can't do a language** (row 18), beyond the "Needs iOS 27" example.
- **From = Into on screen:** whether the duplicate line is hidden when both sides match (PR #256, "Owner to try",
  step 3).
- **Into once "Your languages" exists:** how this list relates to the kept list proposed in ADR 0031. That ADR is
  still proposed, so nothing here depends on it.
