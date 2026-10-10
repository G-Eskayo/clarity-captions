# 0022 — Conversations are saved automatically for 30 days and never leave the phone, not even in backups

## Status

Accepted (2026-10-06), from the #3 design session. Implemented by #8 and #52. Amended 2026-10-09 by #102 (save on request).

## Context

A deaf user often needs to reread what someone said, both during a conversation and afterwards
("what was the restaurant name she mentioned at lunch?"). Transcripts also hold what *other people*
said in private conversations, and "on-device only" is the promise the app is built on (CONTEXT.md).
iOS includes app data in iCloud device backups unless the app excludes it.

Considered: keep only the current session (simplest, but loses the "reread later" value); keep forever
(unbounded private data on the phone); include transcripts in iCloud backup (survives a lost phone,
but breaks the on-device promise).

## Decision

1. During a session, scrollback is unlimited.
2. When captioning stops, the conversation is saved automatically on the phone with its date and time.
3. Saved conversations are deleted automatically after 30 days. Any single conversation, or all of
   them, can be deleted at any time.
4. Transcripts are excluded from iCloud backup and from any sync. Nothing leaves the device.

## Consequences

- She can reread recent conversations without doing anything to save them.
- Private conversations don't accumulate indefinitely.
- A lost, broken or replaced phone loses its transcripts: accepted as the price of the on-device promise.
- The 30-day window is fixed, not a setting ([[0013]], [[0019]]: idle stop is the only behavior setting).

## Amendment (2026-10-09, #102): saved on request, not automatically

The owner's v1 design (#96, `docs/design/v1-polish-spec.md` §1) replaces decision 2:

- Stop **pauses** the conversation instead of saving and clearing it. A dim fades in with **[ Save ]** over
  **[ New ]**; Start captions resumes the **same** conversation.
- A conversation is saved **only when she taps [ Save ]**. It shows [ ✔ ] then **[ Saved ]** in green, held until
  the conversation's content changes; saving again updates the same saved conversation.
- **[ New ]** clears it, and asks first when it isn't saved.
- Decisions 1, 3 and 4 stand: unlimited scrollback, saved conversations deleted after 30 days, never backed up
  or synced.
- New: while she is in another app, the on-screen conversation is written to the phone (excluded from backup) so
  it survives iOS closing Seal in the background. On a cold launch it comes back paused if she left less than 30
  minutes ago, and is deleted otherwise (Decision "coldlaunch" on #102, recommended option pending the owner's
  answer; `ColdLaunchRule.current`). iOS can't tell a swipe-away from a background close, hence the time window.
