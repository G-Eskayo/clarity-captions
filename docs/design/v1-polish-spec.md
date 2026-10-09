# v1 polish spec (owner, 2026-10-09)

Source: the owner's own words in the 2026-10-09 session, after testing on his iPhone 17 Pro. Builders implement this
exactly. **Nothing about placement, labels, colors or motion may be invented:** if a detail is not here, ask, or list it
as an open question in the PR. Every ticket and PR that changes the look carries images (mock-ups before building,
simulator screenshots after). This is a hard rule.

## 1. Pause, save, new (replaces ADR 0022's auto-save)

- Pressing the X (Stop) brings the **Start captions** button back, with exactly the functionality and smoothness it
  has now.
- A **dimmed background** fades in, with two buttons stacked under Start: **[ SAVE ]**, and under it **[ NEW ]**.
- Pressing **Start captions** fades the dim and the choices back to clear, and captioning **resumes the same
  conversation**.
- **Save animation:** [ SAVE ] turns into a **green check box**, then becomes **[ SAVED ]** in green.
- After saving she can resume as above. If **the conversation's content changes** (new captions, not time passing),
  the button returns to [ SAVE ] so she can save again. Saving again updates the same saved conversation.
- Saved conversations are **deleted after 30 days**, with a note saying so in the Saved section.
- Only conversations she saves are kept (no automatic saving of every session).
- **Copying while paused:** a single tap on the dimmed area fades the dim and buttons to clear, so she can scroll and
  select text. The dim and the buttons come back with a **press-and-hold on empty space** (not on words). Press-and-hold
  on words selects text. *(Proposed: needs the owner's sign-off on the mock-up.)*
- Open: [ NEW ] with unsaved changes asks first or clears at once (proposed: asks); whether an unsaved conversation
  survives closing the app (proposed: yes, the one current conversation only).

## 2. Layout

- **Start captions** sits at the **top middle**, in portrait and landscape.
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

## 5. Lettering

- Add a **dyslexia-friendly font** (proposed: OpenDyslexic, SIL Open Font License, credited in NOTICE and in-app
  credits) as a lettering choice, and **make it the default**.

## 6. Settings cleanup

- Remove **Words and names** from Settings (keep the engine's vocabulary support for later).
- Remove the **Speaker labels** explainer section.

## 7. How-to-use intro

- A **short, sweet, interactive** intro showing how to use the app, at first run.
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
- Open: what the seal turns into at the hand-off (proposed: shrinks and glides up into the Start button's spot).
