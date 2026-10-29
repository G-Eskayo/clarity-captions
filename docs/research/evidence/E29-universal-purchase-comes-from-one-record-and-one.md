# E29. Universal Purchase comes from one record and one bundle ID

- **Source:** Apple Developer, [Offering universal purchase](https://developer.apple.com/support/universal-purchase/)
  (checked 2026-10-28): a macOS app added to an iOS app's record "uses the same Apple ID (an app identifier), SKU, and
  bundle ID as the iOS app".
- **What we took:** sharing the bundle ID and record is what makes one purchase cover every platform; a different
  bundle ID and record keep them separate.
- **Confidence:** Strong (official documentation).
- **Drives:** ADR 0028 (the Mac sold separately), #176.
- **Public use:** Internal.
