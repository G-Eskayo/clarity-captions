# 0030 — The app follows the phone's language; every UI language ships in the app

## Status

Proposed (2026-10-29, #200; right-to-left added the same day after the owner's comment on #200). Draft: the owner
answers the `ui-language`, `ui-text` and `rtl-*` Decisions on the
design PR before this is accepted. Design: `docs/design/smallest-install-and-language-packs.md` §2.

## Context

The owner's direction (2026-10-29): buttons, walkthrough, every screen and Apple's own features (caption engine,
translation) follow the phone's language: German on a German phone, Spanish in Mexico or Spain, Hebrew in Israel, on
every device that has the feature and later on Android ([[0026]], #43).

- All app text is already in String Catalogs (#35). English is 235 strings and 12 KB on disk (measured 2026-10-29,
  `docs/perf/install-size-2026-10-29.md`). A language costs the install kilobytes, not megabytes.
- iOS, iPadOS and macOS pick an app's UI language from the user's preferred-language list, and offer a per-app
  language in Settings once the app has more than one localization (citations in the design doc §2).
- **Region isn't language.** Israel's region holds Hebrew, Arabic and Russian speakers; the US region holds Spanish
  speakers. Choosing by region would put many people in the wrong language.
- The caption language already follows the device when nothing is chosen (#37, `CaptionLanguage.resolve`), and the
  translation target defaults from `Locale.preferredLanguages` (#53).

## Decision (proposed)

1. **Every UI localization ships inside the app.** UI text is never a downloadable pack.
2. **The UI language is the system's choice for this app**: the per-app language if the user set one, otherwise the
   first language in the phone's list that Seal has a translation for, otherwise English. Seal has no language
   setting of its own for the UI; it links to the system's per-app setting instead ([[0013]]: no technical choices
   in the app).
3. **The caption language defaults to the UI language**, then down the phone's language list, to the first one a
   caption engine on this device supports, already installed or not. Only when none match does first run ask (as
   #37 does today). The user can still change it in Settings.
4. **Translation's "Into" defaults to the UI language** when it differs from the caption language, otherwise to the
   next language in the phone's list ([[0031]]).
5. **Region never picks a language.** It's used only for formats (dates, numbers) and to order a language's variants
   (es-MX before es-ES on a Mexican phone).
7. **A right-to-left UI language gets the mirrored app** (owner, #200, 2026-10-29): the layout flips (SwiftUI's
   `layoutDirection` from the system, no flag of ours) and every word is written for that language by a native
   speaker, not translated word for word. The mirrored app only appears once Seal has that localization.
8. **Caption direction follows the caption language, never the UI's.** Each caption line, live or saved, takes its
   direction from its own language; a translation line from the Into language. In face to face (#60, #208) each half
   follows its own language, line by line. Text whose language isn't known (a typed name) follows its own first
   strong character.
9. **Pictures don't mirror by default** (the seal, the Listening light); controls and their chevrons do. The owner
   decides the exceptions (Decision `rtl-seal` on #205).
10. **Numbers, dates and times use the locale's formats**, including plural rules and digits; no counted string is
    built with `String(format:)`.
11. Android follows the same rules through its per-app language support (Android 13+, and AppCompat for older
   versions) when there's an Android app (#43).

## Consequences

- The App Store listing (#39) and the app's languages should go together; a localized listing for an
  untranslated app misleads.
- Every localization needs a native-speaker review (#38's rule) before it ships; machine-only strings don't ship.
- Right-to-left (Hebrew, Arabic) needs the #35 RTL checks for real on every screen, not just the pseudo run. The
  audit in the design doc (§2, right-to-left) lists what doesn't mirror today, by file and line. The measured state
  (2026-10-29, evidence E31): a Hebrew phone gets the English app unmirrored, because Seal has no Hebrew localization;
  the pseudolanguage shows SwiftUI mirrors most screens by itself, except the bracket buttons, the caption area's
  direction, right-to-left selection and the text chevrons.
- The caption area sets its own layout direction from the caption language, so it reads correctly inside either app
  direction. A saved conversation has to keep its caption language for this.
- Unverified: whether Apple's own sheets inside Seal (Translation's download sheet, the microphone prompt) follow
  Seal's per-app language or the phone's. If the phone's, a user with Hebrew set for Seal on an English phone may
  see an English Apple sheet. To check on a phone.
