# 0031 — Translation keeps the user's own list of languages, at least one while it's owned

## Status

Proposed (2026-10-29, #200). Draft: the owner answers the `translation-delete` and `translation-keep` Decisions on
the design PR first. Extends #53/#171 (one Into language) and #60 (face to face). Design:
`docs/design/smallest-install-and-language-packs.md` §5.

## Context

- The owner (2026-10-29): translation adds size only once bought and added. The user can download, switch, change and
  delete the languages they translate between, and keep more than one so switching is easy. At least one must stay
  while translation is owned.
- Today `TranslationCenter` holds a single `target`.
- Apple's translation languages are system-managed and shared with every app. An app can ask about a pair
  (`LanguageAvailability.status(from:to:)`) and download through Apple's sheet (`prepareTranslation()`), but it
  **can't list or delete them**. The user deletes them in Settings > Apps > Translate (Apple's developer doc and the
  iOS 27 user guide, cited in the design doc).
- Seal's own translation packs (for languages Apple lacks, such as Serbian) would be asset packs Seal can list and
  remove ([[0029]]). On Android, ML Kit's models can be listed and deleted.

## Decision (proposed)

1. **Seal keeps its own list, "Your languages"**, saved on the device. It's the list the user manages, whoever
   holds the files.
2. **Add** downloads (Apple's sheet, or a Seal pack with progress). **Switch** picks the Into language from the list
   with no download. **Delete** removes a Seal pack for real. For an Apple language, delete takes it off Seal's list
   and says in one line where iOS keeps it.
3. **At least one:** while translation is owned, the last language can't be deleted. Buying translation adds the
   default Into language ([[0030]]) to the list.
4. **Seal's own translation packs** are only offered and downloadable once translation is owned.
5. Face to face (#60) and one-way translation use the same list.

## Consequences

- Deleting an Apple language in Seal may free no space, because iOS keeps it until the user deletes it in Settings.
  Seal says so plainly rather than pretend.
- Seal can't show Apple languages' sizes (unreadable from the app). It shows sizes for its own packs only.
- `TranslationCenter.target` becomes the selected item of a list, a CaptionCore value type with the minimum-one rule
  under unit tests.
