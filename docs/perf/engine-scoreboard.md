# Engine Scoreboard

Unified performance data for engine choice across captions, translation, and in-ear voice.
Sources: #145, #158, #201, #159, #237, #200. Routing, gaps, Android column, and size cleanup deferred to later steps.

## Captions

### English

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| parakeet-fluidaudio (parakeet-ultra-coreml) | 13.8% | 12.7%–14.7% | iPhone |
| parakeet-fluidaudio (ultra-pal6) | 13.8% | 12.8%–14.8% | iPhone |
| parakeet-fluidaudio (ultra-pal4) | 14.8% | 13.7%–15.8% | iPhone |
| parakeet-fluidaudio (parakeet-tdt-0.6b-v2-coreml) | 15.5% | 14.5%–16.6% | iPhone |
| sherpa-onnx | 16.1% | 14.9%–17.2% | iPhone |
| parakeet-fluidaudio (parakeet-redux-coreml) | 16.7% | 15.5%–18.0% | iPhone |
| apple-speechanalyzer | 17.2% | 16.0%–18.4% | iPhone |

### Hebrew

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| Parakeet-He (thewh1teagle, transformers) | 8.2% | 7.3%–9.2% | Mac |
| ivrit.ai zipformer2 66M (sherpa-onnx, int8) | 8.6% | 7.6%–9.6% | Mac |
| Apple DictationTranscriber he-IL | 22.3% | 20.5%–24.2% | Mac |

### Spanish

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| Parakeet Ultra, FluidAudio (Core ML) | 2.8% | 2.4%–3.3% | Mac |
| Parakeet Ultra, sherpa-onnx (ONNX, community export) | 3.2% | 2.7%–3.7% | Mac |
| Apple SpeechAnalyzer, es-ES | 4.0% | 3.4%–4.5% | Mac |

### French

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| Parakeet Ultra, FluidAudio (Core ML) | 4.5% | 3.9%–5.1% | Mac |
| Parakeet Ultra, sherpa-onnx (ONNX, community export) | 6.2% | 5.5%–6.9% | Mac |
| Apple SpeechAnalyzer, fr-FR | 7.5% | 6.7%–8.3% | Mac |

### German

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| Parakeet Ultra, FluidAudio (Core ML) | 4.4% | 3.8%–5.0% | Mac |
| Parakeet Ultra, sherpa-onnx (ONNX, community export) | 5.3% | 4.7%–6.0% | Mac |
| Apple SpeechAnalyzer, de-DE | 7.2% | 6.5%–7.9% | Mac |

### Italian

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| Parakeet Ultra, FluidAudio (Core ML) | 2.2% | 1.8%–2.5% | Mac |
| Apple SpeechAnalyzer, it-CH | 3.6% | 3.1%–4.1% | Mac |

### Portuguese

| Engine | WER | 95% CI | Device |
|---|---|---|---|
| Parakeet Ultra, FluidAudio (Core ML) | 3.9% | 3.3%–4.5% | Mac |
| Apple SpeechAnalyzer, pt-BR | 5.3% | 4.7%–6.0% | Mac |

## Translation

| Engine | Language pair | chrF | 95% CI | Device |
|---|---|---|---|---|
| apple | en-es | 56.8 | 56.2–57.4 | Mac |
| opus-mt-big | en-es | 56.5 | 55.9–57.1 | Mac |
| opus-mt | en-es | 55.0 | 54.3–55.6 | Mac |
| opus-mt-greedy | en-es | 54.8 | 54.2–55.4 | Mac |
| apple | en-fr | 50.1 | 49.5–50.7 | Mac |
| opus-mt | en-fr | 48.3 | 47.7–48.9 | Mac |
| opus-mt-greedy | en-fr | 47.9 | 47.2–48.5 | Mac |
| opus-mt-big | en-fr | 48.0 | 47.2–48.9 | Mac |

## In-Ear Voice Translation

| Engine | Component | Latency (ms) | Device |
|---|---|---|---|
| Apple Translation + device voice | End of speech → finished caption line | 859 | Mac |
| Apple Translation + device voice | Finished translation → first audible sample (warm voice) | 36 | Mac |
| Apple Translation + device voice | First sentence in a voice (cold) | 225 | Mac |

## Model Sizes

| Model | On disk (MB) | Compressed (MB) | Device |
|---|---:|---:|---|
| parakeet-redux-coreml | 220.0 | 177.0 | iPhone |
| parakeet-tdt-0.6b-v3-coreml-int4 | 336.0 | 254.0 | iPhone |
| ultra-pal4 | 350.0 | 320.0 | iPhone |
| parakeet-tdt-0.6b-v2-coreml | 464.0 | 451.0 | iPhone |
| ultra-pal6 | 498.0 | 485.0 | iPhone |
| parakeet-ultra-coreml | 632.0 | 555.0 | iPhone |
| Sortformer v2.1 fp16 | 240.6 | 220.4 | iPhone |
