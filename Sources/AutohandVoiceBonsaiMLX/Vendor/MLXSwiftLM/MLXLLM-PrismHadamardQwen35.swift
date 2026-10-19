// Ported from github.com/ml-explore/mlx-swift-lm (MIT), PR #630 head
// a3596e4d3c8484a010c811021426d26dff1f365a: Libraries/MLXLLM/Models/Qwen35.swift,
// Qwen3Next.swift, PrismHadamardQwen35.swift and Libraries/MLXLMCommon/
// HadamardQuantized.swift, KVCache.swift. Rewritten onto mlx-swift 0.31.4
// for Autohand Voice (dense text model only, plain arrays instead of
// Module reflection, no compile/MTP/MoE/training paths); see NOTICE.md in
// this directory.

#if arch(arm64)
import Foundation
import MLX
import MLXNN

// MARK: - Configuration

/// The parts of the pack's `config.json` the text model needs: the Prism
/// manifest at the top level and Qwen3.5's `text_config`.
struct PrismHadamardQwen35Configuration: Decodable {
    struct Module: Decodable {
        let path: String
        let block: Int
        let embedding: Bool
        let dtype: String?
    }

    struct Quantization: Decodable {
        let bits: Int
        let groupSize: Int
        let mode: String?

        enum CodingKeys: String, CodingKey {
            case bits
            case groupSize = "group_size"
            case mode
        }
    }

    struct Text: Decodable {
        let hiddenSize: Int
        let hiddenLayers: Int
        let intermediateSize: Int
        let attentionHeads: Int
        let kvHeads: Int
        let headDim: Int?
        let linearNumValueHeads: Int
        let linearNumKeyHeads: Int
        let linearKeyHeadDim: Int
        let linearValueHeadDim: Int
        let linearConvKernelDim: Int
        let rmsNormEps: Float
        let vocabularySize: Int
        let fullAttentionInterval: Int?
        let layerTypes: [String]?
        let tieWordEmbeddings: Bool?
        let attentionBias: Bool?
        let ropeParameters: RopeParameters?

        struct RopeParameters: Decodable {
            let ropeTheta: Float?
            let partialRotaryFactor: Float?
            let ropeType: String?

            enum CodingKeys: String, CodingKey {
                case ropeTheta = "rope_theta"
                case partialRotaryFactor = "partial_rotary_factor"
                case ropeType = "rope_type"
            }
        }

        enum CodingKeys: String, CodingKey {
            case hiddenSize = "hidden_size"
            case hiddenLayers = "num_hidden_layers"
            case intermediateSize = "intermediate_size"
            case attentionHeads = "num_attention_heads"
            case kvHeads = "num_key_value_heads"
            case headDim = "head_dim"
            case linearNumValueHeads = "linear_num_value_heads"
            case linearNumKeyHeads = "linear_num_key_heads"
            case linearKeyHeadDim = "linear_key_head_dim"
            case linearValueHeadDim = "linear_value_head_dim"
            case linearConvKernelDim = "linear_conv_kernel_dim"
            case rmsNormEps = "rms_norm_eps"
            case vocabularySize = "vocab_size"
            case fullAttentionInterval = "full_attention_interval"
            case layerTypes = "layer_types"
            case tieWordEmbeddings = "tie_word_embeddings"
            case attentionBias = "attention_bias"
            case ropeParameters = "rope_parameters"
        }

        var resolvedHeadDim: Int { headDim ?? hiddenSize / attentionHeads }
        var ropeTheta: Float { ropeParameters?.ropeTheta ?? 10_000_000 }
        var partialRotaryFactor: Float { ropeParameters?.partialRotaryFactor ?? 0.25 }

        func isLinearLayer(_ index: Int) -> Bool {
            if let layerTypes { return layerTypes[index] == "linear_attention" }
            let interval = fullAttentionInterval ?? 4
            return (index + 1) % interval != 0
        }
    }

    let schemaVersion: Int
    let modelType: String
    let baseModelType: String?
    let tensorNamespace: String?
    let gdnActivationLayout: String?
    let modules: [Module]
    let quantization: Quantization
    let text: Text

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case modelType = "model_type"
        case baseModelType = "base_model_type"
        case tensorNamespace = "tensor_namespace"
        case gdnActivationLayout = "gdn_activation_layout"
        case modules
        case quantization
        case text = "text_config"
    }

    /// Rejects packs this loader cannot run correctly (the weights would
    /// load but decode nonsense).
    func validate() throws {
        func fail(_ reason: String) -> BonsaiMLXError { .invalidModel(reason) }
        guard modelType == "prism_hadamard_qwen35" else {
            throw fail("model_type \(modelType) is not prism_hadamard_qwen35")
        }
        guard schemaVersion == 2 else { throw fail("schema_version \(schemaVersion)") }
        guard baseModelType == "qwen3_5" else { throw fail("base model is not qwen3_5") }
        guard tensorNamespace == "mlx-vlm-qwen3_5" else {
            throw fail("tensor namespace \(tensorNamespace ?? "nil")")
        }
        guard gdnActivationLayout == nil || gdnActivationLayout == "grouped" else {
            throw fail("ungrouped GDN activations need a permutation")
        }
        guard quantization.mode == nil || quantization.mode == "affine" else {
            throw fail("quantization mode \(quantization.mode ?? "")")
        }
        guard !modules.isEmpty, Set(modules.map(\.path)).count == modules.count else {
            throw fail("empty or duplicate module manifest")
        }
        for module in modules {
            guard SignedHadamard.isValidBlockSize(module.block) else {
                throw fail("block \(module.block) for \(module.path)")
            }
            guard module.dtype == nil || module.dtype == "float16" else {
                throw fail("activation dtype \(module.dtype ?? "") for \(module.path)")
            }
        }
        guard text.tieWordEmbeddings != false else { throw fail("untied output head") }
    }
}

// MARK: - Weights

/// The pack's language-model tensors, keyed without the `language_model.`
/// prefix. Unpacked floating-point tensors are cast to the activation dtype
/// (float16) except `A_log`, which the recurrence reads in float32 — what
/// mlx-vlm's converter and mlx-swift-lm's checkpoint policy do, so the
/// residual stream stays half precision.
struct PrismWeights {
    private var arrays: [String: MLXArray]
    private let packed: Set<String>
    let activationDType: DType = .float16

    init(url: URL, packedModules: Set<String>) throws {
        let all = try loadArrays(url: url)
        var arrays: [String: MLXArray] = [:]
        let prefix = "language_model."
        for (key, value) in all where key.hasPrefix(prefix) {
            arrays[String(key.dropFirst(prefix.count))] = value
        }
        guard !arrays.isEmpty else {
            throw BonsaiMLXError.invalidModel("no language_model tensors")
        }
        self.arrays = arrays
        self.packed = packedModules
    }

    /// A float tensor that is not part of a packed module.
    mutating func dense(_ key: String, keepFloat32: Bool = false) throws -> MLXArray {
        guard let value = arrays.removeValue(forKey: key) else {
            throw BonsaiMLXError.invalidModel("missing tensor \(key)")
        }
        if keepFloat32 { return value.asType(.float32) }
        return value.dtype == activationDType ? value : value.asType(activationDType)
    }

    mutating func raw(_ key: String) throws -> MLXArray {
        guard let value = arrays.removeValue(forKey: key) else {
            throw BonsaiMLXError.invalidModel("missing tensor \(key)")
        }
        return value
    }

    func isPacked(_ path: String) -> Bool { packed.contains(path) }

    var remainingKeys: [String] { arrays.keys.sorted() }
}

// MARK: - Layers

/// MLX affine-quantized linear whose weight sits in a rotated input basis:
/// `y = W_q · (R·x)`.
final class HadamardQuantizedLinear {
    let weight: MLXArray
    let scales: MLXArray
    let biases: MLXArray
    let signs: MLXArray
    let rotation: SignedHadamard
    let groupSize: Int
    let bits: Int

    init(
        _ path: String,
        weights: inout PrismWeights,
        block: Int,
        groupSize: Int,
        bits: Int
    ) throws {
        guard weights.isPacked(path) else {
            throw BonsaiMLXError.invalidModel("\(path) is not in the packed manifest")
        }
        weight = try weights.raw(path + ".weight")
        scales = try weights.raw(path + ".scales")
        biases = try weights.raw(path + ".biases")
        signs = try weights.raw(path + ".signs").asType(.float32)
        let inputs = weight.dim(1) * 32 / bits
        guard weight.dtype == .uint32, signs.dim(0) == inputs, inputs % block == 0,
              scales.dim(1) * groupSize == inputs
        else { throw BonsaiMLXError.invalidModel("bad packed shapes for \(path)") }
        rotation = SignedHadamard(blockSize: block)
        self.groupSize = groupSize
        self.bits = bits
    }

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        quantizedMM(
            rotation.forward(x, signs: signs),
            weight,
            scales: scales,
            biases: biases,
            transpose: true,
            groupSize: groupSize,
            bits: bits
        )
    }
}

/// The packed embedding table. Lookups un-rotate the dequantized rows;
/// as the tied output head it rotates its input like a packed linear.
final class HadamardQuantizedEmbedding {
    let weight: MLXArray
    let scales: MLXArray
    let biases: MLXArray
    let signs: MLXArray
    let rotation: SignedHadamard
    let groupSize: Int
    let bits: Int
    let dtype: DType

    init(
        _ path: String,
        weights: inout PrismWeights,
        block: Int,
        groupSize: Int,
        bits: Int
    ) throws {
        weight = try weights.raw(path + ".weight")
        scales = try weights.raw(path + ".scales")
        biases = try weights.raw(path + ".biases")
        signs = try weights.raw(path + ".signs").asType(.float32)
        rotation = SignedHadamard(blockSize: block)
        self.groupSize = groupSize
        self.bits = bits
        dtype = weights.activationDType
    }

    func callAsFunction(_ ids: MLXArray) -> MLXArray {
        let shape = ids.shape
        let flat = ids.flattened()
        let rows = dequantized(
            weight[flat],
            scales: scales[flat],
            biases: biases[flat],
            groupSize: groupSize,
            bits: bits
        ).asType(dtype)
        return rotation.inverse(rows.reshaped(shape + [-1]), signs: signs)
    }

    func asLinear(_ x: MLXArray) -> MLXArray {
        quantizedMM(
            rotation.forward(x, signs: signs),
            weight,
            scales: scales,
            biases: biases,
            transpose: true,
            groupSize: groupSize,
            bits: bits
        )
    }
}

struct Projection {
    let packed: HadamardQuantizedLinear?
    let dense: MLXArray?

    func callAsFunction(_ x: MLXArray) -> MLXArray {
        if let packed { return packed(x) }
        return matmul(x, dense!.T)
    }
}

/// Loads `path` as a packed layer when the manifest lists it, otherwise as
/// a plain float linear (Bonsai keeps the tiny GDN `a`/`b` projections
/// unquantized).
private func projection(
    _ path: String,
    weights: inout PrismWeights,
    blocks: [String: Int],
    quantization: PrismHadamardQwen35Configuration.Quantization
) throws -> Projection {
    if let block = blocks[path] {
        return Projection(
            packed: try HadamardQuantizedLinear(
                path,
                weights: &weights,
                block: block,
                groupSize: quantization.groupSize,
                bits: quantization.bits
            ),
            dense: nil
        )
    }
    return Projection(packed: nil, dense: try weights.dense(path + ".weight"))
}

/// Per-layer recurrent state for a Gated DeltaNet layer.
final class GatedDeltaCache {
    var conv: MLXArray?
    var recurrent: MLXArray?
}

/// Growing key/value buffer for a full-attention layer (mlx-lm's
/// `KVCacheSimple`: preallocated in 256-token steps).
final class AttentionCache {
    private(set) var offset = 0
    private var keys: MLXArray?
    private var values: MLXArray?
    private let step = 256

    var state: [MLXArray] { [keys, values].compactMap { $0 } }

    func update(keys newKeys: MLXArray, values newValues: MLXArray) -> (MLXArray, MLXArray) {
        let previous = offset
        let needed = previous + newKeys.dim(2)
        if keys == nil || needed > keys!.dim(2) {
            let steps = (step + newKeys.dim(2) - 1) / step
            let kShape = [newKeys.dim(0), newKeys.dim(1), steps * step, newKeys.dim(3)]
            let vShape = [newValues.dim(0), newValues.dim(1), steps * step, newValues.dim(3)]
            let grownK = MLXArray.zeros(kShape, dtype: newKeys.dtype)
            let grownV = MLXArray.zeros(vShape, dtype: newValues.dtype)
            if var currentK = keys, var currentV = values {
                if previous % step != 0 {
                    currentK = currentK[.ellipsis, ..<previous, 0...]
                    currentV = currentV[.ellipsis, ..<previous, 0...]
                }
                keys = concatenated([currentK, grownK], axis: 2)
                values = concatenated([currentV, grownV], axis: 2)
            } else {
                keys = grownK
                values = grownV
            }
        }
        offset = needed
        keys![.ellipsis, previous..<offset, 0...] = newKeys
        values![.ellipsis, previous..<offset, 0...] = newValues
        return (keys![.ellipsis, ..<offset, 0...], values![.ellipsis, ..<offset, 0...])
    }
}

final class GatedDeltaNet {
    let numVHeads: Int
    let numKHeads: Int
    let headKDim: Int
    let headVDim: Int
    let keyDim: Int
    let convDim: Int
    let convKernelSize: Int
    let eps: Float

    let inProjQKV: Projection
    let inProjZ: Projection
    let inProjB: Projection
    let inProjA: Projection
    let outProj: Projection
    let conv1dWeight: MLXArray
    let dtBias: MLXArray
    let aLog: MLXArray
    let normWeight: MLXArray

    init(
        prefix: String,
        config: PrismHadamardQwen35Configuration,
        weights: inout PrismWeights,
        blocks: [String: Int]
    ) throws {
        let text = config.text
        numVHeads = text.linearNumValueHeads
        numKHeads = text.linearNumKeyHeads
        headKDim = text.linearKeyHeadDim
        headVDim = text.linearValueHeadDim
        keyDim = headKDim * numKHeads
        convDim = keyDim * 2 + headVDim * numVHeads
        convKernelSize = text.linearConvKernelDim
        eps = text.rmsNormEps
        guard numVHeads % numKHeads == 0 else {
            throw BonsaiMLXError.invalidModel("GDN value heads must group key heads")
        }
        func load(_ name: String) throws -> Projection {
            try projection(
                prefix + name,
                weights: &weights,
                blocks: blocks,
                quantization: config.quantization
            )
        }
        inProjQKV = try load("in_proj_qkv")
        inProjZ = try load("in_proj_z")
        inProjB = try load("in_proj_b")
        inProjA = try load("in_proj_a")
        outProj = try load("out_proj")
        conv1dWeight = try weights.dense(prefix + "conv1d.weight")
        guard conv1dWeight.shape == [convDim, convKernelSize, 1] else {
            throw BonsaiMLXError.invalidModel("conv1d weight shape \(conv1dWeight.shape)")
        }
        dtBias = try weights.dense(prefix + "dt_bias")
        aLog = try weights.dense(prefix + "A_log", keepFloat32: true)
        normWeight = try weights.dense(prefix + "norm.weight")
    }

    func callAsFunction(_ x: MLXArray, cache: GatedDeltaCache) -> MLXArray {
        let B = x.dim(0)
        let S = x.dim(1)
        let qkv = inProjQKV(x)
        let z = inProjZ(x).reshaped(B, S, numVHeads, headVDim)
        let b = inProjB(x)
        let a = inProjA(x)

        let convState = cache.conv
            ?? MLXArray.zeros([B, convKernelSize - 1, convDim], dtype: qkv.dtype)
        let convInput = concatenated([convState, qkv], axis: 1)
        cache.conv = contiguous(convInput[0..., (-(convKernelSize - 1))..., 0...])
        let convOut = silu(conv1d(convInput, conv1dWeight, groups: convDim))

        let parts = split(convOut, indices: [keyDim, 2 * keyDim], axis: -1)
        let q = parts[0].reshaped(B, S, numKHeads, headKDim)
        let k = parts[1].reshaped(B, S, numKHeads, headKDim)
        let v = parts[2].reshaped(B, S, numVHeads, headVDim)

        // l2norm(q)·Dk^-½ and l2norm(k) via rms_norm; the reference adds
        // 1e-6 to the sum of squares, rms_norm to the mean.
        let dtype = q.dtype
        let invScale = 1 / Float(headKDim).squareRoot()
        let qkEps = 1e-6 / Float(headKDim)
        let qNormed = MLXArray(invScale * invScale).asType(dtype)
            * MLXFast.rmsNorm(q, weight: MLXArray.mlxNone, eps: qkEps)
        let kNormed = MLXArray(invScale).asType(dtype)
            * MLXFast.rmsNorm(k, weight: MLXArray.mlxNone, eps: qkEps)

        let (out, state) = gatedDeltaUpdate(
            q: qNormed,
            k: kNormed,
            v: v,
            a: a,
            b: b,
            aLog: aLog,
            dtBias: dtBias,
            state: cache.recurrent
        )
        cache.recurrent = state

        // Gated RMSNorm: rms_norm(out)·silu(z), the product in float32.
        let normed = MLXFast.rmsNorm(out, weight: normWeight, eps: eps)
        let gated = (silu(z.asType(.float32)) * normed.asType(.float32)).asType(out.dtype)
        return outProj(gated.reshaped(B, S, -1))
    }
}

final class FullAttention {
    let heads: Int
    let kvHeads: Int
    let headDim: Int
    let scale: Float
    let ropeDimensions: Int
    let ropeBase: Float
    let eps: Float

    let qProj: Projection
    let kProj: Projection
    let vProj: Projection
    let oProj: Projection
    let qNorm: MLXArray
    let kNorm: MLXArray

    init(
        prefix: String,
        config: PrismHadamardQwen35Configuration,
        weights: inout PrismWeights,
        blocks: [String: Int]
    ) throws {
        let text = config.text
        heads = text.attentionHeads
        kvHeads = text.kvHeads
        headDim = text.resolvedHeadDim
        scale = 1 / Float(headDim).squareRoot()
        ropeDimensions = max(1, Int(Float(headDim) * text.partialRotaryFactor))
        ropeBase = text.ropeTheta
        eps = text.rmsNormEps
        if text.attentionBias == true {
            throw BonsaiMLXError.invalidModel("attention bias is not supported")
        }
        func load(_ name: String) throws -> Projection {
            try projection(
                prefix + name,
                weights: &weights,
                blocks: blocks,
                quantization: config.quantization
            )
        }
        qProj = try load("q_proj")
        kProj = try load("k_proj")
        vProj = try load("v_proj")
        oProj = try load("o_proj")
        qNorm = try weights.dense(prefix + "q_norm.weight")
        kNorm = try weights.dense(prefix + "k_norm.weight")
    }

    func callAsFunction(_ x: MLXArray, cache: AttentionCache) -> MLXArray {
        let B = x.dim(0)
        let L = x.dim(1)
        // q_proj carries the queries and an output gate per head.
        let qAndGate = qProj(x).reshaped(B, L, heads, -1).split(parts: 2, axis: -1)
        let gate = qAndGate[1].reshaped(B, L, -1)
        var queries = MLXFast.rmsNorm(qAndGate[0], weight: qNorm, eps: eps)
            .transposed(0, 2, 1, 3)
        var keys = MLXFast.rmsNorm(
            kProj(x).reshaped(B, L, kvHeads, -1),
            weight: kNorm,
            eps: eps
        ).transposed(0, 2, 1, 3)
        let values = vProj(x).reshaped(B, L, kvHeads, -1).transposed(0, 2, 1, 3)

        // Text-only positions are equal on all three M-RoPE axes, which
        // reduces interleaved M-RoPE to plain RoPE on the rotary dims.
        let offset = cache.offset
        queries = MLXFast.RoPE(
            queries, dimensions: ropeDimensions, traditional: false,
            base: ropeBase, scale: 1, offset: offset
        )
        keys = MLXFast.RoPE(
            keys, dimensions: ropeDimensions, traditional: false,
            base: ropeBase, scale: 1, offset: offset
        )
        let (allKeys, allValues) = cache.update(keys: keys, values: values)
        let attended = MLXFast.scaledDotProductAttention(
            queries: queries,
            keys: allKeys,
            values: allValues,
            scale: scale,
            mask: L > 1 ? .causal : .none
        )
        let merged = attended.transposed(0, 2, 1, 3).reshaped(B, L, -1)
        return oProj(merged * sigmoid(gate))
    }
}

final class DecoderLayer {
    let linear: GatedDeltaNet?
    let attention: FullAttention?
    let inputNorm: MLXArray
    let postAttentionNorm: MLXArray
    let gateProj: Projection
    let upProj: Projection
    let downProj: Projection
    let eps: Float

    init(
        index: Int,
        config: PrismHadamardQwen35Configuration,
        weights: inout PrismWeights,
        blocks: [String: Int]
    ) throws {
        let prefix = "model.layers.\(index)."
        if config.text.isLinearLayer(index) {
            linear = try GatedDeltaNet(
                prefix: prefix + "linear_attn.",
                config: config,
                weights: &weights,
                blocks: blocks
            )
            attention = nil
        } else {
            linear = nil
            attention = try FullAttention(
                prefix: prefix + "self_attn.",
                config: config,
                weights: &weights,
                blocks: blocks
            )
        }
        inputNorm = try weights.dense(prefix + "input_layernorm.weight")
        postAttentionNorm = try weights.dense(prefix + "post_attention_layernorm.weight")
        func load(_ name: String) throws -> Projection {
            try projection(
                prefix + "mlp." + name,
                weights: &weights,
                blocks: blocks,
                quantization: config.quantization
            )
        }
        gateProj = try load("gate_proj")
        upProj = try load("up_proj")
        downProj = try load("down_proj")
        eps = config.text.rmsNormEps
    }

    var isLinear: Bool { linear != nil }

    func callAsFunction(
        _ x: MLXArray,
        linearCache: GatedDeltaCache?,
        attentionCache: AttentionCache?
    ) -> MLXArray {
        let normed = MLXFast.rmsNorm(x, weight: inputNorm, eps: eps)
        let mixed: MLXArray
        if let linear, let linearCache {
            mixed = linear(normed, cache: linearCache)
        } else {
            mixed = attention!(normed, cache: attentionCache!)
        }
        let h = x + mixed
        let m = MLXFast.rmsNorm(h, weight: postAttentionNorm, eps: eps)
        return h + downProj(silu(gateProj(m)) * upProj(m))
    }
}

/// Per-conversation state: one cache per layer.
final class PrismHadamardQwen35Cache {
    let linear: [GatedDeltaCache?]
    let attention: [AttentionCache?]

    init(layers: [DecoderLayer]) {
        linear = layers.map { $0.isLinear ? GatedDeltaCache() : nil }
        attention = layers.map { $0.isLinear ? nil : AttentionCache() }
    }
}

/// Qwen3.5 dense text model (hybrid Gated DeltaNet + gated full attention)
/// over a Prism Hadamard 2-bit pack, with the tied embedding as its head.
final class PrismHadamardQwen35Model {
    let config: PrismHadamardQwen35Configuration
    let embedding: HadamardQuantizedEmbedding
    let layers: [DecoderLayer]
    let norm: MLXArray

    var vocabularySize: Int { config.text.vocabularySize }

    init(directory: URL) throws {
        let configData = try Data(contentsOf: directory.appendingPathComponent("config.json"))
        let config: PrismHadamardQwen35Configuration
        do {
            config = try JSONDecoder().decode(
                PrismHadamardQwen35Configuration.self,
                from: configData
            )
        } catch {
            throw BonsaiMLXError.invalidModel("config.json: \(error)")
        }
        try config.validate()
        self.config = config

        var blocks: [String: Int] = [:]
        var embeddingBlock: Int?
        for module in config.modules {
            if module.embedding {
                guard module.path == "model.embed_tokens" else {
                    throw BonsaiMLXError.invalidModel("unexpected embedding \(module.path)")
                }
                embeddingBlock = module.block
            } else {
                blocks[module.path] = module.block
            }
        }
        guard let embeddingBlock else {
            throw BonsaiMLXError.invalidModel("the embedding is not packed")
        }

        var weights = try PrismWeights(
            url: directory.appendingPathComponent("model.safetensors"),
            packedModules: Set(config.modules.map(\.path))
        )
        embedding = try HadamardQuantizedEmbedding(
            "model.embed_tokens",
            weights: &weights,
            block: embeddingBlock,
            groupSize: config.quantization.groupSize,
            bits: config.quantization.bits
        )
        var layers: [DecoderLayer] = []
        for index in 0..<config.text.hiddenLayers {
            layers.append(try DecoderLayer(
                index: index,
                config: config,
                weights: &weights,
                blocks: blocks
            ))
        }
        self.layers = layers
        norm = try weights.dense("model.norm.weight")
        let leftover = weights.remainingKeys
        guard leftover.isEmpty else {
            throw BonsaiMLXError.invalidModel(
                "unused tensors: \(leftover.prefix(5).joined(separator: ", "))"
            )
        }
    }

    func makeCache() -> PrismHadamardQwen35Cache {
        PrismHadamardQwen35Cache(layers: layers)
    }

    /// Logits for the last position of `tokens` (`[1, L]` int32).
    func lastLogits(_ tokens: MLXArray, cache: PrismHadamardQwen35Cache) -> MLXArray {
        var hidden = embedding(tokens)
        for (index, layer) in layers.enumerated() {
            hidden = layer(
                hidden,
                linearCache: cache.linear[index],
                attentionCache: cache.attention[index]
            )
        }
        let last = hidden[0..., (-1)..., 0...]
        let normed = MLXFast.rmsNorm(last, weight: norm, eps: config.text.rmsNormEps)
        return embedding.asLinear(normed).reshaped(-1).asType(.float32)
    }

    /// Every array the model holds, for one up-front `eval`.
    var parameters: [MLXArray] {
        var arrays = [
            embedding.weight, embedding.scales, embedding.biases, embedding.signs, norm,
        ]
        func add(_ projection: Projection) {
            if let packed = projection.packed {
                arrays += [packed.weight, packed.scales, packed.biases, packed.signs]
            } else if let dense = projection.dense {
                arrays.append(dense)
            }
        }
        for layer in layers {
            arrays += [layer.inputNorm, layer.postAttentionNorm]
            [layer.gateProj, layer.upProj, layer.downProj].forEach(add)
            if let linear = layer.linear {
                [linear.inProjQKV, linear.inProjZ, linear.inProjA, linear.inProjB, linear.outProj]
                    .forEach(add)
                arrays += [linear.conv1dWeight, linear.dtBias, linear.aLog, linear.normWeight]
            }
            if let attention = layer.attention {
                [attention.qProj, attention.kProj, attention.vProj, attention.oProj].forEach(add)
                arrays += [attention.qNorm, attention.kNorm]
            }
        }
        return arrays
    }
}
#endif
