# 0024 — Beta reports are picked up automatically on the Mac Mini, grouped by device, and testers' words stay private

## Status

Accepted (2026-10-13, owner). Extends ADR 0023, which covers the sending side. Report format:
`docs/beta/metrics-schema.md`.

## Context

ADR 0023 shipped the sending side: testers tap *Send feedback to Gil* and a `seal-feedback-*.json` report arrives
as a text attachment. Build 3 passed Beta App Review on 2026-10-13, and the public TestFlight link is live, so
reports can now arrive from people the owner hasn't set up personally. Nothing reads them yet.

The owner wants every report recorded, the useful and actionable parts pulled out, and the results **grouped by
device**, with no step that depends on him forwarding anything.

This repo is public. A tester's note is their own words, and may mention other people or places.

## Decision

1. **Automatic pickup, not forwarding.** A MARVIN job finds new `seal-feedback-*.json` files under
   `~/Library/Messages/Attachments/` by itself. It reads only those files, never message text or other
   attachments.
2. **It runs on the Mac Mini**, the always-on automation host, so reports are ingested while the laptop is closed.
   This needs Messages signed in on the Mini with *Messages in iCloud* on, and a one-time Full Disk Access grant
   for the job's interpreter (see the MARVIN launchd/TCC notes).
3. **Private store.** Raw reports and summaries live outside the repo, on the Mini (`~/.claude/seal-beta/`). Each
   report is validated against `schema: 1`, and duplicates are skipped by conversation `id`.
4. **Grouped by device.** The main view groups by device model, shown by its plain name ("iPhone 15 Pro") and
   then split by build. Each group shows report count, median rating, lag p50/p95, rewrite rate, relabels per
   minute, how conversations ended, battery drop per 30 minutes, and highest thermal state. A second view groups
   by build, to see whether a new build fixed something. Results show in the MARVIN dashboard.
5. **Public tickets carry numbers only.** When a threshold is crossed, the job files or updates a clarity-captions
   ticket with device, build, report count and the measurements. It never includes a note, a tester's name or
   phone number, or anything that identifies who sent it. Notes are read in the private view. Starting
   thresholds, to be tuned once real data arrives:
   - lag p95 above 2 s on a device model
   - any `stuck` ending
   - median rating at or below 4 on a device model, from at least 2 reports
6. **TestFlight's own feed comes second.** TestFlight's screenshot feedback and crash reports (App Store Connect
   API) join the same per-device view in a follow-up. The owner creates the API key and stores it on the Mini;
   agents never handle it.

## Consequences

- The schema doc's earlier plan to quote the tester's note in tickets is replaced by decision 5.
- If Messages on the Mini is signed out, or *Messages in iCloud* is off, reports stop arriving with no error.
  The job reports when it last saw a report, so a long silence shows up in the dashboard's health checks.
- Testers' notes never reach GitHub, so a ticket alone can't explain *why* a rating was low. The owner reads the
  note in the private view and adds plain context to the ticket by hand if he wants to.
- Reports are tied to a build (ADR 0023), so per-build views show whether a fix worked.
