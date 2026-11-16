# Hebrew engine accuracy (#201)

## ivrit.ai eval-d1 (conversation)

| Engine | WER | 95% CI | CER | 95% CI |
|---|---:|---|---:|---|
| Parakeet-He (thewh1teagle, transformers) | 5.2% | 4.5% – 5.9% | 2.4% | 2.0% – 2.9% |
| ivrit.ai zipformer2 66M (sherpa-onnx, int8) | 5.0% | 4.2% – 5.6% | 2.5% | 2.1% – 2.8% |
| Apple DictationTranscriber he-IL | 17.8% | 15.3% – 20.6% | 10.4% | 7.8% – 13.3% |

## ivrit.ai eval-whatsapp (voice notes)

| Engine | WER | 95% CI | CER | 95% CI |
|---|---:|---|---:|---|
| ivrit.ai Whisper large-v3 turbo (transformers), reference only | 7.0% | 6.1% – 8.0% | 3.2% | 2.8% – 3.9% |
| Parakeet-He (thewh1teagle, transformers) | 8.2% | 7.3% – 9.2% | 3.8% | 3.4% – 4.4% |
| Apple DictationTranscriber he-IL | 22.3% | 20.5% – 24.2% | 11.6% | 10.2% – 13.1% |
