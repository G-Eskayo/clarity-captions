# Seal app icon

Approved by the project owner on 2026-10-05.

## Files

- `seal-icon-1024.png`: the light icon (1024 px, RGB, no transparency, square: iOS applies the rounded mask).
- `seal-icon-1024-dark.png`: dark appearance (same art, deeper teal background).
- `seal-icon-1024-tinted.png`: tinted appearance (grayscale, iOS applies the user's tint).
- `source/b3-seed5.png`: the generated image the art is built from.
- `build_icon.py`: rebuilds all three from the source (needs numpy, scipy and Pillow; the MARVIN venv has them).

## Palette (four colors)

| Role | Hex |
|---|---|
| Background teal | `#1F998B` |
| Seal cream | `#FBE8C1` |
| Body shadow, cheeks, tongue (peach) | `#EFC587` |
| Features: eyes, nose, mouth, whiskers (deep teal) | `#0E5A56` |

## Provenance

- The source image was generated locally with **FLUX.1-schnell** (Apache-2.0) through mflux:
  `--model schnell -q 4 --steps 4 --width 640 --height 640 --seed 5`, with a prompt asking for a minimal
  flat three-color mascot: "Simple geometric seal pup mascot, a round cream head and one raised waving
  flipper, big round eye with a shine, open barking mouth facing left, shapes built from circles and
  smooth curves, zoomed in so the head fills most of the square," plus a style line (flat colors, no
  gradients, no outlines, no text).
- `build_icon.py` flattens it onto the locked palette, redraws the whiskers and tongue as clean shapes,
  adds the three bark rays, and exports the appearances.
- **No photograph is used or stored here.** An earlier direction used a reference photo for the pose; that
  work was scrapped and removed from the repo.

## Caveats

- Purely AI-generated art generally cannot be copyrighted, though the finished icon can still function as
  a trademark. Keep that in mind for the store listing.
- The edges are smoothed from a 640 px source, so they are slightly soft up close. A vector redraw would be
  the polish step if it ever matters.
