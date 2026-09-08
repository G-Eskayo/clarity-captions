# 0009 — TestFlight as an internal step toward a hard App Store-live date

## Status

Accepted (2026-09-08). Revises [[0001]]'s distribution decision. Amended (2026-09-08, same day):
the project owner confirmed 2026-10-25 means **live on the public App Store**, not TestFlight —
correcting this ADR's original framing, which had treated TestFlight as the deadline milestone
and public submission as a follow-on. That was wrong; recorded below for why it changed.

## Context

[[0001]] chose personal install via the paid Apple Developer Program specifically to *avoid*
App Store review risk against the 2026-10-25 deadline. Two things changed since:

1. The project owner explicitly wants a real public App Store release, confirmed as the actual
   2026-10-25 target, not just a personal install or a TestFlight build.
2. He wants to test the app himself before anyone else does, and bring the intended recipient in
   as a real tester in October — removing the "no pre-release feedback loop" objection the
   earlier design review raised against personal-install-only distribution.

Apple's actual review mechanics (checked 2026-09-08): a new app's first public App Store
submission typically takes 2-5 days from submission to decision. **The real timeline risk is a
rejection/resubmission cycle, not the review itself** — each cycle can add days to weeks. A
due-diligence pass (`docs/app-store-compliance.md`) identified the concrete, checkable
requirements that most commonly cause first-submission rejections, so they can be designed in
from the start rather than discovered at submission time. TestFlight (internal: no review;
external: one ~24-48h beta review) remains valuable as a pre-submission testing step, not as a
replacement for the actual deadline.

## Decision

**Target: public App Store submission with enough buffer before 2026-10-25 to survive one
rejection cycle**, not submission exactly on the deadline. Concretely, working backward from
2026-10-25:

1. **Own testing** (project owner) — as early as a working build exists, via internal TestFlight
   (no review wait).
2. **Her October testing** — via external TestFlight (one ~24-48h beta review), early enough in
   October to leave real time to act on what her testing surfaces.
3. **Public App Store submission — targeted with roughly 10-15 days of buffer before 2026-10-25**,
   specifically to absorb one realistic rejection-and-resubmission cycle without missing the date.
   This means the app needs to be feature-complete, tested by both the owner and her, and passing
   the `docs/app-store-compliance.md` checklist well before the deadline itself — realistically
   by early-to-mid October, not late October.

This is a materially tighter internal schedule than this ADR originally proposed, and tighter
than the independent design review's scope-cut recommendations assumed a soft/flexible date.
Given that, `docs/app-store-compliance.md`'s two items that convert from "should do" to "App Store
compliance gate" — measured battery/thermal behavior, and Dynamic Type/contrast support across
the app's own UI — must be treated as must-ship, not nice-to-have, since Guideline 2.1
(performance) is the single largest rejection category and a rejection there directly threatens
the hard date.

## Consequences

- Requires Apple Developer Program enrollment ([[0001]]) immediately — it blocks every stage
  above, including the earliest internal TestFlight testing, not just the final submission.
- App Store Connect setup (privacy policy hosted and linked, App Privacy questionnaire filled in
  accurately, screenshots, description, accessibility metadata) is now critical-path work, needed
  well before the public submission step, not something to defer.
- The compressed schedule increases pressure on keeping scope cut tightly to what
  `docs/research-existing-resources.md` and the independent design review already identified as
  must-ship (speaker-turn labeling, live captioning, failure/silence handling, caption display
  settings) — there is now less slack to add anything beyond that before the deadline.
- If the 10-15 day buffer gets eaten by development running long, the fallback is *not* to submit
  without buffer — it's to cut remaining scope further, since a rejection with no buffer left
  means missing 2026-10-25 outright.
