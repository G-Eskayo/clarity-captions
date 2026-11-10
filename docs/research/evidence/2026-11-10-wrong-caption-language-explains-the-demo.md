# A saved non-English caption language explains the bad demo; build 10 is immune to it

- **Source:** the owner's beta report from the demo phone (1.1.0 (9), shared 2026-11-10, kept private) and our own
  replays, #273 (PR #274): 8 EdAcc validation conversations through build 9 (`3c56e56`) and build 10 (`be128a5`) with
  the caption language set to en-US, es-ES, pt-BR, fr-FR, de-DE and it-IT. Results:
  `docs/perf/whole-system-replay-results.md` ("The owner's session data").
- **What we took:** every session on the phone ran Apple's engine with `engineFallback = "locale"`, so Apple's
  engine was hearing English as another language. Replayed, that costs build 9 34 to 58 WER points and gives the
  phone's kind of text; build 10 sends those languages to Parakeet, which hears the language itself, and loses 0.0
  to 2.2 points. On an en-US phone the language must have been saved in Seal (Settings › Caption language or first
  run), where it survives updates and is not shown on the caption screen.
- **Confidence:** Ours. Strong for the mechanism (the report's own field, reproduced); the exact language saved on
  the phone is not known yet.
- **Drives:** #273's decision for the owner on the engine fallback; showing the caption language, and recording it
  in the beta report.
- **Public use:** Internal.
