# Accessibility Audit (2026-10-05)

Automated pass on the app's own UI (ContentView, FirstRunView, SettingsSheet, SpikeApp/RootView), covering Dynamic Type, contrast, Dark Mode, and VoiceOver. This audit complements the existing on-device Accessibility Inspector and VoiceOver testing plan documented in `docs/app-store-compliance.md`.

## Scope

- App screens: portrait and landscape layouts of the main captioning screen (ContentView), first-run onboarding (FirstRunView), look/style picker (SettingsSheet).
- Excluded intentionally: `developerPanel` (dev-only, explicitly non-product per ADR 0013); caption text size control (CaptionTextSize presets A−/A+) and preset-driven color scheme (existing deliberate design per ADR 0013).
- Tool coverage: code review, pure CaptionCore tests; not on-device VoiceOver or Dynamic Type rendering (see "Untested" below).

## Findings and Fixes

### AC1 — Dynamic Type at largest sizes

**Finding:** The Stop circle in portrait (`compactStop` in ContentView) is a fixed 56×56pt frame with an SF Symbol sized via `.title2.bold()`. At accessibility sizes (AX1–AX5), the glyph will outgrow the fixed circle.

**Fix:** Cap the symbol's type scaling with `.dynamicTypeSize(...DynamicTypeSize.xxxLarge)` so it remains legible without clipping the frame. Every other text style (status headlines, buttons, captions, "Jump to latest" button, all of FirstRunView) uses system text styles inside `minHeight`-based or flexible frames, so it grows rather than clips — no fix needed.

**Code change:** ContentView.swift, `compactStop` computed property.

**Intentional non-issue:** `SettingsSheet`'s "Aa" swatches and font-preview text use fixed point sizes as previews of a chosen caption style, not body text — intentional and working as designed.

### AC2 — Contrast in light and dark

**Finding:** The "dim, don't dismiss" non-final caption text uses `opacity(0.6)` applied on screen. At full opacity, every preset passes the AAA bar (7:1 contrast), tested daily via `testEveryPresetIsHighContrast()`. With 0.6 opacity applied, the effective color is an alpha-composite of the text over the background; hand-computing the Paper preset at 0.6 opacity gives ~4.65:1 — above AA (4.5:1) but with thin margin, and nothing currently locks that in. A future preset edit could silently regress below AA.

**Fix:** Add a pure `RGBA.composited(over:)` method in CaptionStyle.swift (alpha-composite helper, no UI framework dependency) and a new test case `testDimmedCaptionStaysHighContrast()` asserting every preset's dimmed text (at opacity 0.6) stays ≥4.5:1 against its background. This makes dimmed-text contrast a testable invariant.

**Code changes:** CaptionStyle.swift (method), CaptionStyleTests.swift (test case).

**Flagged, not auto-fixed:** FirstRunView's error text uses plain `.red` (UIColor). Real contrast against the system background can't be measured headlessly; it's listed here as a specific item for the owner's existing on-device Accessibility Inspector pass rather than guessing a replacement color blind.

**Intentional non-issue:** Dark Mode: `.preferredColorScheme` already follows the chosen caption preset (not the system setting) in both ContentView and SettingsSheet — intentional existing behavior, documented in the code, not a regression.

### AC3 — VoiceOver operates every control and reads state changes

**Existing coverage:** Every interactive control already has an accessible label (`compactStop`, `largeButton`, `settingsButton`, "Jump to latest", SettingsSheet preset/size/font buttons). No additional labels needed.

**Finding:** State changes are never announced. SwiftUI doesn't auto-speak text changes unless the element has VoiceOver focus. Concretely:
- `CaptionState` changes (Ready → Listening → Stopped) in ContentView — no announcement today.
- `FirstRunStep` transitions in FirstRunView — entire screen content swaps, no announcement.

**Fix:**
1. Add a pure `StatusWords.announcement(for:)` method in MainScreen.swift that combines headline + detail (e.g., "Stopped. network error" for a failure).
2. In ContentView, add `.onChange(of: model.state) { UIAccessibility.post(notification: .announcement, argument: StatusWords.announcement(for:)) }` — one line announcing each state transition.
3. In FirstRunView, add `.onChange(of: model.step) { UIAccessibility.post(notification: .screenChanged, argument: FirstRunCopy.for(new).title) }` — one line per step transition (uses existing tested copy).
4. Combine each caption line's speaker label + text with `.accessibilityElement(children: .combine)` so VoiceOver reads "Speaker 1, <text>" in one swipe instead of two.

**Code changes:** MainScreen.swift (announcement method + test), ContentView.swift (state change handler + import UIKit), FirstRunView.swift (step change handler).

**Untested here:** Actual VoiceOver announcement behavior on a real device or simulator — flagged for the owner's existing on-device VoiceOver testing pass.

## Cross-references

- **Dynamic Type, contrast, Dark Mode, VoiceOver on-device pass:** `docs/app-store-compliance.md`, "Self-testing plan" — the owner's existing Accessibility Inspector + manual VoiceOver testing (running on iPhone 17 at iOS 26 and iOS 27) covers actual rendering and announcement behavior that can't be automated headlessly.
- **ADR 0012 (dim, don't dismiss):** rationale for 0.6 opacity on non-final text.
- **ADR 0013 (radical simplicity):** rationale for fixed preset sizes and the intentional exclusion of developer tools from accessibility scope.
- **Caption text size control (CaptionTextSize):** intentionally separate from system Dynamic Type per ADR 0013 — users get a few presets (A−, A+) rather than free-form control.

## What was verified and what remains

**Verified headlessly:**
- Every preset's contrast at full and 0.6 opacity (new test).
- State announcement and step announcement methods (new tests).
- Code structure (pure types in CaptionCore tested; thin SwiftUI layer with one-line handlers).

**Verified on-device (existing plan, not new):**
- Actual Dynamic Type rendering at AX sizes, including the capped Stop circle.
- Real VoiceOver announcements firing.
- FirstRunView red-error-text contrast and readability.
- Dark Mode appearance and color scheme switching.
- All four screen transitions and interactive elements under real VoiceOver.

See `docs/app-store-compliance.md` for the full on-device testing setup.
