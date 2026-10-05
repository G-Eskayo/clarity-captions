# Issue #23 Implementation Summary

## Overview
Implemented a brand animation moment for waiting states (first-run setup and cold app startup) to replace the pulsing icon + disabled button with a calm, engaging brand mark animation.

## Changes Made

### 1. CaptionCore Package

#### New File: `Packages/CaptionCore/Sources/CaptionCore/BrandMoment.swift`
- **`BrandAnimationGate`**: Controls the duration of brand animations
  - `minimumDuration` (default 0.4s): Ensures animation plays for at least this duration
  - `isFinished(ready:elapsed:)`: Returns true when setup is complete AND minimum duration elapsed
  - `remainingDelay(elapsed:)`: Calculates sleep time to respect minimum duration
  
- **`BrandAnimationPresentation`**: Accessibility-aware presentation mode
  - `.animated`: Smooth breathing animation (default)
  - `.calmStatic`: Static image (when reduce-motion is enabled)
  - `.for(reduceMotion:)`: Factory method to select based on system preference

#### New File: `Packages/CaptionCore/Tests/CaptionCoreTests/BrandMomentTests.swift`
- 8 comprehensive unit tests covering:
  - Minimum duration enforcement
  - Ready/elapsed state combinations
  - Remaining delay calculations
  - Custom duration support
  - Reduce motion presentation logic
- **Status**: All tests passing ✅

### 2. First-Run Flow Updates

#### Modified: `Apps/Spike/Sources/FirstRunView.swift`
**FirstRunModel changes:**
- Removed `sawSetupScreen` flag (no longer needed)
- Added `gate` instance and `setupStartedAt` timestamp
- Updated `refresh()` to:
  - Auto-finish when `.done` is reached
  - Sleep for `gate.remainingDelay()` before finishing
  - Never show the `.done` screen as a tap target
- Removed `.done` case from `primaryTapped()` (no longer needed)

**FirstRunView UI changes:**
- Replaced pulsing SF Symbol with `BrandAnimationView` for `.speechModel` and `.speakerModel` steps
- Kept existing text (title, message) and progress indicators
- Left tap-prompt steps (`.welcome`, `.microphone`) unchanged

### 3. Main-Screen Startup Updates

#### Modified: `Apps/Spike/Sources/ContentView.swift`
**CaptionModel changes:**
- Added `gate` instance and `preparingStartedAt` timestamp
- Updated `start()` to:
  - Record start time when entering `.preparing`
  - Sleep for `gate.remainingDelay()` before transitioning to `.listening`

**ContentView UI changes:**
- Shows full-screen `BrandAnimationView` with "Getting ready…" text during `.preparing` state
- Resumes normal layout once `.listening` begins

### 4. New SwiftUI Component

#### New File: `Apps/Spike/Sources/BrandAnimationView.swift`
- SwiftUI view that displays the brand mark with context-aware animation
- **Accessibility**: Reads `@Environment(\.accessibilityReduceMotion)` to select presentation
- **Animation** (when `reduceMotion=false`):
  - Smooth breathing effect: scale 0.95→1.0 and opacity 0.8→1.0
  - Duration 1.1s, repeats forever with autoreverses
  - Deliberately subtle for older users (ADR 0013)
- **Static** (when `reduceMotion=true`):
  - No animation modifiers applied
  - Same image, no motion
- **Sizing**: Adapts to `verticalSizeClass` (72px compact, 150px regular)
- **Background**: Fills with `Color("LaunchBackground")` for seamless launch screen transition

### 5. Asset Setup

#### New File: `Apps/Spike/Sources/Assets.xcassets/BrandMark.imageset/Contents.json`
- Imageset definition for light and dark appearance variants
- References `icon-light.png` and `icon-dark.png`

#### New File: `setup-brand-assets.sh`
- Setup script to copy icon files into the BrandMark imageset
- Run once after cloning: `bash setup-brand-assets.sh`
- Ensures build has all required image assets

**⚠️ Manual Setup Required:**
The binary PNG files need to be present in `Apps/Spike/Sources/Assets.xcassets/BrandMark.imageset/`:
- `icon-light.png` (from AppIcon.appiconset)
- `icon-dark.png` (from AppIcon.appiconset)

Run `bash setup-brand-assets.sh` from the project root to set these up.

## Acceptance Criteria Coverage

✅ **AC1**: Animation ends when setup is complete, no fixed timer
- `BrandAnimationGate.isFinished()` checks both `ready` flag and elapsed time

✅ **AC2**: Minimum duration prevents flash when ready instantly
- 0.4s default minimum duration, `remainingDelay()` enforces sleep

✅ **AC3**: Reduce Motion setting toggles animation off
- `BrandAnimationPresentation.for(reduceMotion:)` selects `.calmStatic` appropriately

✅ **AC4**: Brand mark scales for portrait/landscape
- `verticalSizeClass` adaptive sizing in `BrandAnimationView`

✅ **AC5**: Animation uses same art as final icon
- Reuses existing `icon-light.png` and `icon-dark.png` in BrandMark imageset

✅ **AC6**: No extra tap after first-run completes
- `FirstRunModel.refresh()` auto-transitions from `.done` without showing it
- No ".Start captioning" button required

## Test Results

```
CaptionCore Package Tests: 69 passed, 1 skipped, 0 failures
├── BrandMomentTests: 8 passed
│   ├── testCustomMinimumDuration ✅
│   ├── testFinishedAfterMinimum ✅
│   ├── testFinishedExactlyAtTheMinimum ✅
│   ├── testNeverFinishedWhileNotReadyRegardlessOfElapsedTime ✅
│   ├── testNotFinishedBeforeMinimumEvenWhenReady ✅
│   ├── testPresentationBasedOnReduceMotion ✅
│   ├── testRemainingDelayCountsDown ✅
│   └── testRemainingDelayNeverNegative ✅
└── [All other tests remain passing]
```

## Behavior Changes

### First-Run Flow
- **Before**: Users see setup screens, then a `.done` tap screen, then main app
- **After**: Users see setup screens with brand animation, then go straight to main app
- **Result**: One fewer tap, smoother progression

### App Startup
- **Before**: Tap "Start captions" → immediate show of empty captions area (if ready quickly)
- **After**: Tap "Start captions" → 0.4s+ brand animation → then listening captions
- **Result**: Branded moment, no jarring instant transitions

## Notes

### What's Untested in This Environment
- Visual animation smoothness and frame rate
- Dark/light mode asset rendering
- Reduce Motion system setting on actual device
- Portrait/landscape layout transitions
- Actual user perception of timing and feel

These would require real device/simulator testing before ship.

### Unchanged
- No changes to signing, bundle IDs, deployment target, or package dependencies
- No changes to ADRs or architectural decisions
- No new network access or telemetry
- `.done` case remains in CaptionCore (still a valid terminal state for logic), only hidden in UI
