# Round-2 mock-ups (2026-10-10)

One screen, fades only, no boxes or borders, an action-driven tour, a smoother launch hand-off. Rules:
[`v1-polish-spec.md` § Round 2](../../v1-polish-spec.md). What they replace: [`ui-audit-2026-10-10.md`](../../ui-audit-2026-10-10.md).

| File | What to look at |
|---|---|
| `01-settings-fade.png` | Settings fades in on the same screen (captions out first, then Settings in); the gear stays put and takes her back. Alternative: a "‹ Captions" word. |
| `02-saved-fade.png` | Saved conversations on the same background: plain rows, one thin line, plain search, Delete all asked in place. |
| `03-confirmations-in-place.png` | [ New ]'s question, naming a speaker: in place, in retro words, no alert boxes. |
| `04-cards-borderless.png` | The rating question on the dim with no card (the same rule for the beta notice and the tour words). |
| `05-preparing.png` | After Start, no seal box: A words only, B words + a small seal face. |
| `06-voices-explainer.png` | "Seal tells voices apart": today's boxed banner vs one plain line that fades by itself. |
| `07-tour-v2.png` | The tour, 9 frames: each step waits for her to really do it; no Next on action steps; Back and Skip stay. |
| `anim-settings-fade.gif` | Settings in and out as fades. |
| `anim-save-new-inplace.gif` | [ Save ] → [ ✔ ] → [ Saved ], then [ New ]'s question in place. |
| `anim-tour-save-moment.gif` | In the tour, [ Saved ] gets its moment before the next words fade in (today the next card covers it). |
| `anim-launch-handoff-smooth.gif` | The hand-off without a hard cut: the green irises in continuously behind the seal, an arcing jump with squash and stretch, a splash, three ripples. |

`src/build.mjs` renders everything (Playwright + ffmpeg). `src/seal-nobg*.svg` are `design/mascot/seal-rig.svg`
without the icon's teal square (the square is what made "the seal in a box").
