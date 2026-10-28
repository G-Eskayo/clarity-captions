# 0027 — The Mac app captions a call by tapping the Mac's sound with a Core Audio process tap

## Status

Accepted (owner, 2026-10-28, draft PR #174 Decisions). For #172 "Mac app: live captions for FaceTime and phone calls".
Extends [[0010]] (all Apple platforms) and the Mac app from #41.

## Context

The owner's mother takes FaceTime calls (and iPhone calls handed to the Mac through Continuity, which play through
FaceTime) on her Mac and needs to read what the other person says. The Mac app from #41 only heard the microphone,
which picks up the call only when it plays through the speakers, and also picks up the room.

macOS offers two ways to hear another app's sound:

- **ScreenCaptureKit** (`SCStream` with audio, `docs/ideas/mac-system-audio-capture-feasibility.md`): needs the full
  "Screen & System Audio Recording" permission and is built around capturing a screen or window.
- **Core Audio process tap** (`CATapDescription` + a private aggregate device, macOS 14.2+): audio only. It needs the
  narrower "System Audio Recording Only" permission (`kTCCServiceAudioCapture`, with `NSAudioCaptureUsageDescription`
  in Info.plist) and can tap chosen processes, apps by bundle ID (macOS 26), or every sound except its own.

## Decision

1. **Use a Core Audio process tap** (`ProcessTapAudioSource` in CaptionCore, behind the `AudioSource` seam the
   microphone also uses). Same engine and caption pipeline as the iPhone app; only where the sound comes from changes.
2. **By default, tap every sound the Mac plays except Seal Speak's own** (owner's choice d2). It needs no guess about
   which FaceTime process renders the far side, and covers Continuity calls, Zoom and the rest. The cost: a video
   playing during a call gets captioned too. FaceTime-only and microphone stay available through
   `defaults write com.gileskayo.captions listenTo facetime|room`, with no control on screen (design A, d1).
3. **Ship through TestFlight for macOS** on the iPhone app's App Store Connect record (same bundle ID, d3). That
   needs App Sandbox: the Release build is sandboxed with hardened runtime; Debug isn't, so screenshots can be written.

## Evidence

On the owner's MacBook Pro (macOS 27.0.1), from inside the app (evidence log E23):
- Tapping an `afplay` of `say` speech: 593,920 frames, the real engine wrote "She sells seashells by the seashore.
  The harbor is calm this morning." exactly; stop took 0.1 s.
- Every sound but our own: same words; sandboxed Release-style build: same words, 594,432 frames.
- The Mac mini's earlier attempt delivered zero frames because the tap ran from a test runner, which macOS never asks
  about. The app must make the request itself.

## Consequences

- The permission belongs to the app: the first Start shows macOS's "System Audio Recording" prompt, and until it is
  allowed the tap delivers nothing (no error). The window should say so if no sound arrives (follow-up).
- A live FaceTime call and a Continuity phone call are still to be checked by hand.
