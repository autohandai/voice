# Dependency and model licenses

| Component | Version | License | Source |
|---|---:|---|---|
| FluidAudio | 0.14.4 | Apache-2.0 | https://github.com/FluidInference/FluidAudio |
| NVIDIA Parakeet TDT 0.6B v3 | Apache-2.0 | https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3 |
| MLX Swift (optional Qwen3-ASR engine) | 0.31.4 | MIT | https://github.com/ml-explore/mlx-swift |
| Swift Numerics (MLX Swift dependency) | 1.1.1 | Apache-2.0 | https://github.com/apple/swift-numerics |
| speech-swift (vendored subset, modified) | v0.0.28 | Apache-2.0 | https://github.com/soniqo/speech-swift |
| Qwen3-ASR 0.6B MLX 4-bit (downloaded on demand) | bc441bd | Apache-2.0 | https://huggingface.co/aufklarer/Qwen3-ASR-0.6B-MLX-4bit |
| llama.cpp (on-device Talk, GGUF runtime) | b11721 | MIT | https://github.com/ggml-org/llama.cpp |
| mlx-swift-lm (ported subset, modified; Talk MLX runtime) | PR #630 a3596e4 | MIT | https://github.com/ml-explore/mlx-swift-lm |
| Ternary Bonsai 2 2B GGUF (downloaded on demand) | 683f7be | Apache-2.0 | https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-gguf |
| Ternary Bonsai 2 2B MLX 2-bit (downloaded on demand) | 1c6cbae | Apache-2.0 | https://huggingface.co/prism-ml/Ternary-Bonsai-2-2B-mlx-2bit |

Apple frameworks including AppKit, AVFoundation, ApplicationServices, CoreML,
and Foundation are supplied by macOS and are not redistributed by this
repository.

The project itself remains MIT licensed. See [LICENSE](LICENSE) and
[NOTICE.md](NOTICE.md).
