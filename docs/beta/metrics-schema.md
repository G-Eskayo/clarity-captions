# Beta feedback report: file format

Decision: ADR 0023. One file per *Send feedback to Gil*, named `seal-feedback-<build>-<YYYYMMDD-HHMM>.json`. It
holds every conversation recorded since the last report that was sent.

**Never in a report:** caption text, audio, speaker names, saved conversations. The only free text is
the tester's own optional note.

## Shape

```json
{
  "schema": 1,
  "app": { "version": "1.0", "build": "42", "environment": "sandbox" },
  "device": { "model": "iPhone15,4", "os": "iOS 26.1", "lowPowerModeSeen": false, "language": "en-US" },
  "settings": { "theme": "paper", "lettering": "openDyslexic", "textSize": "large", "quietStop": "fiveMinutes" },
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
      "launch": { "fullDance": false, "barShown": false },
      "engine": "parakeet-ultra-pal6",
      "engineFallback": null,
      "captionLanguage": "en-US",
      "captionLanguageChosen": false,
      "faceToFace": { "owner": "en-US", "partner": "es-ES" },
      "build": "11",
      "earDelay": {
        "translateDelay": { "p50Seconds": 0.42, "p95Seconds": 0.89, "maxSeconds": 1.23, "samples": 156 },
        "voiceStartDelay": { "p50Seconds": 0.05, "p95Seconds": 0.15, "maxSeconds": 0.42, "samples": 156 },
        "behindBy": { "p50Seconds": 0.38, "p95Seconds": 1.14, "maxSeconds": 2.05, "samples": 156 },
        "repeats": 0,
        "translationMisses": 2,
        "voiceCutOffs": 1
      }
    }
  ]
}
```

| Field | Meaning | Source in the app |
|---|---|---|
| `minutes` | Time captions were running, summed over the conversation's stretches; pauses never count. The conversation on screen counts up to the send. Any other stretch left open was cut off when she left Seal (no background audio): it ends at that moment with `ending.kind` `appClosed`, and with no recorded leave time (saved by 1.1 build 10 or earlier) it counts 0 rather than up to the send (#287) | `ConversationRecorder` stretches, `leftMidConversation(at:)` |
| `rating` | Answer to "How well could you follow the conversation?" (1–10), or `null` if skipped | rating card |
| `note` | The tester's optional note; `null` if none | rating card |
| `lag` | Seconds from a word being spoken to its caption appearing | `WordLagTracker` / `CaptionUpdate.lagSeconds` |
| `rewriteRate` | Share of caption words changed after first appearing; an accuracy proxy | `CaptionStream` volatile → final |
| `speakers` | Distinct speaker labels shown, and live relabels per minute | `SpeakerLabelSmoother` |
| `launchToStartSeconds`, `startToFirstCaptionSeconds` | Speed to useful | launch sequence, `TranscriptionEngine` startup laps |
| `rating` + `ratingSkipped` | `rating: null` with `ratingSkipped: false` means the conversation was sent before the rating card appeared: *unrated*, not skipped | rating card |
| `settings.quietStop` | `fiveMinutes`, `fifteenMinutes`, `thirtyMinutes`, `never` | `IdleStop` |
| `ending.kind` | `userStop`, `quietStop`, `failure` (with `reason`, the plain-language text), `stuck`, `appClosed` | `CaptionSessionController`, `IdleStop`, `FailureReason` |
| `battery` | Battery drop scaled to 30 minutes; highest `ProcessInfo.thermalState` | `UIDevice.batteryLevel`, `ProcessInfo` |
| `micLevel` | Room loudness summary, never audio | `AudioLevel`, `ListeningActivityTracker` |
| `engine`, `engineFallback` | Which recognizer captioned the conversation (`parakeet-ultra-pal6` or `apple-speechanalyzer`; the last one used, if it switched) and why it left Parakeet (`loadFailed`, `memoryWarning`, `thermalCritical`, `noWordsFromSpeech`, `lowMemory`, `locale`, `repeatedFallbacks`, `modelMissing`), else `null`. Added for 1.1 build 7 (ADR 0025); additive, still schema 1 | `TranscriptionEngine.engineName` / `fallbackReason` via `CaptionUpdate` |
| `captionLanguage`, `captionLanguageChosen` | The caption language setting (BCP-47) the latest stretch ran with, and whether it was picked in Seal (Settings › Caption language or first run) rather than following the phone. Added for 1.1 build 11 (#288); additive, still schema 1; `null` for conversations recorded by build 10 or earlier | `CaptionLanguageCenter.current` / `followsDevice` |
| `faceToFace` | Face to face: each half's picked language (`owner` is her half), `null` for a half not picked; the whole field is `null` when face to face was off. With one half picked, that half's language captions everything (#208). Build 11 (#288) | `FaceToFaceSplit.captions` |
| `build` | The build that recorded this conversation. `app.build` is the build that sent the report, which can be later (#288) | `CFBundleVersion` at Start |
| `device.language` | The phone's first preferred language (BCP-47), to set beside `captionLanguage`. Build 11 (#288) | `Locale.preferredLanguages` |
| `earDelay` | "Speak it in my ear" latencies (#294): delay from phrase spoken to translation received (`translateDelay`), from translation ready to voice starting (`voiceStartDelay`), distance behind the speaker when voice finishes (`behindBy`), each as p50/p95/max and sample count; plus counters for repeats, translation misses, and voice cut-offs. Added build TBD (#294); additive, still schema 1; `null` for conversations recorded before this build | `EarDelayTracker`, `BetaFeedbackCenter.earX()` |

Size: about 1 KB per conversation, with no cap until sent (ADR 0023), so even 1,000 unsent conversations make a
report of about 1 MB, well within an iMessage attachment.

## How MARVIN ingests reports

Decision: ADR 0024. Texts arrive in the owner's Messages and sync to the Mac Mini, where attachments are stored
under `~/Library/Messages/Attachments/`. A MARVIN job on the Mini finds new `seal-feedback-*.json` files there and:

1. validates each against this schema (`schema: 1`) and skips duplicates by conversation `id`
2. appends them to a private local dataset (`~/.claude/seal-beta/reports.jsonl`), never the repo
3. summarises **per device model** (plain name, then split by build) and per build: report count, median rating,
   lag p50/p95, rewrite rate, relabels, endings, battery and thermal state, shown in the MARVIN dashboard;
   from build 7 also split by `engine`
4. files or updates clarity-captions tickets when a threshold is crossed (lag p95 > 2 s on a device model, any
   `stuck` ending, median rating ≤ 4 on a device model from at least 2 reports), quoting **only measurements,
   device and build**, never the tester's note or anything that identifies the sender

Reading `~/Library/Messages` needs Full Disk Access for the process that runs the job (macOS privacy protection);
the owner grants that once. The job never reads message text, only `seal-feedback-*.json` attachments. TestFlight's
own screenshot feedback and crash reports join the same per-device view later (ADR 0024, decision 6).
