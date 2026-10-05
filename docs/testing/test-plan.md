# Seal: test plan by environment

For the person running tests (facilitator) and for anyone reading results. The tester-facing, plain-language
guide is `human-testing-guide.md`; this document says **what to test, where, how to measure, and what to report**.
It replaces building a recorder into the app: everything below uses the phone's own screen recording.

Results feed: the restaurant-conditions test, the per-line background dimming work, the latency baseline
(caption speed must stay within 10% of baseline), and the usability test with the first user.

## 1. Record every session (header)

Date, tester, environment ID (section 3), number of people, noise level (a free decibel-meter app is fine,
note the rough dB), phone placement and distance, **mic mode** (Standard is the default; the developer panel,
shown by long-pressing the state word, offers Raw and Voice), phone model and iOS version, app build (commit
shown by TestFlight or Xcode), session length.

## 2. How to measure with no extra tooling

1. **Screen-record with the microphone on**: Control Center, long-press the record button, turn Microphone on,
   Start Recording. The video shows the captions and the audio carries the room, in one synchronized file.
2. Run the **reference script** (section 5) so there is a ground truth to compare against. For free conversation,
   keep a short note of who spoke in what order.
3. Review the recording afterwards (QuickTime, Photos, or any player that shows time):
   - **Lag**: pick 10 clearly spoken marker words. For each, note the time the word is spoken and the time it
     first appears on screen. Report the median and the worst.
   - **Word accuracy**: compare the final captions to the script. Count substitutions (S), deletions (D),
     insertions (I) against N words. Word error rate = (S + D + I) / N.
   - **Who's who**: count caption lines, and how many are attributed to the correct speaker. Note swaps and
     lines with no label.
   - **Over-capture**: count lines that came from people or sound outside your table (TV, other tables).
   - **Dropouts**: any stretch longer than 3 seconds where people were talking and nothing appeared.
   - **Stops and crashes**: any red "Stopped" message, with the time and what was on screen.
4. Rate **readability** and **usefulness** from 1 (bad) to 5 (very good), and write one sentence on the best and
   worst moment.

## 3. Environments

Each row is a separate session. Repeat the important ones (marked ★) in each mic mode.

| ID | Environment | Setup | People | Noise | What it answers |
|---|---|---|---|---|---|
| E1 | Quiet room, one on one | Phone on a table 3 ft away | 2 | under 40 dB | The baseline: best case for speed and accuracy |
| E2 | Quiet room, small group | Phone in the middle of the table | 4 | under 40 dB | Speaker separation with turn-taking and interruptions |
| E3 ★ | **Restaurant or café table** (real) | Phone flat on the table | 2 to 5 | real room, note dB | The primary environment: noise, overlap, distance |
| E4 ★ | Simulated restaurant at home | Play restaurant ambience from a speaker 6 to 10 ft away at about 65 to 70 dB | 2 to 4 | 65 to 70 dB | A repeatable stand-in for E3 for tuning |
| E5 | TV or music on in the room | TV at normal volume, people talking at the table | 2 to 3 | 55 to 65 dB | Does competing speech get captioned, and dimmed? |
| E6 | Family dinner | Phone mid-table | 6 or more | 60 to 70 dB | Many voices, heavy overlap, the 4-speaker limit |
| E7 | Meeting or classroom | Phone on a table or lectern, speaker 15 to 30 ft away | 1 speaker plus audience | 40 to 55 dB | Far-field single speaker |
| E8 | Car, as a passenger | Phone in a holder, engine and road noise | 2 to 3 | 60 to 70 dB | Steady noise. **Never read it while driving.** |
| E9 | Outdoors | Phone held or on a bench, wind and street noise | 2 | 55 to 75 dB | Wind and open-air noise |
| E10 | Fast, soft and accented speech | Quiet room, scripted | 2 | under 40 dB | What gets missed for hard-to-recognize speech |

**Distance ladder** for E1, E3 and E4: repeat a short segment with the talker at 1 ft, 3 ft, 6 ft and 10 ft.
Note the farthest distance where the words are still mostly right.

## 4. Per-session procedure

1. Tell everyone at the table you are testing a captioning app. Get a clear yes before recording.
2. Fill in the header (section 1). Start the screen recording with the microphone on.
3. Start captions in Seal. Set the phone down where the environment says.
4. Say a spoken marker such as "test one", then run the script or talk naturally for 3 to 5 minutes.
5. Include one deliberate overlap (two people talking at once for a few seconds) and one quiet aside.
6. Stop captions, stop the recording, and fill in the sheet while it is fresh.
7. Analyze (section 2) within a day. Delete recordings once the numbers are written down (section 7).

## 5. Reference scripts

Read at normal pace. These lines are from the public Harvard Sentences (List 1) and the Rainbow Passage.

- **Short sentences** (read two lines each, alternating speakers):
  1. The birch canoe slid on the smooth planks.
  2. Glue the sheet to the dark blue background.
  3. It's easy to tell the depth of a well.
  4. These days a chicken leg is a rare dish.
  5. Rice is often served in round bowls.
  6. The juice of lemons makes fine punch.
- **Names and numbers** (tests vocabulary): "Tell Jennifer, Marcus and Priya the meeting moved to 3:45 on Thursday,
  room 212, and the phone number is 555-0143."
- **Rainbow Passage opening**: "When the sunlight strikes raindrops in the air, they act as a prism and form a
  rainbow. The rainbow is a division of white light into many beautiful colors."
- **Fast and soft**: repeat three of the short sentences once quickly and once in a quiet voice.

## 6. Draft targets (to be revised after the first data)

These are starting points, not promises. Adjust once real numbers exist.

| Measure | Quiet (E1, E2) | Noisy (E3 to E9) |
|---|---|---|
| Median lag | 1.5 s or less | 2 s or less |
| Word error rate | 15% or less | 30% or less |
| Speaker label accuracy | 85% or more | 70% or more |
| Over-capture | none | few, and ideally dimmed |
| Dropouts over 3 s | none | rare |
| Stops or crashes | none | none |

## 7. Privacy and handling

Recordings contain people's voices. Keep them on your device, never commit them to the repo, never post them,
and delete them once the numbers are recorded. Record only your own table, never strangers. Results (numbers
and notes) go in `docs/testing/results/` as a dated CSV; use `results-template.csv`.

## 8. Turning results into work

A measurement below target becomes an issue that states the environment ID, the numbers, and the target.
Cross-check lag against the latency baseline so new features cannot quietly slow captions.
