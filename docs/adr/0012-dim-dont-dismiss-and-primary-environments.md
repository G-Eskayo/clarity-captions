# 0012 — Dim, don't dismiss: background speech is de-emphasized, never silently dropped

## Status

Accepted (2026-10-02). The project owner confirmed the principle; the primary environments below
came from his description of how his mother actually uses Otter today.

## Context

The app has to work "in any environment a deaf person may inhabit." The owner also wants
background noise handled: in a noisy room, captions should not be cluttered by speech the user
doesn't care about. Those two goals conflict. The app has no enrollment ([[0008]]), so it cannot
know whether a voice 5 ft away is the person being talked to or a stranger at the next table, and a
speaker-agnostic noise filter cannot tell a TV from a quiet dinner companion.

Findings from the 2026-10-02 spike (iPhone 17 Pro, `SpeechAnalyzer` + FluidAudio Sortformer):
- A clean two-voice test separated both speakers correctly, so the model and feed path work.
- In a relatively quiet room, two people were told apart and labels were mostly correct.
- Noisy-room behavior has **not yet been measured**. The earlier "Speaker 1 for both" result
  happened with the audio session in `.measurement` mode (system noise/gain processing off), so
  it is not evidence about the model itself.
- The diarizer is capped at 4 speakers and its documentation warns it may miss quiet or distant
  speech.

[[0008]] already recorded the underlying asymmetry for a deaf user: a missed caption is far more
costly than an extra one.

## Decision

1. **Show everything the app hears; never silently drop speech.** Speech judged to be background
   (low level, far, low confidence, or not attributable to a nearby speaker) is shown
   **de-emphasized** — smaller, faded, visually grouped — not removed.
2. **Noise suppression is allowed only as signal-quality help, not as a filter that deletes
   speech.** Whether to use the system's Voice Isolation, and how, is decided by measurement in the
   primary environments, not assumed.
3. **Primary environments, in the owner's words for his mother's actual use of Otter:**
   restaurants, the dinner table, and any sit-down conversation. Design and test for these first:
   phone placed on or near a table, roughly 2–6 people, steady room noise, turn-taking speech with
   some overlap. Far-field "across the room" is secondary; it was the first spike test, not the
   main use.
4. **Out of scope by platform limits, stated so they are not rediscovered:** phone calls (iOS
   does not give third-party apps the far side's audio) and media playback captioning.

## Consequences

- Needs a visible confidence/proximity signal per caption line, which the current spike does not
  have. Tracked as a task, not built here.
- The test plan changes from "across the room" to restaurant-like conditions: noise playback
  plus talkers at a table. See the far-field test task.
- The spike's Raw/Standard/Voice mic picker is a **measurement tool**, not a product feature
  ([[0013]]). One default ships.
