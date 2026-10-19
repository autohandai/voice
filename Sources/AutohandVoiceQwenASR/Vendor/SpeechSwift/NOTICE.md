# speech-swift (vendored subset)

- Source: https://github.com/soniqo/speech-swift
- Tag: `v0.0.28` (commit `231f8eb9f0971fee335fef49f42d2975e4fbf8bc`)
- Copyright 2025 Ivan Digital
- License: Apache License 2.0 (see `LICENSE` in this directory)

Only the offline (non-streaming) Qwen3-ASR transcription path with the MLX
quantized text decoder is vendored. Files are renamed `<upstream module>-
<upstream file>.swift`:

| File | Upstream path |
|---|---|
| `Qwen3ASR-AudioEncoder.swift` | `Sources/Qwen3ASR/AudioEncoder.swift` |
| `Qwen3ASR-AudioPreprocessing.swift` | `Sources/Qwen3ASR/AudioPreprocessing.swift` |
| `Qwen3ASR-Configuration.swift` | `Sources/Qwen3ASR/Configuration.swift` |
| `Qwen3ASR-QuantizedTextDecoder.swift` | `Sources/Qwen3ASR/QuantizedTextDecoder.swift` |
| `Qwen3ASR-Qwen3ASR.swift` | `Sources/Qwen3ASR/Qwen3ASR.swift` |
| `Qwen3ASR-WeightLoading.swift` | `Sources/Qwen3ASR/WeightLoading.swift` |
| `MLXCommon-PreQuantizedEmbedding.swift` | `Sources/MLXCommon/PreQuantizedEmbedding.swift` |
| `MLXCommon-QuantizedMLP.swift` | `Sources/MLXCommon/QuantizedMLP.swift` |
| `MLXCommon-SDPA.swift` | `Sources/MLXCommon/SDPA.swift` |
| `MLXCommon-WeightLoading.swift` | `Sources/MLXCommon/WeightLoading.swift` |
| `AudioCommon-Tokenizer.swift` | `Sources/AudioCommon/Tokenizer.swift` |

## Changes made for Autohand Voice

- Every file carries a vendoring header and is wrapped in `#if arch(arm64)`:
  MLX runs only on Apple Silicon GPUs, so the x86_64 slice never compiles
  these code paths.
- `import MLXCommon` / `import AudioCommon` were removed (everything lives in
  the single `AutohandVoiceQwenASR` module) and `public` declarations were
  made internal so the vendored types are not part of this module's API.
- `Qwen3ASR.swift` was trimmed to single-clip transcription: batched decoding,
  the Hugging Face Hub download (`fromPretrained`, `HuggingFaceDownloader`),
  the 1.7B model-size detection and RAM guards, `MetalBudget.pinMemory()`
  (Metal wired-memory pinning), and load-time memory logging were removed. A
  `load(from:)` initializer loads the 0.6B 4-bit model from a local,
  already verified directory. Missing decoder or tokenizer now throws
  instead of returning a placeholder string.
- `WeightLoading.swift`: forced-aligner and float-decoder loaders and all
  `print` calls were removed (stdout carries the STT helper's JSON protocol).
- `Tokenizer.swift`: load logging to stderr and `debugTokenMappings()` were
  removed.
- `AudioPreprocessing.swift` resamples through `AudioFileLoader.resample`,
  which Autohand Voice provides in `Qwen3AudioInput.swift` (AVAudioConverter)
  instead of speech-swift's AudioCommon.

The model download, checksum verification, cache location, runtime gating
and the public `Qwen3SpeechRecognizer` API are Autohand Voice code outside
this directory.
