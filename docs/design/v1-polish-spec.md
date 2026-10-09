# v1 polish spec (owner, 2026-10-09)

Source: the owner's own words in the 2026-10-09 session, after testing on his iPhone 17 Pro. Builders implement this
exactly. **Nothing about placement, labels, colors or motion may be invented:** if a detail is not here, ask, or list it
as an open question in the PR. Every ticket and PR that changes the look carries images (mock-ups before building,
simulator screenshots after). This is a hard rule.

## 1. Pause, save, new (replaces ADR 0022's auto-save)

- Pressing the X (Stop) brings the **Start captions** button back, with exactly the functionality and smoothness it
  has now.
- A **dimmed background** fades in (the captions fade back), with two **retro, literal text buttons**, centered:
  **`[ Save ]`**, and under it **`[ New ]`** (owner, 2026-10-09 review of #96: no pill, just the bracketed text).
- Pressing **Start captions** fades the dim and the choices back to clear, and captioning **resumes the same
  conversation**.
- **Save animation:** `[ Save ]` → tap → `[ ✔ ]` → `[ Saved ]` in **green text**, held solid until saving is allowed
  again.
- After saving she can resume as above. If **the conversation's content changes** (new captions, not time passing),
  the button returns to `[ Save ]` so she can save again. Saving again updates the same saved conversation.
- Saved conversations are **deleted after 30 days**, with a note saying so in the Saved section.
- Only conversations she saves are kept (no automatic saving of every session).
- **Copying while paused:** a single tap on the dimmed area fades the dim and buttons to clear, so she can scroll and
  select text. The dim and the buttons come back with a **press-and-hold on empty space** (not on words). Press-and-hold
  on words selects text. *(Proposed: needs the owner's sign-off on the mock-up.)*
- Open: [ NEW ] with unsaved changes asks first or clears at once (proposed: asks); whether an unsaved conversation
  survives closing the app (proposed: yes, the one current conversation only).

## 2. Layout

- **Start captions** sits at the **bottom middle**, in portrait and landscape (corrected 2026-10-09 after the #96
  mock-ups drew it at the top). While captioning, Stop is today's small circle, which the Start pill shrinks into.
- The **Listening / Paused** status sits on the **same row as the gear**, so captions start higher (owner, 2026-10-09).
- **Settings** is always in the **top-left corner**, as a **gear icon only**: no words, no background, in a color
  chosen to suit each theme.
- The app flows: it should never feel like changing screens. Use transitions and shared elements, not hard cuts.

## 3. Copying text

- Press and hold to select caption text and drag the handles to extend it (across lines).
- About **half a second** after the selection stops changing, **only a Copy button** appears (no other menu items).
- The selection can still be resized after the Copy button appears.

## 4. Look and feel

- **Flat and gummy throughout:** bold, relaxing flat colors that are easy and pleasant on the eyes in different
  environments; buttons that **squish when pressed**; fun animations here and there.
- **Themes:** an equal choice of light and dark, **3 light and 3 dark** (today: 3 dark, 1 light). Every pair stays at
  AAA contrast (the existing test).
- **Dark themes are relaxed for older eyes** (the audience is older people, not developers): no pure black behind,
  no pure white text; the black-and-yellow "Bright" theme is dropped as harsh. Research: luminance contrast, not hue,
  is what helps low-vision readers; no study found favoring yellow on black.
- **Button style: A (gummy lip), with a thinner bottom lip** (owner, 2026-10-09; #96 image 10).

## 5. Lettering

- Lettering choices: **OpenDyslexic (default)**, **Atkinson Hyperlegible**, **Standard** (system font), **Typewriter**.
  **Rounded** and **Serif** are removed (owner, 2026-10-09, PR #100).
- Why OpenDyslexic is the default: the owner is dyslexic (an homage) and finds it comforting to look at. The research
  shows no measured reading benefit (evidence log E5), so it is offered for comfort and never marketed as improving
  reading. Both fonts are SIL Open Font License; credit them in NOTICE and in-app credits.

## 6. Settings cleanup

- Remove **Words and names** from Settings (keep the engine's vocabulary support for later).
- Remove the **Speaker labels** explainer section.
- Remove the **Conversation** section (Copy all text / Share as text / SRT): highlight-and-copy covers it.
- **No borders anywhere** in Settings (not the preview, not the sections): it should feel like the same screen. At most
  **one thin line** between sections; minimalism. "Stop when it's quiet" stays, minus its border.
- Text size uses the **A− / A+ buttons** (as today), not a slider.

## 7. How-to-use intro

- A **short, sweet, interactive** intro showing how to use the app, at first run.
- It is a tour **on the real screen**, not instruction cards: the person actually uses the app as intended, where
  everything really is (spotlight on the real Start, X, [ Save ], caption text, gear), moving on as they do each
  thing, so there is no translating instructions into understanding.
- People go through it **as fast or as slow as they want**.
- It can be **replayed at any time from Settings with one button**.

## 8. Launch animation

- On the green launch screen, the **seal mascot from the app icon** does a **funny, inviting, warm** animation: a
  dance move or something fun, or something that says what the app does.
- It **lands in a pose** that can stay freeze-framed until the app is ready.
- A **progress bar** shows start-up progress.
- Even if the progress finishes first, the animation **always finishes**, then **holds the freeze frame for 0.75 s**,
  then **animates into the start screen**.
- The mascot does **not** live anywhere else in the app.
- Open: how it hands off into the main screen: **Glide** (the seal shrinks and glides down into the bottom-middle
  Start button, which grows out of it) or **Dive** (the seal dives down and the main screen washes up). Chosen on
  #99, which is updated to land in the #96 main screen.
