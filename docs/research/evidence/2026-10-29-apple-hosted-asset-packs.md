# Apple-hosted asset packs, and what apps can't manage

- **Source:** Apple's docs, read 2026-10-29: [Creating managed asset packs](https://developer.apple.com/documentation/backgroundassets/creating-managed-asset-packs),
  [AssetPackManager](https://developer.apple.com/documentation/backgroundassets/assetpackmanager),
  [Apple-hosted asset pack size limits](https://developer.apple.com/help/app-store-connect/reference/apple-hosted-asset-pack-size-limits),
  [WWDC25 325](https://developer.apple.com/videos/play/wwdc2025/325/),
  [Translating text within your app](https://developer.apple.com/documentation/translation/translating-text-within-your-app),
  [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory). Google's counterpart:
  [Play Asset Delivery](https://developer.android.com/guide/playcore/asset-delivery),
  [ML Kit translation](https://developers.google.com/ml-kit/language/translation/android).
- **What we took:** from iOS 26.0, an app can ship models as Apple-hosted packs that download at install, after
  install or on request. The app can track and remove them, and they update without an app update (200 GB free per
  app). Apple's translation and speech assets are system-managed and shared: an app can ask about a language but
  can't list or delete translation languages. ML Kit's are per app and deletable.
- **Confidence:** Strong (official documentation). Unconfirmed: cellular behaviour and integrity checks of packs.
- **Drives:** ADRs 0029 (packs) and 0031 (the user's translation list, deleting Apple languages honestly).
- **Public use:** Internal.
