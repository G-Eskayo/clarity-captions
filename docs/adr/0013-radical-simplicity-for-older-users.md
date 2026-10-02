# 0013 — Radical simplicity: usable by an older person with no instructions

## Status

Accepted (2026-10-02), as a product principle. Specific screens are designed against it later.

## Context

The first user is the owner's mother, and the app is meant for anyone with similar needs ([[0007]]).
The owner stated the bar directly: simple enough for an old person, minimal buttons, highly
intuitive, super easy to use. This is a hard constraint on every screen, not a polish goal.

## Decision

1. **One obvious action.** Opening the app should lead to captions with as little as a single tap
   (or none). A person should never have to choose between modes, models, or technical options.
2. **No technical choices in the product.** Mic modes, diarization settings, and similar are
   spike-only measurement tools. The shipping app picks one tested default, or adapts
   automatically.
3. **Settings stay minimal and live behind one clearly labeled place**, and consist of caption
   display only ([[CONTEXT]]: background color, text size, text color, font), ideally as a few
   presets rather than free-form controls.
4. **State is always plain language.** What the app is doing ("Listening", "I can't hear anything",
   "Stopped — tap to restart") is shown in words large enough to read at a glance. A frozen screen
   must never look like a crash.
5. **Setup follows the Delight principle** and is a short guided first run, not a settings form.
6. **Test against it with a real older user** (the intended recipient) before submission, not
   only against a checklist.

## Consequences

- Every added control needs a justification against this ADR.
- It sits in tension with the possible "noisy place" toggle from [[0012]]; the first answer to try
  is making it automatic or removing it, not adding a button.
- Accessibility of the app's own UI (Dynamic Type, contrast, VoiceOver) is part of the same bar,
  and is also an App Store compliance requirement.
