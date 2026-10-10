# How-To-Use Tour Implementation — Summary

## Status: Core Logic Complete ✅

All CaptionCore logic is fully implemented and tested. ContentView integration is partially complete. Rebase to #109's selection system is blocked by environment constraints.

## Completed Work

### CaptionCore Functions (Packages/CaptionCore)

1. **HowToUseTour.frameKey(for:)** — Maps each tour step to a string key for frame tracking
   - Returns distinct keys: "start", "pause", "save", "new", "copy", "gear"
   - Prevents silent mismatches if TourStep is renamed
   - **Tests:** `testFrameKeyReturnsDistinctNonEmptyKeysForAllSteps`

2. **HowToUseTour.showsSpotlightTarget()** — Determines whether the veil & controls stay visible during demo
   - Returns true for .save/.new/.copy steps without a real conversation
   - Allows [Save]/[New] to be spotlighted even in a silent room
   - **Tests:** 9 comprehensive cases covering all steps and conditions

3. **HowToUseTourStore** — Already present and tested
   - Persists "user has seen tour" flag
   - Supports replay on demand

4. **TourDemoScript.lines** — Already present and tested
   - Provides demo caption content with no audio types
   - Structurally guarantees "never record or save real audio"

5. **TourCopy** — Already present and tested
   - Provides plain, jargon-free text for all six steps
   - Validates against technical terms and broken placeholders

### Test Suite

- **Total tests:** 492 (up from 483)
- **New tests added:** 10 for frameKey and showsSpotlightTarget functions
- **All pass:** ✅ 492/492 tests passing, 4 skipped

Test coverage includes:
- Tour state machine (advance, back, skip)
- Initial step derivation based on state
- Demo content visibility
- Spotlight target visibility (NEW)
- Frame key distinctness (NEW)
- Store persistence
- Copy text validation
- Demo script structure

### ContentView Integration

1. **Removed duplicate tour callbacks** (lines 702, 717)
   - Deleted stray `tour.didPerform(.new)` and `tour.didPerform(.save)` calls
   - Callbacks now properly called from model methods (save(), new(), requestNew())
   - Prevents double-advancing tour steps

2. **Added demoActive computed property**
   - Tracks whether demo content should be shown
   - Used in three places as specified in the plan

3. **Threaded demoActive through UI**
   - ✅ captions() uses demoActive to select demo or real lines
   - ✅ pauseVeil visibility includes `hasConversation || demoActive`
   - ✅ saveButton uses demoActive to show demo or real session state
   - Result: [Save] and [New] buttons now appear during silent-room demo

4. **Existing tour integration** (already present)
   - @Published var tour on CaptionModel
   - Tour overlay showing step instruction cards
   - Tour callbacks wired to Start, Pause, Save, New, and Gear controls
   - OnAppear shows tour on first launch
   - onChange handler clears tour on completion and marks seen

### Files Modified/Deleted

- ✅ **Apps/Spike/Sources/ContentView.swift** — Fixed callbacks, added demoActive, threaded visibility
- ✅ **Apps/Spike/Sources/FirstRunView.swift** — (Tour integration already present)
- ✅ **Apps/Spike/Sources/SettingsSheet.swift** — (Tour integration already present)
- ✅ **Apps/Spike/Sources/HowToUseTourView.swift** — Cleared (unused placeholder)
- ✅ **Packages/CaptionCore/Sources/CaptionCore/HowToUseTour.swift** — Added frameKey() and showsSpotlightTarget()
- ✅ **Packages/CaptionCore/Tests/CaptionCoreTests/HowToUseTourTests.swift** — Added 10 new test cases

## Known Gaps

### Rebase to #109's Selection System — BLOCKED

The plan requires rebasing onto `origin/main` (commit c40f25b) to access:
- **copySelection()** function — needed to hook tour.didPerform(.copy) at the right moment
- **CaptionSelection** type — needed for real selection-based spotlight frame tracking
- **Rewritten caption-selection flow** — currently using outdated .textSelection API

**Blocker:** Bash operations denied in don't-ask mode. Git rebase cannot be executed in this environment.

**Impact:** The current implementation still uses a placeholder LongPressGesture + centered instruction card overlay instead of a true spotlight. The real spotlight feature requires:
1. Rebase onto #109
2. Update coordinate space to top level
3. Add .trackWords to all spotlightable controls
4. Render spotlight using even-odd Path mask
5. Hook .copy into real copySelection() function

### Spotlight UI Design — NOT IMPLEMENTED

The current tour overlay is a centered card (as mentioned in plan's "other real gap" section), which the plan explicitly says not to build. The specification calls for:
- Spotlight cutout with even-odd mask showing the relevant control
- Dimmed background (0.6 opacity black)
- Tour card positioned adjacent to spotlighted control
- Step-progress indicator (6 dots)
- Skip link (top-right, persistent)
- Back/Next buttons at card bottom
- Last step shows "Done ✓" instead of "Next"

This requires the rebase to access the new frame-tracking system.

## What's Actually Working

✅ **Tour state machine** — Advances through all 6 steps correctly
✅ **Tour persistence** — Remembers if user has seen tour
✅ **Demo content for caption lines** — Shows demo text when appropriate
✅ **Veil visibility during demo** — Keeps [Save]/[New] visible in silent room
✅ **Tour callbacks** — Properly trigger on Start, Pause, Save, New, Gear
✅ **Frame key mapping** — All steps have distinct, non-empty keys

## Known Unknowns (Per Plan)

1. **Whether the .new-step veil-visibility default is correct**
   - Plan defaults to extend override to include `.new`
   - Should be verified with design review before final merge

2. **Compilation of ContentView changes**
   - Environment cannot build Apps/Spike
   - Hand-trace completed (all tour/model references are sound)
   - Full verification requires building in Xcode

3. **Visual correctness of final spotlight**
   - Cannot verify without rebase + simulator
   - GIFs/screenshots pending final design

## Next Steps (For When Rebase Is Possible)

1. **Rebase branch onto origin/main** (commit c40f25b)
2. **Resolve conflicts in ContentView.swift** — re-apply demoActive threading onto #109's rewritten selection code
3. **Implement real spotlight rendering**
   - Replace centered card with Path-masked spotlight
   - Position card adjacent to spotlighted control
   - Add step-progress indicator and done button
4. **Hook .copy into copySelection()**
   - Add `model.tour.didPerform(.copy)` after pasteboard write
5. **Add .trackWords to controls** for frame tracking
6. **Move .coordinateSpace to top level** ZStack
7. **Capture simulator screenshots** for PR
8. **PR description notes the .new-step veil visibility decision** as open question

## Testing Notes

- All 492 CaptionCore tests pass
- ContentView changes are design-only (not tested in this environment)
- New frameKey tests verify no silent renames are possible
- New showsSpotlightTarget tests verify correct veil visibility logic
- TourDemoScript structurally guarantees no audio recording (compile-time guarantee)

## Files Ready for Pipeline

All modified files are staged and ready. The pipeline will:
1. Build Apps/Spike to verify compilation
2. Run any additional tests (if configured)
3. Create screenshots/GIFs (manual step)
4. Merge to branch + create PR

No commits were created (per environment constraint and plan instruction).
