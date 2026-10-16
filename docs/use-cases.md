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

## From TestFlight build 3, the project owner (2026-10-13, iPhone 18 Pro, iOS 27.0.1)

Eight screenshot comments, read from Xcode's TestFlight feedback cache. Decided 2026-10-15: all of it goes into build 4.

**The tour (5 of 8):**

> I'm guess this is on a timer, but after reading it and giving it a couple seconds, I don't see anything. (step 4, Tap [ Save ])

> Okay, it wasn't on a timer, just hung. Going back worked, but some of the text that is on a timer went away too
> quickly. Show it all and let the user dictate when to go forward, but don't add a shit ton more onboarding pages.
> (step 5, Tap anywhere on the dim)

> What does page 5 and 6 mean? I don't get it.

> Honestly, just add this to the last page. Kinda thought I was done when I edited the settings and felt annoyed that
> I wasn't. Maybe that's me. (step 7, Tap the gear)

> Maybe another me thing, but you don't really need to explain the obvious UI elements. (step 8, That's it)

- Cause: tour v2 (#121) advances action steps **only** on the real action (no Next), so a step whose action isn't
  obvious looks frozen. Two follow-up lines disappear after a short reading pause.
- Landed: the tour is shortened to about 4 steps the user controls. Every step has Next and also advances on the action,
  nothing is timed, and obvious UI isn't explained. Mock-ups go to the owner first.

**Main screen:**

> Speaker 1 needs top padding. It's is in the scroll fade section.

- Landed: top padding so the first speaker label clears the fade.

**Settings:**

> What the heck is that preview at the top?

- Landed: label the live sample plainly (it shows how captions will look).

> Saved conversations section isn't obvious. Feels like something that could be used a lot. Maybe rethink its location.

- Landed: reachable from the main screen in build 4. Placement goes to the owner as mock-up options.

**Still open from the owner's father (2026-10-03):** what "a close button" means. Ask him before build 4 if possible.
