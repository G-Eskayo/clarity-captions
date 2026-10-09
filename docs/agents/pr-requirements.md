# Pull request requirements

These apply to every pull request on this repo, including the ones the MARVIN ticket pipeline opens.

## Anything that changes how the app looks must include screenshots

If a change affects what a person sees (layout, colors, text, icons, animations, a new screen), the pull request
**must include screenshots of the real running app** showing the changed screens: portrait and landscape where
both apply, and light and dark where both apply. They should come from actually running the app in a dev
environment, not from reading the code.

- **No images, no merge.** This is the owner's hard rule (2026-10-09). The dashboard refuses Approve on a PR that
  changes how the app looks and shows no image (code `NO_UI_EVIDENCE`, marvin #374). Saying "screenshots could not
  be captured" is not an alternative: capture them. The Mac Mini can: build for the iOS Simulator with signing off,
  launch with the debug-only demo flags (`-ClarityDemoStatic`, `-ClarityDemoSettings`,
  `-ClarityDemoSettingsSection <id>`), switch with `xcrun simctl ui booted appearance light|dark`, and save with
  `xcrun simctl io booted screenshot`. The MARVIN pipeline does this automatically for its own PRs. If a screen
  can't be reached that way, add a demo flag that reaches it.
- Images must be visible in the PR description itself: an image on the pushed branch
  (`https://github.com/G-Eskayo/clarity-captions/blob/<branch>/<path>?raw=true`) or one dragged into the description.
  A repo-relative path does not render in a PR description.
- Tickets that change the look carry images too (a mock-up or a screenshot of the intended result) before they
  are built, so the owner approves what he can see.
- "N/A" is only acceptable for changes with no visible effect (docs, tests, internal logic).
- Describe, in a sentence per screenshot, what to look at.

## Everything else

- The iOS app must build with the change. State whether the build was run and its result.
- Tests must pass; say how many ran and how many passed.
- Do not claim something is verified unless it was.

## Changes to the live captioning path (starting, running, stopping)

Anything that touches how captioning starts, runs or stops must keep the lifecycle tests passing
(`CaptionSessionControllerTests`) and must add one for any new behavior. Say in the pull request how it was
exercised: pressing Start, Stop and Start again, and a failed start, on a simulator or device. Tests with a
fake engine are required; they are not a substitute for one real run, and the PR must say whether a real run was done.

## Commits name the ticket they advance

Any commit that implements or advances a ticket ends its message with `Refs #N` (or `Closes #N` when it finishes it).
The dashboard's "does work already exist?" check can only see work whose commits cite a ticket number, so work done
by hand without one looks like nothing happened and tickets that are really done stay open and blocked.
