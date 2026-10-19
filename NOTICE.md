# Notices

Autohand Voice is based on the Dictate project:

- Source: https://github.com/0xbrando/dictate
- Original author: brando
- License: MIT

The original copyright notice and MIT license remain in `LICENSE`.
Dependency and model licenses are documented in `LICENSES.md`.

The optional Qwen3-ASR engine vendors a modified subset of speech-swift
(https://github.com/soniqo/speech-swift, tag v0.0.28, Apache-2.0, Copyright
2025 Ivan Digital). Its license and a list of changes are in
`Sources/AutohandVoiceQwenASR/Vendor/SpeechSwift/`.

The MLX runtime for the on-device Talk model ports a modified subset of
mlx-swift-lm (https://github.com/ml-explore/mlx-swift-lm, PR #630 head
a3596e4, MIT, Copyright (c) 2024 ml-explore): the Qwen3.5 hybrid model, the
gated-delta Metal kernel and the Hadamard-rotated quantized layers. Its
license and a list of changes are in
`Sources/AutohandVoiceBonsaiMLX/Vendor/MLXSwiftLM/`.

Ternary Bonsai 2 is created using Bonsai by Prism ML (Copyright 2026-present
Prism ML, Inc., Apache-2.0), built from Qwen3.5-2B (Copyright 2026 Alibaba
Cloud, Apache-2.0). It is downloaded on request and never bundled.
