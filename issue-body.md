## From/Into Behavior Specification

Comprehensive behavior table for caption language (From) and translation language (Into) picks in all scenarios, pending owner approval before further changes.

**Related:** #37, #53, #245, #251, #252, PR #256, ADR 0031.

## Behavior Table

### From (Caption Language) Picks

| Scenario | Current Behavior | From Row Display | Into List | Notes |
|----------|------------------|------------------|-----------|-------|
| **Pick an installed language** (files already on device) | Language switches immediately | Language name only | Filtered or full based on Translation state | Normal case; no download needed |
| **Pick a not-yet-installed language** (speech model not present) | Download starts; old language stays until complete | `<Language> · downloading 0%` → progress climbs → `<Language>` | Filtered or full based on Translation state | From shows real download progress; Into follows whatever filter rule applies |
| **Download stalls / fails** | Download fails; reverts to the previous From language | Shows error message and previous language name | Filtered or full based on Translation state | User must pick a working language or retry; error is clear |
| **Pick a language while one is downloading** (supersede) | Previous download is cancelled; new download starts | `<New Language> · downloading 0%` (old language abandoned) | Filtered or full based on Translation state | No ambiguity about which language is "active"; the newest pick is authoritative |
| **Change From while captioning is running** | **Not specified — owner's decision** | Depends on decision below | Depends on decision below | **Owner question:** Should the From language switch take effect immediately mid-session (with background download), or require pausing captioning first? |

### Into (Translation Target Language) Picks

| Scenario | Current Behavior | Into Row Display | Can pick equal From? | Notes |
|----------|------------------|------------------|----------------------|-------|
| **Pick an installed translation pair** (From→Into is ready on device) | Language switches immediately | Language name only | Yes (same language allowed) | Normal case; no download needed; ADR 0031 #252 decision |
| **Pick a not-yet-downloadable pair** (Apple doesn't offer this pair, or requires newer OS) | Pick is disabled / marked as unavailable (after #251 is built) | Language name + reason (e.g., "Needs iOS 27") | N/A (can't pick) | Readiness model (#251) determines availability; Into list only offers ready pairs |
| **Pick a language equal to From** (From = Into) | Translation is skipped for that language; each caption line passes through with no translation | Language name (same as From row) | Yes (same language allowed) | Per owner decision #252; `TranslationCenter` treats same-language as identity transform |
| **Change Into while captioning is running** | **Not specified — owner's decision** | Depends on decision below | Yes (same language allowed) | **Owner question:** Should Into language switch take effect immediately on the next caption line, or require pausing captioning first? |
| **Delete / uninstall an Into language** | Language is removed from "Your languages" list; if last language, deletion is blocked (ADR 0031 §3); otherwise app reverts Into to a remaining language | Previous Into language (one of the remaining, or error if last) | Depends on what's left | Tied to #251 (Readiness) and Settings work (#221); at least one must stay while translation is owned |

### Interaction Cases

| Case | From Pick | Into Pick | Caption Behavior | User Experience |
|------|-----------|-----------|------------------|-----------------|
| **Same language on both sides** | User picks From; Into picks same language manually | Both show identical language | Each caption line passes through untranslated (identity), with no audio translation | "You see English, you hear English" — valid use case (owner decision #252); ear voice speaks the captioned language |
| **From picks during active captioning** | From changes to language with uninstalled speech model | Download bar shows; captioning doesn't stop | Captions switch to new From language once download completes | User keeps hearing caption stream; no silence or "stall" |
| **Into picks during active captioning** | N/A (Into picks don't change caption source) | Into changes to new translation language | Each new caption line appears in new Into language, old lines unchanged | Seamless; no delay or notification needed |
| **From download fails during captioning** | Download fails; From reverts to previous language | Previous language name; error visible in Settings | Captioning continues with previous From language | Clear error in Settings; next caption line uses fallback |
| **Face to face split, both halves**  | Each half can have its own From (caption language) | Each half can have its own Into language | Each half captions and translates independently | Both From and Into are settable before split opens; all downloads happen in Settings only (owner's standing rule) |
| **One side of face to face has no ready translation pair** | N/A (settings pre-check #245) | N/A (settings pre-check #245) | Feature doesn't open / shows "can't translate this pair" | #245 and #251 (readiness) prevent split from starting in bad state |
| **One pick fires two installs of the same locale** | **Bug, not fixed** — iPad log in #252 comments; `SpeechDownload` claims single-flight but a second caller slips through | Undefined (both fire?) | Undefined | Needs a separate bug ticket, not part of this spec |
| **Apple's asset server never starts the download** | **Not yet handled** — no watchdog message surfaced to the From row today | N/A (no progress shown) | N/A (blocked?) | Needs building; if Apple doesn't start, current code gives no feedback |
| **Translation pair needs downloading** | **Planned behavior (after #251):** Apple's sheet, indeterminate progress | Language name + "Downloading, Apple shows progress" | Yes (same language allowed) | Per #251 readiness; Into list shows readiness state once #251 is built |
| **Mac call translation (one-way)** | N/A (Mac uses device's caption language) | One-way translation uses Into from Settings | Mac side sees captions in Into language | Simplest case; Into is just the fixed user's chosen language |

---

## Decisions

<!-- marvin:decisions -->

### same-language-display: When From and Into are the same language, show the duplicate translated line, or hide it?
- [ ] Show: the translated line stays under the original, even though it repeats it (current build)
- [ ] Hide: when From and Into match, show one line, no repeat

### spec-approve: Approve this behavior table as the spec for From/Into, or does it need changes first?
- [ ] Approve: build against this table
- [ ] Needs changes: use the note to say what

<!-- /marvin:decisions -->

---

## Implementation Notes (for later reference, not a task list)

- **Readiness model (#251):** determines which languages are downloadable/installed/unsupported; feeds Into list filtering.
- **Into list filtering:** after #251, Into offers only ready languages. Same-language pairs (From = Into) are allowed and don't error.
- **Download progress display:** From row shows download % while in progress (#256 implements this).
- **No feature-initiated downloads:** owner's standing rule; all downloads happen in Settings only. No downloads during face-to-face setup — Settings is the sole entry point.
- **Superseded picks:** when user picks a new From before the old one finishes downloading, the old download is cancelled without ambiguity.
- **Face to face pre-check:** #245 ensures both halves have ready From/Into pairs before split opens.

---

## Acceptance (Owner)

- [ ] This table covers all the edge cases you expect
- [ ] The same-language-display and spec-approve decisions match your intent from PR #256
- [ ] Any additions or corrections before this is marked ready for code?
