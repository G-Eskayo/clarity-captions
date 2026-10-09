# v1 polish mock-ups (2026-10-09, revised after the owner's feedback), for approval

Mock-ups of [docs/design/v1-polish-spec.md](../../v1-polish-spec.md), drawn at iPhone 17 Pro size (402×874 pt,
rendered at 3×). They are HTML pictures of the intended design, not the running app. After building, PRs carry real
simulator screenshots. Regenerate with `node src/build.mjs` (it uses the Playwright in `~/.agents/dashboard`).

| Image | What to look at |
|---|---|
| 01-main-captioning.png | Gear top-left with "Listening" on the same row; today's small Stop circle at the bottom right; captions in the dyslexia-friendly font. Portrait and landscape. |
| 02-paused-save-new.png | After X: Start captions at the bottom middle; captions fade back; retro text buttons [ Save ] over [ New ], centered. Portrait, landscape, and dark. |
| 03-save-animation.png | [ Save ] → [ ✔ ] (green) → [ Saved ] (green, held until the conversation changes). Light and dark. |
| 04-dim-cleared-and-back.png | Tap the veil to clear it for scrolling and copying; press and hold on empty space brings it back. |
| 05-copy.png | Multi-line selection with handles and only a Copy button. |
| 06-themes.png | 3 light and 3 relaxed dark themes, with computed contrast for text, gear, speaker labels and the [ Saved ] green. All ≥ 7:1. |
| 08-settings.png | Settings with no borders, one thin line between sections, A− / A+ buttons, no Conversation section; Lettering: Easy to read (OpenDyslexic, default), Atkinson Hyperlegible, Standard, Rounded, Serif, Typewriter. Light and dark. |
| 09-how-to-use-intro.png | The how-to-use tour on the real main screen: spotlight on the real control, six steps, Skip / Back / Next. |
| 10-button-style-A-final.png | The chosen Start button style: A (gummy lip) with a thinner bottom lip, resting and pressed, light and dark. Used on every screen. |

(07, the A/B/C board, and 11, the launch hand-off, were removed: the button style is chosen, and the hand-off is decided on #99.)

## What changed in the latest round

- **Status on the gear row:** "Listening" / "Paused" sits on the same row as the gear, so captions start higher.
- **Button style A, final:** gummy lip with a thinner bottom lip (3 pt resting, 1 pt pressed), used everywhere.
- **Lettering has six choices:** Easy to read (OpenDyslexic, default), Atkinson Hyperlegible, Standard, Rounded,
  Serif, Typewriter.
- **Launch hand-off removed from here:** the launch animation lands in this screen; its hand-off is chosen on #99.

## Earlier changes after the owner's feedback

- **Start captions is at the bottom middle** (it was drawn at the top). While captioning, Stop is today's small circle
  at the bottom right, which the Start pill shrinks into.
- **[ Save ] / [ New ] are retro, literal text buttons**, centered: `[ Save ]` → `[ ✔ ]` → `[ Saved ]` in green.
- **Dark themes are relaxed for older eyes:** Bright (yellow on black) is gone; no pure black backgrounds and no pure
  white text. Charcoal replaces Classic, Night is softened, Harbor is new.
- **Settings:** no borders anywhere, one thin line between sections, A− / A+ buttons instead of a slider, the
  Conversation section (Copy all / Share) removed.
- **The intro is a tour on the real screen**, not cards.

## Choices made in the mock-ups (the veil and the swatch check are Decisions on #96)

- **The pause veil fades toward the theme's own background** (about 86%), instead of darkening, so [ Save ] and
  [ New ] keep full theme contrast. Each retro button sits on a patch of the theme background (no border) so faded
  captions never show through the letters.
- **Retro buttons use a monospaced font** (SF Mono) so the brackets line up like a terminal.
- **[ Saved ] green:** #12512F on light themes (7.8–8.6:1), #9BE3B4 / #A6E8BC on dark themes (9.2–10.3:1).
- **Dark theme colors:** Charcoal #2B2D31 / #ECE6D9, Night #1D2536 / #E9E3D5, Harbor #173331 / #ECE4D3.
- **Atkinson Hyperlegible** (SIL OFL) is bundled for the mock in `src/fonts/`, like OpenDyslexic.
- **Settings sits on the theme background**, selected theme marked with a small check under its swatch (no ring).
- **Tour:** six steps, each moving on when she does the thing; Next skips a step, Back goes back, Skip tour ends it.

## Research behind the dark-theme change

No study found shows yellow-on-black is easier for older readers; luminance contrast, not hue, is what helps
(Legge et al. 1990, low-vision reading). In healthy older adults, dark text on light read slightly better than light
on dark, with no measured difference in eye fatigue (Piepenbrock et al., Ergonomics 2013). Very bright text on pure
black is commonly reported to glare for people with astigmatism (anecdotal, not a controlled study). Hence: relaxed
dark themes, no pure black or white, contrast kept at AAA.
