# Clarity Captions

A native iOS app that gives real-time speech captions with **zero network dependency** — everything
runs on-device. Built for a deaf user who needs to follow live conversation without relying on a
service connection (unlike cloud-based tools such as Otter).

Working title. Target: production-ready, installed on the intended user's iPhone 17, by
**2026-10-25**.

## Status

Pre-implementation. See `CONTEXT.md` for domain terms and `docs/adr/` for the decisions made so
far. No code yet — requirements and design come first.

## Core requirements

- Fully on-device real-time transcription of conversation audio. No network call anywhere in the
  captioning path.
- Runs natively on iPhone 17.
- Stretch goal, feasibility being validated first: filter the user's own speech out of the
  caption stream so only other speakers' words are shown.
