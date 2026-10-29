# What Seal does on a right-to-left phone today

- **Source:** our own run, iPhone 17 simulator (iOS 26), Debug build of `c04a131`, 2026-10-29 (#200, PR #205):
  `-AppleLanguages (he) -AppleLocale he_IL`, and Xcode's right-to-left pseudolanguage
  (`-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES`), ten screens each, plus a grep of
  `Apps/Spike/Sources` and CaptionCore (audit in `docs/design/smallest-install-and-language-packs.md` §2). Apple's
  guidance: [Right to left (HIG)](https://developer.apple.com/design/human-interface-guidelines/right-to-left),
  [`layoutDirection`](https://developer.apple.com/documentation/swiftui/environmentvalues/layoutdirection).
- **What we took:** a Hebrew phone gets the English app, not mirrored, because Seal has only an English localization;
  only the time format follows the region (24-hour). Forced right-to-left, SwiftUI mirrors almost every screen by
  itself (no hard-coded left/right in the app). What breaks: the bracket buttons (`]Save [`), the caption area
  (follows the app's direction instead of the caption language), selection on right-to-left text (assumes glyphs run
  left to right), text chevrons in English strings, and counted strings (no plural variants, Western digits only).
  The launch seal (a Canvas) never mirrors.
- **Confidence:** Strong for what the simulator showed; Medium for how real Hebrew strings will lay out (bidi on ‹ ›
  and lone chevrons was not seen, because there are no Hebrew strings yet).
- **Drives:** ADR 0030 points 7–10, the right-to-left audit, and Decisions `rtl-*` on PR #205.
- **Public use:** Internal until the Hebrew app ships; then the before/after can be shown.
