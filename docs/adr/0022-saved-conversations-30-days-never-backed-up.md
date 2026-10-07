# 0022 — Conversations are saved automatically for 30 days and never leave the phone, not even in backups

## Status

Accepted (2026-10-06), from the #3 design session. Implemented by #8 and #52.

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
