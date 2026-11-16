# Live Translation in your ear: spike (#233)

## Speech to voice lag

| Step | Median | p95 | Where measured |
|---|---|---|---|
| End of speech → finished caption line | **859 ms** | 1157 ms | Mac, EdAcc real speech fed in real time, 87 lines |
| Translate one caption line (Apple Translation) | 51–70 ms | 69–110 ms | Mac, 19 languages, #159 |
| Finished translation → first audible sample (warm voice) | 10–61 ms Mac, 8–41 ms simulator | up to 140 ms Mac, 102 ms simulator | 10 languages × 10 lines |
