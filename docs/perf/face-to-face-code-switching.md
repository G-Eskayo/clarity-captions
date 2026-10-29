# Face to face: code-switching and the matching numbers compared (#208, items 3 and 4)

Measured 2026-10-29 on the Mac mini (Apple M4, macOS 26.5.1), release build.
Code: `Packages/CaptionCore/Tests/CaptionCoreTests/FaceToFaceCodeSwitchingEvalTests.swift`, corpus converter
`scripts/codeswitch-eval/miami_to_json.py`. Raw numbers: [face-to-face-code-switching-results.json](face-to-face-code-switching-results.json).

```
python3 scripts/codeswitch-eval/miami_to_json.py <miami CHAT dir> /tmp/miami.json
CAPTION_CODESWITCH_JSON=/tmp/miami.json CAPTION_CODESWITCH_OUT=/tmp/results.json \
  swift test -c release -Xswiftc -enable-testing --filter FaceToFaceCodeSwitchingEval
```

## The question

The owner, on #199: people practise the other language or throw in words they're learning. A few minutes in, Seal
should know who speaks Spanish and who speaks English, and mixed ("Spanglish") lines shouldn't move anyone. #199
moved a voice after **2 sure lines in a row** in the other language. And the lock numbers (4+ words, 95% sure) were
to be tested against alternatives for accuracy, and the winner picked on numbers.

## What was built (item 3)

A confidence per voice, in `LanguageMatchPolicy.correction`:

- Each finished line of 4+ words from the voice's own engine is evidence. Sure of the voice's language: **+1**, up to a
  cap. Sure of the other language: **−1**. Mixed or unclear: **nothing**, so Spanglish neither moves anyone nor
  wears the confidence down.
- The voice moves when its confidence reaches **−2**. Right after a lock that's two lines, as in #199, so an early
  mistake is still fixed fast. Once their language has been heard for a while it takes many more.
- The cap means a voice that really changes (the diarizer handing one person's slot to the other) is always followed.
- Unclear lines bring the other engine back to check after 2 in a row, plus one more for each point of confidence. In
  a check, each sure verdict counts as one line.

Tests came first: `FaceToFaceCodeSwitchingTests` (13), including back-and-forth, practice lines, 300 Spanglish lines,
a capped confidence and real NaturalLanguage lines. Changing the cap, the check, mixed-line erosion or a one-verdict
move each breaks them.

## Data

**Bangor Miami corpus** ([BangorTalk](https://bangortalk.org.uk/speakers.php?c=miami), released under GNU GPL v3).
56 real recorded informal conversations between Spanish-English bilinguals in Miami, about 25 hours of speech, 45,576
utterances. Each has its time and a language tag on every word, from human transcribers. It's test data on the Mac only:
never committed, never shipped, never on a public page. **No audio was transcribed by anything:** the words are the
corpus's own transcripts.

- **Each speaker's language:** the majority of their tagged words over the whole conversation. 99 speakers have 40+
  words. **75 are clearly one language** (70%+ of words; 55 English, 20 Spanish). **24 are real bilinguals** (under
  70%) with no right half: for them, only the bouncing is measured.
- Even the clear speakers code-switch. 12 or 13 of the 75 get a wrong first lock under every set of numbers, because
  their first lines really are in their other language ("ay Dios mío", "me dice ella que trabaja en una tienda de
  furniture").

## Method

Each speaker is a voice. Their lines go in time order through the real `SpeakerLanguages` and Apple's NaturalLanguage
(English vs Spanish, as on the device), a few words at a time as the engines report them, then finished. Both engines
hear a voice that has no language yet or is being checked; a locked voice is heard only by its own. A voice's lines
always show on its current half, so a line counts as **on the wrong half** if the voice sat on the wrong half when it
was said.

Four scenarios, the same for every set of numbers:

1. **Natural:** the conversations as recorded, diarizer perfect.
2. **Mislabelled start** (#199's measured limit): another person's first 2 lines, in the other language, land under
   this voice. Measured: lines until the voice is on its right half.
3. **Swapped voice at 3 minutes:** from 3 minutes on, the slot is really another person, speaking the other language
   (40 real lines). Measured: how long until the voice follows.
4. **Swapped voice at 10 minutes** (80 lines): the same, once a long-known voice's confidence has reached its cap. This
   is the cost of a sticky cap.

**The rule for the winner, set before the combined runs:** the fewest lines on the wrong half, all four scenarios
added up. That weighs "don't move people" (1) against "follow a real change" (2–4).

**Stand-ins:** the words are the human transcript (no engine errors), and the diarizer is perfect except where a
scenario breaks it on purpose. Runs are deterministic (checked twice, byte for byte).

## Results

Sorted by the winner rule. "Lock 4/99" means 4+ words, 99% sure. Rows without a cap use cap 8 (the first value tried);
rows named "confidence cap N" use lock 4/95. Timings are median · 90th percentile.

| Numbers | Wrong-half lines, all scenarios | Natural: wrong-half lines | Natural: wrong moves | Natural: voices moved twice+ | First lock right | Both engines on | Bilinguals moved twice+ | Mislabelled start: lines to fix | Swapped at 3 min: seconds to follow | Swapped at 10 min: seconds to follow |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| lock 4/99, cap 12 | 4503 (4.88%) | 3.03% | 27 | 18/75 | 63/75 | 1.25% | 23/24 | 6 · 23 lines | 38 s · 57 s | 42 s · 58 s |
| lock 4/99, cap 16 | 4535 (4.91%) | 2.59% | 18 | 15/75 | 63/75 | 1.13% | 22/24 | 6 · 23 lines | 52 s · 74 s | 54 s · 74 s |
| lock 4/99 | 4543 (4.92%) | 3.61% | 39 | 23/75 | 63/75 | 1.49% | 24/24 | 6 · 23 lines | 27 s · 41 s | 29 s · 43 s |
| lock 4/99, cap 8 | 4543 (4.92%) | 3.61% | 39 | 23/75 | 63/75 | 1.49% | 24/24 | 6 · 23 lines | 27 s · 41 s | 29 s · 43 s |
| lock 4/95, cap 16 | 4566 (4.94%) | 2.65% | 20 | 15/75 | 62/75 | 1.05% | 22/24 | 6 · 23 lines | 52 s · 74 s | 54 s · 74 s |
| confidence cap 12 | 4597 (4.98%) | 3.18% | 29 | 19/75 | 62/75 | 1.18% | 23/24 | 6 · 23 lines | 38 s · 57 s | 40 s · 58 s |
| lock 6/99 | 4633 (5.02%) | 3.25% | 28 | 17/75 | 64/75 | 1.33% | 23/24 | 7 · 26 lines | 35 s · 50 s | 35 s · 50 s |
| lock 6/99, cap 8 | 4633 (5.02%) | 3.25% | 28 | 17/75 | 64/75 | 1.33% | 23/24 | 7 · 26 lines | 35 s · 50 s | 35 s · 50 s |
| lock 6/99, cap 12 | 4646 (5.03%) | 2.59% | 22 | 16/75 | 64/75 | 1.14% | 21/24 | 7 · 26 lines | 51 s · 71 s | 54 s · 71 s |
| lock 4/95 | 4650 (5.03%) | 3.77% | 43 | 23/75 | 62/75 | 1.39% | 24/24 | 6 · 23 lines | 27 s · 41 s | 28 s · 43 s |
| lock 4/99, cap 20 | 4657 (5.04%) | 2.29% | 16 | 13/75 | 63/75 | 1.06% | 20/24 | 6 · 23 lines | 61 s · 88 s | 68 s · 92 s |
| confidence cap 8, move at -3 | 4682 (5.07%) | 3.81% | 42 | 22/75 | 62/75 | 1.45% | 24/24 | 6 · 23 lines | 27 s · 41 s | 28 s · 43 s |
| confidence cap 20 | 4691 (5.08%) | 2.34% | 18 | 14/75 | 62/75 | 1.01% | 20/24 | 6 · 23 lines | 62 s · 88 s | 68 s · 92 s |
| lock 3/90 | 4713 (5.10%) | 4.08% | 61 | 26/75 | 61/75 | 1.51% | 24/24 | 5 · 21 lines | 24 s · 39 s | 24 s · 37 s |
| lock 6/99, cap 16 | 4772 (5.17%) | 2.15% | 14 | 11/75 | 64/75 | 1.00% | 18/24 | 7 · 26 lines | 61 s · 84 s | 70 s · 88 s |
| lock 6/99, cap 20 | 5043 (5.46%) | 2.05% | 12 | 10/75 | 64/75 | 1.09% | 17/24 | 7 · 26 lines | 61 s · 102 s | 88 s · 108 s |
| lock 4/99, cap 30 | 5070 (5.49%) | 1.89% | 12 | 10/75 | 63/75 | 0.94% | 17/24 | 6 · 23 lines | 69 s · 118 s | 98 s · 127 s |
| lock 4/95, cap 30 | 5104 (5.53%) | 1.96% | 14 | 11/75 | 62/75 | 0.93% | 17/24 | 6 · 23 lines | 70 s · 117 s | 98 s · 127 s |
| confidence cap 4 | 5169 (5.60%) | 4.97% | 102 | 34/75 | 62/75 | 2.22% | 24/24 | 6 · 18 lines | 16 s · 24 s | 16 s · 23 s |
| lock 4/99, cap 40 | 5487 (5.94%) | 1.59% | 10 | 9/75 | 63/75 | 0.89% | 15/24 | 6 · 23 lines | 72 s · 134 s | 129 s · 167 s |
| lock 4/95, cap 40 | 5531 (5.99%) | 1.67% | 13 | 11/75 | 62/75 | 0.90% | 15/24 | 6 · 23 lines | 71 s · 134 s | 129 s · 167 s |
| lock 6/99, cap 30 | 5536 (5.99%) | 1.76% | 10 | 8/75 | 64/75 | 0.89% | 16/24 | 7 · 26 lines | 67 s · 121 s | 128 s · 158 s |
| lock 8/95 | 5634 (6.10%) | 3.66% | 17 | 13/75 | 61/75 | 1.15% | 19/24 | 9 · 32 (1 never) lines | 44 s · 67 s | 51 s · 67 s |
| lock 6/99, cap 40 | 6091 (6.59%) | 1.76% | 10 | 8/75 | 64/75 | 0.88% | 15/24 | 7 · 26 lines | 66 s · 120 s (1 never) | 160 s · 203 s |
| streak 3 | 7488 (8.11%) | 8.17% | 228 | 47/75 | 62/75 | 3.49% | 24/24 | 6 · 14 lines | 9 s · 18 s | 10 s · 18 s |
| streak 2 (#199) | 8212 (8.89%) | 9.35% | 397 | 50/75 | 62/75 | 0.89% | 24/24 | 4 · 11 lines | 6 s · 12 s | 6 s · 12 s |
| streak 1 | 9760 (10.57%) | 11.59% | 1065 | 67/75 | 63/75 | 0.40% | 24/24 | 2 · 7 lines | 3 s · 6 s | 3 s · 6 s |

## What the numbers say

- **The growing confidence beats #199's rule by a wide margin.** On real conversation, lines on the wrong half fall from
  9.35% (2 lines in a row) to 3.03%, wrong moves from 397 to 27, and voices moved twice or more from 50 of 75 to 18.
  Stricter streaks (3 in a row) help only a little (8.17%, 228 wrong moves).
- **The lock: 99% beats 95%.** At every cap: fewer wrong moves, one more speaker locked right first time (63 vs 62),
  and no slower to fix a mislabelled start (6 lines median either way). 6+ words at 99% gets one more first lock
  right (64) but is slower to fix a mislabelled start (7 lines median) and loses overall. 8+ words is worse still. A looser lock
  (3 words at 90%) loses too.
- **The cap is a trade-off.** A bigger cap means fewer wrong moves in real conversation (cap 40: 1.62% on the wrong half),
  but a really swapped voice is followed later: about 40 s at cap 12, 55 s at cap 16, 70 s at cap 20 and over 2
  minutes at cap 40 (swapped at 10 minutes). Caps 8 to 16
  are within 1% of each other on the total. Above 16 the total gets worse.
- **Bilinguals still get moved** (23 of 24 more than once at cap 12). Someone who really speaks both languages about
  equally has no right half to find. Item 1 fixes this better than any number: once each half picks its language,
  the voice only has to be matched to a person.

## Chosen

**Lock: 4+ words, 99% sure. Correct: confidence, cap 12, move at −2.** It's the winner under the rule set beforehand:
4,503 lines on the wrong half across all scenarios (4.88%), against 8,212 (8.89%) for #199's numbers. On real
conversation: 3.03% of lines on the wrong half and 27 wrong moves, against 397. A real swap is followed in about 40 s
(58 s at the 90th percentile).

Cap 16 is 0.7% behind on the total, with fewer wrong moves (18) and slower following (54 s). The PR asks the owner
which matters more.

## Limits

- **Transcripts, not engines.** Real engines garble some words, so more lines will be unclear. Unclear lines move no one
  under the new rule, so this should cost checks (battery), not wrong moves. Not measured here.
- **A perfect diarizer**, apart from the two broken scenarios. Similar voices at a real table are still untested
  (ticket item 5: the iPad table test).
- **Mostly English.** 55 of the 75 clear speakers are English-first. Miami has no other language pair.
- **Informal talk between bilinguals.** These speakers switch far more than a traveller and a ticket clerk would, so this
  is a hard test for "don't move people" and an easy one for locking.
