# Fewer bits didn't make Parakeet Ultra faster on the M4

- **Source:** our own run for #203 "[E] 2-bit north star, English first", M4 Mac mini, 2026-10-29: EdAcc shard 1
  (548 clips, 1.1 h), one run each of the published int8 Ultra build, `ultra-pal6` and `ultra-pal4` (#150's
  builds) with `engine-eval run` and `engine-eval latency`, machine load sampled every 30 s
  (`~/edacc-eval/results-203/baseline/`). Rows in `docs/perf/engine-accuracy-comparison.md`, section "Low-bit
  builds (#203)".
- **What we took:** on a quiet machine (load average median 3.8 on 10 cores, CPU 63% idle), 4-bit decoded at the
  same speed as 6-bit (108.2x vs 108.3x real time), and both were about 12% slower than int8 (122.5x). #150's run on
  the same shard showed the same order (121.6x / 113.4x / 112.6x). Palettized weights save disk, not decode time,
  on the Mac. The 3-bit and 2-bit builds aren't made yet: the fp16 export env couldn't be installed on the
  unattended run.
- **Confidence:** Ours (one machine, one shard, one run per clip; the Mac's Neural Engine, not the iPhone's).
- **Drives:** #203's speed expectation: don't present lower bits as faster, and judge the 2-bit builds on size and
  WER. It agrees with Apple's note that palettization mainly saves memory.
- **Public use:** Careful (Mac numbers, not the phone).
