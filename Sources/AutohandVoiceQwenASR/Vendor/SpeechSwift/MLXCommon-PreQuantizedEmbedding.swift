// Vendored from github.com/soniqo/speech-swift v0.0.28 (Apache-2.0).
// Modified for Autohand Voice; see NOTICE.md in this directory.

#if arch(arm64)
import Foundation
import MLX
import MLXNN

/// Pre-quantized embedding that can be loaded directly from safetensors
class PreQuantizedEmbedding: Module {
    let groupSize: Int
    let bits: Int
    let embeddingCount: Int
    let dimensions: Int

    @ParameterInfo var weight: MLXArray
    @ParameterInfo var scales: MLXArray
    @ParameterInfo var biases: MLXArray

    init(embeddingCount: Int, dimensions: Int, groupSize: Int = 64, bits: Int = 4) {
        self.embeddingCount = embeddingCount
        self.dimensions = dimensions
        self.groupSize = groupSize
        self.bits = bits

        // Packed last dim = dimensions * bits / 32 (MLX convention). For 4/8-bit this equals
        // dimensions/(32/bits); written this way it's also correct for 3/5/6-bit (32 not divisible by bits).
        let packedDim = dimensions * bits / 32
        let numGroups = dimensions / groupSize

        // Initialize with zeros - will be loaded from weights
        self._weight.wrappedValue = MLXArray.zeros([embeddingCount, packedDim], dtype: .uint32)
        self._scales.wrappedValue = MLXArray.zeros([embeddingCount, numGroups], dtype: .bfloat16)
        self._biases.wrappedValue = MLXArray.zeros([embeddingCount, numGroups], dtype: .bfloat16)

        super.init()
        self.freeze()
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        let s = x.shape
        let x = x.flattened()
        let out = dequantized(
            weight[x], scales: scales[x], biases: biases[x],
            groupSize: groupSize, bits: bits)
        return out.reshaped(s + [-1])
    }

    /// For use as LM head (matmul with transposed weight)
    func asLinear(_ x: MLXArray) -> MLXArray {
        quantizedMatmul(
            x, weight, scales: scales, biases: biases, transpose: true,
            groupSize: groupSize, bits: bits)
    }
}

#endif
