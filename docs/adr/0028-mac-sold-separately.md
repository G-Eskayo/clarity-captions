# 0028 — The Mac app is sold separately from the iPhone/iPad app

## Status

Accepted (owner, 2026-10-28). Supersedes [[0010]]'s preference for one app record with every platform (Universal
Purchase), for the Mac only. Pricing record: #156. Work: #176.

## Context

The Mac app (`Apps/Mac`, #172) captions calls as well as the room. It shared the iPhone/iPad app's bundle ID,
`com.gileskayo.captions`, and macOS builds 1.1 (1) and 1.1 (2) were uploaded to the iPhone/iPad App Store Connect
record for TestFlight. Apple joins platforms into one Universal Purchase when they share the record and bundle ID
(evidence log E28), so released from that record, the Mac app would come free with every iPhone or iPad purchase.

## Decision

1. **iPhone and iPad stay one purchase**: the existing record, `com.gileskayo.captions`, $4.99 one-time, with Live
   Translation as one $1.99 in-app purchase covering both.
2. **The Mac is a separate app**: bundle ID `com.gileskayo.captions.mac`, its own App Store Connect record, $4.99
   one-time, with its own $1.99 Live Translation in-app purchase. Buying on one doesn't unlock the other.
3. **No macOS version is ever submitted from the iPhone/iPad record.** The macOS builds already uploaded there stay
   TestFlight-only.
4. A test (`AppStoreRecordTests`) fails if the two apps share a bundle ID or the iPhone app's ID changes.

## Consequences

- Mac TestFlight moves to the new record. Saved conversations made under the old Mac bundle ID don't carry over
  (they live in the app's own container).
- Two App Store listings, two sets of screenshots and two review submissions.
- The site shows two prices: iPhone and iPad together, and Mac (#177).
