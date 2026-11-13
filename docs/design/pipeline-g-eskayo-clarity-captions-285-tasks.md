1. `ParakeetBackend.language(for:)` pure helper + `ParakeetBackendLanguageTests` (red, then green).
2. `ParakeetBackend.init(modelURL:locale:)`, pass `language:` into both `decode()` call sites' `manager.transcribe(...)`.
3. `ParakeetBackend.onWindow` callback, fired at both real-decode sites in `run()` (not the silence-gated skip, not `finish()`).
4. `TranscriptionEngine.onDecodeWindow`, wire `locale` and `onWindow` through `makeBackend()`'s `.parakeet` case; extend `TranscriptionEngineBackendTests`.
5. `SessionLog.decodeWindows: [Double]`; extend `SessionLogTests` for round-trip.
6. `main.swift`: wire `engine.onDecodeWindow` into `log.decodeWindows`, next to `watchFallbacks`.
7. `replay.py`: `update_spans`, `boundary_positions`, `boundary_errors`, each with the pytest cases above; wire the new table into `score()`/`markdown()`, scoped to sessions that stayed on Parakeet (reuse `left_parakeet`).
8. `swift test --package-path Packages/CaptionCore` and `swift test --package-path Packages/SystemReplay` green; `python -m pytest scripts/system-replay/tests` green.
9. Update `docs/design/parakeet-engine-switch.md` and `docs/perf/whole-system-replay-design.md` with the new `decodeWindows` field and the FluidAudio script-filter finding (so the next person doesn't re-propose the same "language pin" as a fix for same-script drift).
10. PR body states plainly: criteria 2–3 (WER gap closed, no lag regression) are **not** claimed — they need a real `scripts/system-replay/run-ab.sh` run on the Mac mini using this PR's new `decodeWindows`/per-boundary output, which this agent cannot execute here; recommend Decision `scope-285`'s first option.