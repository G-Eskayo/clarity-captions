# 0019 — The screen stays awake while captioning; an idle stop (default 5 min) is the one behavior setting

## Status

Accepted (2026-10-06), from the #3 design session. Amends [[0013]] (settings are no longer display-only).

## Context

The phone sits untouched on a table for the whole conversation. With normal iOS auto-lock the screen
dims and locks within minutes, mid-dinner, which defeats the app's one job. Keeping the screen awake
fixes that but means a forgotten session would run, screen on, until the battery dies.

An automatic stop after a stretch of silence bounds that. How long "too quiet" is varies by family and
meal, so the owner wanted it adjustable. [[0013]] limited Settings to caption display only and banned
technical choices; this is a behavior setting, so it needs an explicit exception rather than a quiet
precedent.

## Decision

1. While captioning, the screen does not auto-lock. When captions stop (by the user, by the idle stop,
   or by a failure) normal auto-lock resumes. Brightness is never changed by the app.
2. **Idle stop**: if no speech is captioned for the chosen time, captioning stops on its own and says so
   gently (not as an error), with the Start again button. Wording to be finalised in implementation,
   along the lines of *Captions paused — no one talked for 5 minutes*.
3. Settings gets exactly one behavior choice, as presets: **5 minutes** (default) · 15 minutes ·
   30 minutes · Never. *Never* is available but must never be the default.
4. [[0013]] is amended: Settings hold caption display options plus this single idle-stop choice. Any
   further behavior setting needs its own ADR.

## Consequences

- Captions stay readable for a whole meal without anyone touching the phone.
- Battery drain from a forgotten session is capped at 5 minutes of silence by default.
- *Never* re-opens the overnight-drain risk for anyone who picks it; acceptable as an explicit choice.
- The silence clock should count captioned speech, not raw sound, so a noisy but empty room still stops.
