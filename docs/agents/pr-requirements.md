# Pull request requirements

These apply to every pull request on this repo, including the ones the MARVIN ticket pipeline opens.

## Anything that changes how the app looks must include screenshots

If a change affects what a person sees (layout, colors, text, icons, animations, a new screen), the pull request
**must include screenshots of the real running app** showing the changed screens: portrait and landscape where
both apply, and light and dark where both apply. They should come from actually running the app in a dev
environment, not from reading the code.

- If you cannot capture screenshots in your environment, **say so in the pull request, in plain words, and do
  not claim the visual change was verified.** The owner will treat the change as unverified.
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
