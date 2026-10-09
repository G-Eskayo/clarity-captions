# 0020 — Captioning continues when the app is left or the phone is locked

## Status

Accepted (2026-10-06), from the #3 design session. **Deferred past v1** (owner, 2026-10-09): not implemented yet (the app declares no `audio` background mode); v1 keeps the screen awake while captioning instead ([[0019]], #83). Tracked by #10.

## Context

Mid-conversation the user may check a message or press the side button out of habit. Stopping
captions whenever the app leaves the screen is simpler and unambiguously private, but even a short
glance away would lose part of the conversation, and a missed caption costs a deaf user far more than
an extra one ([[0012]]).

## Decision

Captioning keeps running while the app is in the background or the phone is locked. iOS's microphone
indicator stays visible throughout, and the idle stop ([[0019]]) still applies. On return, the stream
follows the newest caption, and a short marker in the transcript (along the lines of
*— while you were away —*) shows where she left so she can scroll back.

## Consequences

- Nothing said during a glance away is lost.
- Requires the audio background capability; App Review must see it is used for live captioning.
- Battery cost while backgrounded is bounded by the idle stop.
- Never secretly listening: the system microphone indicator is always shown while running.
