# Beta feedback report: file format

Decision: ADR 0023. One file per *Send feedback to Gil*, named `seal-feedback-<build>-<YYYYMMDD-HHMM>.json`. It
holds every conversation recorded since the last report that was sent.

**Never in a report:** caption text, audio, speaker names, vocabulary, saved conversations. The only free text is
the tester's own optional note.

## Shape

```json
{
  "schema": 1,
  "app": { "version": "1.0", "build": "42", "environment": "sandbox" },
  "device": { "model": "iPhone15,4", "os": "iOS 26.1", "lowPowerModeSeen": false },
  "settings": { "theme": "paper", "lettering": "openDyslexic", "textSize": "large", "quietStop": "5min" },
  "sentAt": "2026-10-12T18:04:00-06:00",
  "conversations": [
    {
      "id": "6F1C…",
      "startedAt": "2026-10-12T12:31:05-06:00",
      "minutes": 23.4,
      "rating": 8,
      "ratingSkipped": false,
      "note": "Lost it when the waiter talked fast",
      "lag": { "p50Seconds": 0.62, "p95Seconds": 1.48, "samples": 1840 },
      "rewriteRate": 0.11,
      "speakers": { "detected": 3, "relabelsPerMinute": 0.9 },
      "launchToStartSeconds": 2.1,
      "startToFirstCaptionSeconds": 1.3,
      "ending": { "kind": "userStop" },
      "battery": { "dropPercentPer30Min": 6.5, "maxThermalState": "fair" },
      "micLevel": { "medianDBFS": -38.0, "quietFraction": 0.12 },
      "launch": { "fullDance": false, "barShown": false }
    }
  ]
}
```

| Field | Meaning | Source in the app |
|---|---|---|
| `rating` | Answer to "How well could you follow the conversation?" (1–10), or `null` if skipped | rating card |
| `note` | The tester's optional note; `null` if none | rating card |
| `lag` | Seconds from a word being spoken to its caption appearing | `WordLagTracker` / `CaptionUpdate.lagSeconds` |
| `rewriteRate` | Share of caption words changed after first appearing; an accuracy proxy | `CaptionStream` volatile → final |
| `speakers` | Distinct speaker labels shown, and live relabels per minute | `SpeakerLabelSmoother` |
| `launchToStartSeconds`, `startToFirstCaptionSeconds` | Speed to useful | launch sequence, `TranscriptionEngine` startup laps |
| `ending.kind` | `userStop`, `quietStop`, `failure` (with `reason`, the plain-language text), `stuck`, `appClosed` | `CaptionSessionController`, `IdleStop`, `FailureReason` |
| `battery` | Battery drop scaled to 30 minutes; highest `ProcessInfo.thermalState` | `UIDevice.batteryLevel`, `ProcessInfo` |
| `micLevel` | Room loudness summary, never audio | `AudioLevel`, `ListeningActivityTracker` |

Size: about 1 KB per conversation; capped at the newest 200 (ADR 0023), so a report stays under about 250 KB,
well within an iMessage attachment.

## How MARVIN ingests reports

Texts arrive in the owner's Messages and sync to his Mac, where attachments are stored under
`~/Library/Messages/Attachments/`. A small MARVIN job finds new `seal-feedback-*.json` files there and:

1. validates each against this schema (`schema: 1`) and skips duplicates by conversation `id`
2. appends them to a local dataset (e.g. `~/.claude/seal-beta/reports.jsonl`)
3. summarises per build and per device: median rating, lag p95, rewrite rate, relabels, stop reasons, battery
4. files or updates clarity-captions tickets when a threshold is crossed (e.g. lag p95 > 2 s on a device class,
   any `stuck` ending, a rating ≤ 4 with a note), quoting only the measurements and the tester's note

Reading `~/Library/Messages` needs Full Disk Access for the process that runs the job (macOS privacy protection);
the owner grants that once. The job never reads message text, only `seal-feedback-*.json` attachments.
