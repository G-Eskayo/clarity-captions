# macOS System Audio Capture Feasibility

Out of scope for the Mac companion app v1 (ticket #41), but documented for future expansion to capture system audio (background music, calls, etc.) in addition to microphone input.

## Technical Requirements

- **Framework**: `ScreenCaptureKit` (`SCStream` with `SCStreamConfiguration.audio`)
- **Permission**: macOS "Screen & System Audio Recording" — user-facing TCC prompt, re-triggered after OS updates
- **Entitlement**: `com.apple.security.screen-capture` (required for App Store build, visible in Xcode's Signing & Capabilities)
- **Scope**: Capture is per-app/per-window (e.g., FaceTime, Zoom), not a blanket system mix
- **Blocking**: Some apps (DRM-protected video players) can block their own content from capture
- **Privacy**: Fully on-device, no network access — consistent with ADR 0007

## App Store Review

Justification for review: accessibility use case (same mission as the core app — making speech visible on-screen).

## Verified Working

Per `docs/ideas/v2-and-growth.md:11` — `CaptionCore` package, tests, and FluidAudio diarizer all build and run on macOS 27; adding ScreenCaptureKit stream logic is incremental.
