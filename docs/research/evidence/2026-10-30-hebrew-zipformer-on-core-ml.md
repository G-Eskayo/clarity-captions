# The Hebrew zipformer on Core ML: 4-bit keeps its accuracy at 39 MB; 3-bit costs voice-note accuracy and memory

- **Source:** our own measurement, #220, 2026-10-30, M4 Mac mini, macOS 26.5.1:
  [`hebrew-coreml-comparison.md`](../../perf/hebrew-coreml-comparison.md), method in
  [`hebrew-coreml-design.md`](../../perf/hebrew-coreml-design.md). The ivrit.ai 66M streaming zipformer
  ([`ivrit-ai/zipformer2-66m-streaming-he`](https://huggingface.co/ivrit-ai/zipformer2-66m-streaming-he) @ `ee769a2`,
  CC BY 4.0) converted from its ONNX export to Core ML by our own translator, then compressed weight-only. Scored with
  #217's harness on ivrit.ai eval-d1 @ `7899b04` and eval-whatsapp @ `1267f61`. Everything ran locally.
- **What we took:** the conversion is faithful: Core ML fp32 scores 2.4% CER on conversation against sherpa-onnx int8's
  2.5% (#217), with the same interval. Compressed encoders: int8 70.6 MB, 6-bit 55.5 MB and **4-bit 38.6 MB** all
  score 2.4% CER on conversation and 4.2–4.3% on voice notes, the same as int8. 3-bit (30.4 MB) holds on conversation
  (2.6%) but slips on voice notes (5.4% CER, 11.1% WER against 8.6%), and on the app's path it held 545 MB while
  captioning against 157 MB for 4-bit. 2-bit fails (35% CER). Compressing the six convolutions that read the fbank
  silenced the 4- and 2-bit encoders entirely; they stay fp16. The Apple Neural Engine compiler rejects the encoder,
  so it runs on CPU and GPU: about 15 ms per 1.28 s chunk on the M4, 60 to 90 times faster than real time.
- **Confidence:** Ours. Same caveats as #217: eval-d1 is one podcast episode, the model trained on ivrit.ai data, and
  these are Mac runs (latency is Seal's added delay, not the model's emission lag). The memory figures come from one
  sentence in the Swift integration test; why 3-bit uses more memory is inferred, not confirmed.
- **Drives:** which Hebrew build ships bundled on every device (#220, #222): 4-bit is recommended to the owner as a
  Decision; it's about half of the 75 MB he asked to beat.
- **Public use:** Careful ("Seal's Hebrew engine is under 40 MB and as accurate as the uncompressed model, in our
  tests on a podcast episode and 54 voice notes").
