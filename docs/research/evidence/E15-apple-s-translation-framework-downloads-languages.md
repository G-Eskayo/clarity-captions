# E15. Apple's Translation framework downloads languages through a system sheet

- **Source:** Apple, [`TranslationSession`](https://developer.apple.com/documentation/translation/translationsession)
  (`prepareTranslation()` "asks for permission to download translation languages"); [Kodeco, Translation API](https://www.kodeco.com/ios/paths/apple-ai-models/49307459-translation-framework/01-meet-the-translation-api/03).
- **What we took:** a missing language triggers a system download view the app can't restyle; a forum report says it
  sometimes doesn't appear on first use.
- **Confidence:** Strong for the sheet; Weak for the first-use bug.
- **Drives:** ADR 0026; the 1.3 translation design must handle or avoid the sheet (Seal shows no system pop-ups).
- **Public use:** Internal.
