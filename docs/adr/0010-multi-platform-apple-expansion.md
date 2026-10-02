# 0010 — Expand to all Apple platforms that can host the app natively, iPhone first

## Status

Proposed (2026-10-02). Extends the scope set in [[0001]] and [[0009]]; does not change either
one's deadline. Needs owner confirmation of the platform list below before any non-iPhone target
is built.

## Context

The project began as an iPhone-only gift (iPhone 17, due live on the App Store 2026-10-25).
On 2026-10-02 the owner widened the goal: once the iPhone app exists, it should extend to every
other device that can host it natively. The reason is the same one behind [[0007]] — the app is
meant for anyone with needs like the primary user's, and people with hearing loss use more than
one device.

Constraints that did not change: the 2026-10-25 date is for **iPhone only**. On-device-only,
no per-user training ([[0008]]), and free forever ([[0007]]) apply to every platform.

## Decision

1. **iPhone ships first and alone against the deadline.** No other platform may take time from the
   iPhone critical path before it is submitted to App Review.
2. **Architecture is shared-core + thin app targets from day one.** Capture, transcription,
   speaker-turn labeling, the caption-stream model, and caption display settings live in a
   platform-agnostic local Swift package. Each platform is a thin target that supplies its own
   UI and audio-session plumbing. This is the only decision here that costs anything on the
   iPhone path, and it is cheap now and expensive to retrofit.
3. **Candidate platforms, in rough expected order**, each to be confirmed individually:
   - iPad — near-free; same SDK, adaptive layout.
   - Mac — native macOS target (not Catalyst unless native proves impractical).
   - Apple Watch — likely a caption *display* companion to the phone, since a watch is a poor
     far-field microphone; whether it transcribes on its own is open.
   - Apple Vision Pro — captions in view is a strong fit; mic and diarization story unverified.
   - Apple TV — no microphone of its own; probably out of scope unless it displays captions from
     another device.
4. **Per-platform feasibility is unverified.** Whether `SpeechAnalyzer`/`SpeechTranscriber` and
   FluidAudio (CoreML, Neural Engine) are available and performant on each platform is checked
   per platform before committing to it, not assumed.

## Consequences

- Build environment must work on both Macs (parity), see the environment note in the repo README
  once written.
- Platform-agnostic core means tests for it run without a device or simulator.
- App Store presence: one app record with multiple platforms (universal purchase) is preferred,
  decided with the naming work in [[0011]].
