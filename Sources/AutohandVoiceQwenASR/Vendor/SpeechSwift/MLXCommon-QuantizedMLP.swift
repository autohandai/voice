// Vendored from github.com/soniqo/speech-swift v0.0.28 (Apache-2.0).
// Modified for Autohand Voice; see NOTICE.md in this directory.

#if arch(arm64)
import Foundation
import MLX
import MLXNN

/// SwiGLU MLP — shared by ASR text decoder, TTS Talker, and Code Predictor.
/// Linear layers are quantized when `bits > 0`, plain Linear otherwise (bf16/fp32 path).
class QuantizedMLP: Module {
    @ModuleInfo var gateProj: Linear
    @ModuleInfo var upProj: Linear
    @ModuleInfo var downProj: Linear

    init(hiddenSize: Int, intermediateSize: Int, groupSize: Int = 64, bits: Int = 4) {
        self._gateProj.wrappedValue = makeMaybeQuantizedLinear(
            hiddenSize, intermediateSize, bias: false,
            groupSize: groupSize, bits: bits)
        self._upProj.wrappedValue = makeMaybeQuantizedLinear(
            hiddenSize, intermediateSize, bias: false,
            groupSize: groupSize, bits: bits)
        self._downProj.wrappedValue = makeMaybeQuantizedLinear(
            intermediateSize, hiddenSize, bias: false,
            groupSize: groupSize, bits: bits)

        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        // SwiGLU: down(silu(gate(x)) * up(x))
        let gate = silu(gateProj(x))
        let up = upProj(x)
        return downProj(gate * up)
    }
}

/// SwiGLU MLP with `Linear` projections — used by modules that need to
/// support both bf16/fp16 and quantized bundles. The runtime swaps
/// Linear → QuantizedLinear in place via `quantize(model:filter:)` when
/// the loaded weights carry `.scales` for these paths.
class MLP: Module {
    @ModuleInfo var gateProj: Linear
    @ModuleInfo var upProj: Linear
    @ModuleInfo var downProj: Linear

    init(hiddenSize: Int, intermediateSize: Int) {
        self._gateProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._upProj.wrappedValue = Linear(hiddenSize, intermediateSize, bias: false)
        self._downProj.wrappedValue = Linear(intermediateSize, hiddenSize, bias: false)

        super.init()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let gate = silu(gateProj(x))
        let up = upProj(x)
        return downProj(gate * up)
    }
}

#endif
