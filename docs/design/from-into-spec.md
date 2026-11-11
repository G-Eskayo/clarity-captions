# From and Into: Language Selection Spec

Owner decisions, approved 2026-11-10. Every case the From and Into controls show in Settings, and how they behave in every state (captioning running, downloading, failed, edge cases). The builder implements this exactly before any other From/Into behavior is built.

## Overview

**From** (caption language): the language people around her are speaking. Apple's speech engine is told this up front and doesn't detect it, so it's chosen, never guessed (#37).

**Into** (translation target): the language captions are translated into (#53). Lives only when translation is bought and turned on, with the language Apple's Translation has for the pair.

Both are changed in Settings, each from its own list. No swap button (#252, owner decision: Neither).

## From: Caption Language

### Table: From Cases

| State | What the row shows | Download starts | Progress shown | On tap | After download | Failed download |
|-------|-------------------|-----------------|-----------------|--------|-----------------|-----------------|
| **Installed, current** | `French (France)` | — | — | Tapping does nothing; already current | — | — |
| **Installed, not current** | `English (US)` | — | — | Switches to it, no download | — | — |
| **Not installed (pick for first time)** | `Spanish (Spain)` | Yes | `Spanish (Spain) · downloading 0%` → progress climbs → `Spanish (Spain) · downloading 100%` → `Spanish (Spain)` | Taps a download-pending language. **Target rule (not yet built):** newest pick wins; same language tapped twice is a single choice, progress from 0%. **Current behavior:** #252 bug may start duplicate downloads. | Captions switch to it. Old captions stay in their language. | Reverts: captions stay in current language. Row shows current, not the failed pick. `SpeechDownload` says why (connection lost, space, etc.), once, to Settings (#51, #243). |
| **Not installed (pick while another is downloading)** | `German (Germany)` | Yes | `German (Germany) · downloading 0%` → progress climbs | Replaces the old download; old language's progress is forgotten | Captions switch to new language. | New download fails; behavior is decided in Decisions section (see face-to-face-recover-failed) |
| **Stalled (no progress for 90 ticks)** | `French (France) · downloading 40%` | Already running | `downloading 40%` with the watchdog message from `SpeechDownload` (connection lost, space, etc., #51, #243) | Stays on screen, no new action | If it resumes, progress climbs from here (`max(shown, new)` #37) | If it times out after stalling, follows Failed above |

### From: While Captioning Is Running

**Decision (owner, 2026-11-10):** From cannot be changed while captioning runs. Stop captions first.

- **The control says why:** not greyed out with no explanation. Shows "`Stop captions to change`" when `CaptionState` is `.preparing` or `.listening` (#18).
- **Tapping the From row opens Settings' caption-language list**, which also shows the same "Stop captions to change" message, same wording.
- **Captions stop or pause first:** the user taps Stop, captions stop, then From becomes tapable again.
- **New language's download:** when From is finally tapped (captions stopped), picking a not-installed language starts its download, as shown in the table above.

### From: Known Open Issues

- **#252 (double-download bug):** Tapping the same pending language twice should be a single choice (newest wins, progress goes from 0%). Today it can start two downloads at once. Not fixed by this ticket; use #252.

## Into: Translation Target

### Table: Into Cases

| State | What Into shows | How it got there | Can change mid-caption? | What happens to earlier lines | Download starts | Progress shown |
|-------|-----------------|------------------|------------------------|-------------------------------|-----------------|-----------------|
| **Language installed, current** | `French (France)` ✓ | Already downloaded before Into changed | Yes | Keep their Into language (no translation = same language) | — | — |
| **Language supported by Apple Translation, not downloaded** | `Spanish (Spain) · downloading N%` | Settings opened with translation on, or Into was changed to a language that isn't downloaded yet (#245) | Yes | New lines use new Into language, earlier lines keep theirs (not yet built #340) | `setUpIntoSpeech()` starts it when Into is tapped or Settings opens | Shows real progress |
| **Language not supported on this iOS** | `German (Germany)` Needs iOS 27 | Device can't do this Into language (e.g., iOS 26 doesn't have it). Greyed. | No | — | — | — |

### Into: The List

**Decision (owner, 2026-11-10):** The Into list shows every language Apple's Translation has, except the current caption language (not yet built, see Known Open Gaps).

- **Current behavior (code):** every language Apple's Translation supports except the current caption language. No "only ready pairs" filtering; a language that's not installed yet or greyed due to device limitations is still shown with its true state.
- **What each row shows, in order:**
  1. Installed (not current): `French (France)` (or just the language name, script only where it tells two apart, like Simplified vs. Traditional Chinese)
  2. Current Into (installed, already chosen): `French (France)` ✓
  3. Downloading: `French (France) · downloading N%` (same progress wording as From)
  4. Not downloadable on this device: `German (Germany)` Needs iOS 27 (greyed, reason shown)
- **Planned (not yet built):** The current caption language will be shown in the list, labeled "your language, nothing to translate," with its true state (no download needed; lines show untranslated in that language). See #340 in Known Open Gaps.

### Into: While Captioning Is Running

**Decision (owner, 2026-11-10):** Into can change while captioning runs. New lines translate to the new language; earlier lines keep theirs.

- **Tapping a new Into language is allowed** while `CaptionState` is `.preparing` or `.listening`.
- **New captions (lines that land after the change) translate to the new Into language.**
- **Earlier lines stay as they were:** a line that landed before the change stays translated in its original Into language (or not translated if the old Into was off).
- **Wait for download:** if the new Into isn't installed yet, the new language's download starts (`setUpIntoSpeech()`). Until it's ready, new captions show untranslated (captions only), then switch to translated once the download lands.
- **Not yet built:** `TranslationCenter.setTarget()` today calls `translations.reset()`, which wipes all earlier translations. That would need to change so that earlier lines keep their original translation. Use ticket #340.

## Face to Face

The app has a split-screen mode (#60, #208): the owner reads captions in one half, the other person reads theirs in the other half. Each half picks its own From (what language is being spoken on its side) and Into (what the other person reads).

**Rule (already built, #208):** Nothing translates until both halves have picked. Once both have picked, each line translates one way (the owner reads the other person's language translated into hers; the other person reads the owner's language translated into theirs).

**Open question: face-to-face and readiness (see Decisions section below.)**

## Known Open Gaps (Not Fixed by This Ticket)

1. **#252: Double-download bug.** Tapping the same pending From language twice. Should be a single choice; instead, two downloads can run at once. Flagged in the From table above. Use ticket #252.

2. **#340: Same language on both sides (not yet built).** When From = Into (e.g., both English), the Into list should include the caption language labeled "your language, nothing to translate," and lines should show untranslated in that language. Currently `TranslationTargetList.rows()` (line 219) filters out the caption language, so it never appears in the list. The code needs to change to include it and `TranslationCenter` must handle the edge case of translating a language into itself. Use ticket #340.

3. **#340: Into change while captioning (not yet built).** Changing Into while captioning runs should leave earlier lines' translations alone. Currently `TranslationCenter.setTarget()` calls `translations.reset()`, which wipes them all. The code and the spec contradict; the spec is the decision. Use ticket #340.

4. **Face-to-face readiness conflict (see Decisions section below):** #245 (built) lets tapping a not-ready language in the split start its download. #251 (not yet built) says no feature should ever start a download. The face-to-face rule (described above) is decided: nothing translates until both halves pick. The open question is whether the readiness shown in each half follows #245's "tap to download" or #251's "Settings only" rule. Clarify before fixing face-to-face's behavior.

## Decisions

<!-- marvin:decisions -->

### from-download-recover: From: What happens when a new download fails and replaces an old one?

From the From table: when a user picks language A (starts downloading), then picks language B (replaces it), and B's download fails, what should happen?

- [ ] A: The old language's download starts again from 0%
- [ ] B: The old language stays as current; B's failure is shown, user can tap B again to retry, or pick a different language
- [ ] C: The old language stays as current; B's failure is shown, but B doesn't appear in the list anymore (implicit discard)

> **Note:** This doesn't affect the main From table — the other cases (single pick, stall, installation) are all decided. This is the only recovery case that's open.

### face-to-face-readiness: Face to face and readiness

In face-to-face (#60), when she taps a language in Into (the list the other person reads), there are two rules:

- **#245 (built, 2026-10-XX):** Tapping a not-downloaded language starts its download (the "Into picks can trigger a download" rule).
- **#251 (not yet built, "no feature ever starts a download"):** The language shows greyed with its reason ("Needs iOS 27" or "downloading N%"). Tapping it does nothing; she has to go to Settings to start the download (the "only Settings downloads" rule).

Which rule should the face-to-face Into list follow?

- [ ] A: Keep #245 as built (tapping starts the download) until #251 ships
- [ ] B: Write it to #251's rule now (show readiness only, no tap-triggered download) as a future change to #245
- [ ] Leave it open in this spec and decide it when #251 ships

> **Note:** This doesn't block approving the rest of the From/Into spec — the main cases above (From/Into in one-way translation, while captioning, same language) are all decided.

