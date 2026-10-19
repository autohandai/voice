# mlx-swift-lm (ported subset)

- Source: https://github.com/ml-explore/mlx-swift-lm
- Revision: PR #630 ("add Bonsai 2 27B support"), head commit
  `a3596e4d3c8484a010c811021426d26dff1f365a`, on top of `main` at
  `48114eedf3c3d4a682a6b1d644cc5af5c2945d10`
- Copyright (c) 2024 ml-explore
- License: MIT (see `LICENSE` in this directory)

mlx-swift-lm needs SwiftPM tools 6.2+, so the parts Autohand Voice needs are
ported onto mlx-swift 0.31.4 directly instead of depending on the package.

| File | Upstream paths |
|---|---|
| `MLXLMCommon-GatedDelta.swift` | `Libraries/MLXLMCommon/GatedDelta.swift` |
| `MLXLLM-PrismHadamardQwen35.swift` | `Libraries/MLXLLM/Models/Qwen35.swift`, `Libraries/MLXLLM/Models/Qwen3Next.swift`, `Libraries/MLXLLM/Models/PrismHadamardQwen35.swift`, `Libraries/MLXLMCommon/HadamardQuantized.swift`, `Libraries/MLXLMCommon/KVCache.swift` (`KVCacheSimple`) |

`SignedHadamard.swift` (one level up) follows `SignedBlockHadamard` from
`HadamardQuantized.swift`.

## Changes made for Autohand Voice

- Every file carries a porting header and is wrapped in `#if arch(arm64)`:
  MLX runs only on Apple Silicon GPUs, so the x86_64 slice never compiles
  these code paths.
- Only the dense Qwen3.5 text model is kept: no MoE, MTP/speculative
  decoding, vision tower, `compile` traces, fused projections, training
  (custom VJP) paths, adapters or model registry.
- Layers hold their arrays directly and are built from the safetensors
  dictionary by name, instead of `Module` reflection and `update(parameters:)`;
  the pack's manifest (`config.json` `modules`) decides which projections are
  Hadamard-rotated quantized layers.
- The gated-delta Metal kernel keeps upstream's arithmetic (Kahan-summed
  `kv_mem`, float32 state) without the masked variant, which batched
  left-padded prompts need and a single conversation does not.
- The KV cache is upstream's `KVCacheSimple` growth policy (256-token steps)
  as a small final class; the recurrent state is two arrays per layer.
