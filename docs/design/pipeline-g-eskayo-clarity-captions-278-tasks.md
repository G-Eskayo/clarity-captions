1. [ ] Edit `testRetentionPolicyIsExpired29DaysAgo` to compute `savedAt` via `Calendar.current.date(byAdding: .day, value: -29, to: now)!` instead of `addingTimeInterval`.
2. [ ] Edit `testRetentionPolicyIsExpired30DaysAgo` the same way with `-30`.
3. [ ] Edit `testRetentionPolicyIsExpired31DaysAgo` the same way with `-31`.
4. [ ] Add `testRetentionPolicyAcrossDaylightSavingFallBack` using fixed `now`/`savedAt` dates spanning the 2026-11-01 fall-back, asserting the 30-day boundary (expired at 30, not at 29).
5. [ ] Add `testRetentionPolicyAcrossDaylightSavingSpringForward` using fixed dates spanning the 2027-03-14 spring-forward, same boundary assertions.
6. [ ] Run `swift test --package-path Packages/CaptionCore` and confirm all `SavedConversationStoreTests` pass, with no change to any other test's outcome.