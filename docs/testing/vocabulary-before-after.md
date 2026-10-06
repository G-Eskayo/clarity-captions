# Vocabulary Testing: Before-and-After Procedure

## Purpose
Verify that custom vocabulary (words and names added in Settings) improves caption accuracy for those words.

## Test Line
Use the **Names and numbers** line from the standard test plan:

> "Tell Jennifer, Marcus and Priya the meeting moved to 3:45 on Thursday, room 212, and the phone number is 555-0143."

(Source: `docs/testing/test-plan.md:77`)

## Procedure

### Run 1: Baseline (No Vocabulary)
1. Launch Seal.
2. Open Settings → Words and names.
3. Verify the text field is empty. If not, clear it and tap Done.
4. Tap Start and hold the device steady.
5. Speak the test line aloud, naturally and clearly.
6. Wait for captions to settle (all text marked "final").
7. Manually record the captions output for the names: Jennifer, Marcus, Priya, and numbers: 3:45, Thursday, 212, 555-0143.

### Run 2: With Vocabulary
1. Open Settings → Words and names.
2. Add one entry per line:
   ```
   Jennifer
   Marcus
   Priya
   555-0143
   ```
   (Optional: add "3:45", "Thursday", "212" if the test needs more coverage.)
3. Tap Done (vocabulary is saved automatically on each edit).
4. Tap Start and hold the device steady.
5. Speak the exact same test line aloud.
6. Wait for captions to settle.
7. Manually record the captions output for the same words/numbers as Run 1.

## Reporting Results
Compare the two runs **word-by-word** for the four key names/numbers:

| Item | Baseline | With Vocabulary | Match? |
|------|----------|-----------------|--------|
| Jennifer | [baseline] | [with vocabulary] | ✓ or ✗ |
| Marcus | [baseline] | [with vocabulary] | ✓ or ✗ |
| Priya | [baseline] | [with vocabulary] | ✓ or ✗ |
| 555-0143 | [baseline] | [with vocabulary] | ✓ or ✗ |

**Pass criterion:** All four items match exactly in the "With Vocabulary" column (or match better than baseline if baseline was already incorrect).

## Notes
- The speech recognizer's output depends on mic mode, room noise, speaker accent, and pace. Runs should be in the same physical location.
- Vocabulary entries are stored on-device, survive app relaunches, and take effect the next time captioning starts (no app restart needed).
- If accuracy improved, it confirms the feature works. If no change, room noise or model confidence may dominate; repeating with clearer audio or a louder room may help.
