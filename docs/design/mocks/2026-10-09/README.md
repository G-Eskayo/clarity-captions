# v1 polish mock-ups (2026-10-09), for the owner's approval

Mock-ups of [docs/design/v1-polish-spec.md](../../v1-polish-spec.md), drawn at iPhone 17 Pro size (402×874 pt,
rendered at 3×). They are HTML pictures of the intended design, not the running app. After building, PRs carry real
simulator screenshots. Regenerate with `node src/build.mjs` (it uses the Playwright in `~/.agents/dashboard`).

| Image | What to look at |
|---|---|
| 01-main-captioning.png | Gear top-left (icon only, theme-colored); the small Stop circle at the top middle; captions in the dyslexia-friendly font. Portrait and landscape. |
| 02-paused-save-new.png | After X: Start captions top-middle, captions dimmed, SAVE then NEW stacked under Start. Portrait and landscape. |
| 03-save-animation.png | SAVE → green check box → green SAVED, three frames. NEW doesn't move. |
| 04-dim-cleared-and-back.png | Tap the dim to clear it for scrolling and copying; press and hold on empty space brings it back (proposed). |
| 05-copy.png | Multi-line selection with handles and only a Copy button. |
| 06-themes.png | All six themes (3 light, 3 dark) with computed contrast for text, gear and speaker labels. All text pairs ≥ 7:1. |
| 07-button-styles.png | Flat and gummy buttons: options A, B, C, resting and pressed. |
| 08-settings.png | The whole Settings sheet after cleanup, with the dyslexia font as default, the 30-day note, and "Show how to use Seal". |
| 09-how-to-use-intro.png | Four intro cards with Skip, swipe, page dots and a small try-it demo on each. |

## Choices made in the mock-ups (all changeable)

- **Stop while captioning sits at the top middle.** Start lives there now, and today's control shrinks in place, so
  Stop shrinks where Start was.
- **A small status line** ("Listening" / "Paused") stays under the top row, as today's status headline does.
- **Themes:** the three existing dark themes are kept unchanged (Classic, Bright, Night). Light gets Paper (existing)
  plus two new ones in the icon's palette: **Sea Glass** (#DCEFEA / #0D2F2C) and **Peach** (#FBE8D2 / #2B1A10).
  Light-theme speaker-label and gear colors were darkened to reach ≥ 7:1 (they were about 5.5:1).
- **Gear colors:** Paper #14514B, Sea Glass #0B4842, Peach #6E2E0A, Classic #FFFFFF, Bright #FFE633, Night #9DB8FF.
- **Dyslexia font name in Settings:** "Easy to read" (OpenDyslexic, SIL Open Font License). The name is a proposal.
- **Screens use button style A** so you can see one style in context; image 7 compares all three.
- **The SAVE/NEW buttons** use a white (light themes) or dark-gray (dark themes) flat pill, so they read as secondary
  to Start.
- **Intro:** four cards (Start; pause, Save, New; copy; settings). The last button says "Start using Seal".

## Open questions

- [ ] Button style: A, B or C? (B needs a darker teal for white text; white on brand teal is 3.4:1.)
- [ ] Press and hold on empty space to bring the dim back (image 4): yes?
- [ ] [ NEW ] with unsaved changes: ask first, or clear at once? (Spec proposes ask.)
- [ ] Does an unsaved conversation survive closing the app? (Spec proposes yes, the one current conversation only.)
- [ ] Keep Bright (yellow on black), or swap it for a softer dark theme?
- [ ] Theme names Sea Glass and Peach, and the font name "Easy to read": OK?
- [ ] Stop circle at the top middle while captioning: OK?
- [ ] Launch-animation hand-off (what the seal turns into) is not in these images; it is a separate animated preview.
