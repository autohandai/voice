#if arch(arm64)
import Foundation
import MLX

/// `BonsaiSampler`'s chain (top-k, presence penalty over the recent
/// generated tokens, top-p at temperature 1, temperature, draw) as lazy MLX
/// ops, so the next token never has to come back to the CPU before the
/// following decode step is queued. `BonsaiSampler` stays the plain-Swift
/// reference; tests pin the two against each other.
struct BonsaiGPUSampler {
    let settings: BonsaiSamplingSettings
    private var key: MLXArray
    /// Last `penaltyWindow` generated tokens, -1 for empty slots.
    private var window: MLXArray

    init(settings: BonsaiSamplingSettings, seed: UInt64?) {
        self.settings = settings
        key = MLXRandom.key(seed ?? UInt64.random(in: .min ... .max))
        window = MLXArray.full(
            [max(1, settings.penaltyWindow)],
            values: MLXArray(Int32(-1))
        )
    }

    /// The next token as a lazy `[1]` int32 array. Records it in the
    /// penalty window.
    mutating func sample(_ logits: MLXArray) -> MLXArray {
        let token = choose(logits).reshaped(1).asType(.int32)
        if settings.presencePenalty != 0, settings.penaltyWindow > 0 {
            window = concatenated([window[1...], token])
        }
        return token
    }

    private mutating func choose(_ logits: MLXArray) -> MLXArray {
        let penalised = settings.presencePenalty != 0 && settings.penaltyWindow > 0
        if settings.temperature <= 0, !penalised {
            return argMax(logits)
        }
        let vocabulary = logits.dim(0)
        var ids: MLXArray
        if settings.topK > 0, settings.topK < vocabulary {
            ids = argPartition(-logits, kth: settings.topK - 1)[..<settings.topK]
        } else {
            ids = argSort(-logits)
        }
        var values = logits[ids]
        if penalised {
            let seen = any(
                expandedDimensions(ids.asType(.int32), axis: 1)
                    .== expandedDimensions(window, axis: 0),
                axis: 1
            )
            values = values - seen.asType(.float32) * settings.presencePenalty
        }
        let order = argSort(-values)
        ids = ids[order]
        values = values[order]
        if settings.topP < 1 {
            let probabilities = softmax(values, axis: -1)
            let before = cumsum(probabilities, axis: -1) - probabilities
            values = MLX.where(before .< settings.topP, values, MLXArray(-Float.infinity))
        }
        guard settings.temperature > 0 else { return ids[0] }
        let (next, sub) = MLXRandom.split(key: key)
        key = next
        let choice = MLXRandom.categorical(values / settings.temperature, key: sub)
        return ids[choice]
    }
}
#endif
