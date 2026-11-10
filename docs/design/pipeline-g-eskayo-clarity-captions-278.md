## North-star fit

- **Reuses**: the fixed-date construction pattern already in `Packages/CaptionCore/Tests/CaptionCoreTests/SavedConversationExportTests.swift:8-11` (a `date(y, m, d, h, min, in: zone)` helper built on `Calendar(identifier: .gregorian)` + `DateComponents`) — same idea applied here as `Calendar.current.date(byAdding:to:)` arithmetic instead of `addingTimeInterval`, since `RetentionPolicy.isExpired` (`Packages/CaptionCore/Sources/CaptionCore/SavedConversationStore.swift:4-7`) is hard-coded to `Calendar.current` and can't take an injected calendar without an app-code change the ticket forbids ("No app change").
- **Simplest sufficient approach**: match the test's date arithmetic to the production arithmetic (`Calendar.current.date(byAdding: .day, ...)`) instead of inventing a second time-handling mechanism (no custom calendar injection, no mocking `Date()`, no new dependency). This is the fix the ticket itself names as primary ("compute '30 days ago' with the same calendar").
- **Token/compute cost**: zero runtime cost — this only touches test code, three one-line changes plus one new ~10-line test function. No new files.
- **User impact**: none — test-only change, no app behavior, no UI. It fixes a developer-experience problem (false-red local test runs), not a user-facing one.
- **Decision I'm making myself** (not an owner-gated choice — not a look/Apple/signing/dependency/feature change): the ticket asks for one DST-crossing case; I'll add two (fall-back **and** spring-forward) since "tests try to break it" calls for exercising both directions a day can be non-24-hours, and it's a one-function, zero-risk addition. Noting it here rather than blocking on it.

## Current behavior confirmed

- `RetentionPolicy.isExpired` (prod): `Calendar.current.date(byAdding: .day, value: retentionDays, to: savedAt)`, then `now >= expiryDate` — correct calendar-day semantics already, no app bug.
- The three failing-prone tests (`SavedConversationStoreTests.swift:20-39`) build `savedAt` with `Date().addingTimeInterval(-N * 24 * 3600)` — wall-clock seconds, not calendar days. Any DST transition inside the N-day window shifts the real elapsed wall-clock time away from what N calendar days actually spans, flipping the boundary tests (`29DaysAgo`, `30DaysAgo`, `31DaysAgo`) depending on host time zone and run date.
- `testPurgeExpiredRemovesOnlyExpiredEntries` (`:123-137`) uses the same `addingTimeInterval` pattern but with 10/40-day margins either side of the 30-day boundary — a single 1-hour DST shift can't flip those, so it's not flaky and is out of scope (minimal diff, Colton check: fix the actual defect, not adjacent passing code).

## Tests to write first (TDD — these are the only edits)

All in `Packages/CaptionCore/Tests/CaptionCoreTests/SavedConversationStoreTests.swift`:

1. `testRetentionPolicyIsExpired29DaysAgo` — change `savedAt` from `Date().addingTimeInterval(-29 * 24 * 3600)` to `Calendar.current.date(byAdding: .day, value: -29, to: now)!`, `now = Date()` kept as-is but computed once before `savedAt`. Assert `XCTAssertFalse(expired)` unchanged.
2. `testRetentionPolicyIsExpired30DaysAgo` — same change with `-30`. Assert `XCTAssertTrue(expired)` unchanged. (This is the ticket's named failing test.)
3. `testRetentionPolicyIsExpired31DaysAgo` — same change with `-31`. Assert `XCTAssertTrue(expired)` unchanged.
4. **New** `testRetentionPolicyAcrossDaylightSavingFallBack` — pin `now` to a fixed calendar date whose "30 days back" lands exactly on the real 2026-11-01 US fall-back (`now = Dec 1, 2026`, `savedAt = Calendar.current.date(byAdding: .day, value: -30, to: now)!` → Nov 1, 2026). Assert expired at exactly 30 days, not expired at 29 days back from that same fixed `now`. Deterministic everywhere: on a DST-observing host it genuinely crosses the transition; on a non-DST host (CI, UTC) it's still correct, just not exercising the edge — never flaky either way. This is the "misuse the ticket didn't call out but adversarial testing should": a fixed historical/future date instead of `Date()`, so the test's correctness never depends on *when* it's run.
5. **New** `testRetentionPolicyAcrossDaylightSavingSpringForward` — same shape, pinned around the 2027-03-14 US spring-forward (23-hour day, the opposite deviation direction): `now = April 13, 2027`, `savedAt` 30 calendar days back. Assert expired at 30 days, not expired at 29.

No other files change. No production code, no UI, no new dependency, no signing/network change — all owner gates in the playbook are inapplicable here.

**Complexity:** every changed/added function is O(1) time and O(1) space (a handful of `Calendar` date computations and boolean comparisons) — no change to the O(n) `purgeExpired`/`all()` scan it feeds into.

**Untested / can't verify myself:** none of this touches UI or the simulator-built app at all, so there's no screenshot or app-build dependency for this ticket — purely a `swift test --package-path Packages/CaptionCore` change, which I can and will run to verify green.

## Task List

1. [ ] Edit `testRetentionPolicyIsExpired29DaysAgo` to compute `savedAt` via `Calendar.current.date(byAdding: .day, value: -29, to: now)!` instead of `addingTimeInterval`.
2. [ ] Edit `testRetentionPolicyIsExpired30DaysAgo` the same way with `-30`.
3. [ ] Edit `testRetentionPolicyIsExpired31DaysAgo` the same way with `-31`.
4. [ ] Add `testRetentionPolicyAcrossDaylightSavingFallBack` using fixed `now`/`savedAt` dates spanning the 2026-11-01 fall-back, asserting the 30-day boundary (expired at 30, not at 29).
5. [ ] Add `testRetentionPolicyAcrossDaylightSavingSpringForward` using fixed dates spanning the 2027-03-14 spring-forward, same boundary assertions.
6. [ ] Run `swift test --package-path Packages/CaptionCore` and confirm all `SavedConversationStoreTests` pass, with no change to any other test's outcome.