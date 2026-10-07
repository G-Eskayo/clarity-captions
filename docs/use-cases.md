# Use cases and user stories

Collected from people who will actually use or support the app. Each item says where it landed, so
nothing is lost. Decisions live in `docs/adr/`; vocabulary in `CONTEXT.md`.

## From the project owner's father (2026-10-03)

> The basic use case: pull out the phone, tap an icon, put the phone on a table or counter where
> people are talking, read the resulting text.

- **Open and caption with as few taps as possible.** Landed in the silence/failure/lock design
  session (#3, 2026-10-06): **no auto-start** — captioning still begins with one Start tap after
  opening the app (owner's decision).
- Phone is **placed on a table or counter**. Matches the primary environments in ADR 0012.

> Does the service you're using differentiate between speakers? I'm guessing it doesn't.

- It does: "Speaker 1 / Speaker 2" labels (ADR 0008). Worth saying plainly in onboarding or the
  store description, since a first guess is that it can't.

> The app should rotate to portrait or landscape.

- New issue: rotate to portrait and landscape with a usable layout in both.

> Include a font size setting somewhere and a close button.

- Font size: built (Settings, size A-/A+). He may expect it reachable faster; revisit after use.
- "Close button": unclear whether he means stop captioning, close a screen, or quit the app. iOS has
  no in-app quit. Today there is a Stop control. Ask him before building anything.

> Add line breaks during pauses.

- New issue: line breaks at pauses (and when the speaker changes).

> The window should be scrollable.

- Scrolling exists; automatic following of the newest text was missing. New issue: auto-scroll to
  the newest caption, with "Jump to latest" after scrolling back.

> Test it by plopping it onto whatever table you're at in a group and see what it does: how fast
> is it? Does it keep up? How's the accuracy?

- This is the restaurant-conditions test. Added "does it keep up" as an explicit result alongside
  speed (lag) and accuracy.
