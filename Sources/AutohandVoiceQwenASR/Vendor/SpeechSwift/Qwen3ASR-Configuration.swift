// Vendored from github.com/soniqo/speech-swift v0.0.28 (Apache-2.0).
// Modified for Autohand Voice; see NOTICE.md in this directory.

#if arch(arm64)
import Foundation

/// Configuration for Qwen3-ASR audio encoder
struct AudioEncoderConfig: Codable, Sendable {
    var inputDim: Int = 128          // Mel filterbank bins
    var hiddenDim: Int = 1024        // Transformer hidden dim
    var numLayers: Int = 18          // Transformer layers
    var numHeads: Int = 16           // Attention heads
    var kernelSize: Int = 3          // Conv kernel size
    var headDim: Int = 64            // Head dimension (hiddenDim / numHeads)
    var ffnDim: Int = 4096           // FFN intermediate dim
    var maxSourcePositions: Int = 1500
    var layerNormEps: Float = 1e-5
    var attentionDropout: Float = 0.0
    var dropoutRate: Float = 0.0
    var layerdrop: Float = 0.0
    var numMelBins: Int = 128
    var projectorHiddenAct: String = "silu"

    init() {}

    /// Config for Qwen3-ASR-0.6B
    static var small: AudioEncoderConfig {
        var config = AudioEncoderConfig()
        config.hiddenDim = 768
        config.numLayers = 12
        config.numHeads = 12
        config.headDim = 64
        config.ffnDim = 3072
        return config
    }

    /// Config for Qwen3-ASR-1.7B
    static var large: AudioEncoderConfig {
        var config = AudioEncoderConfig()
        config.hiddenDim = 1024
        config.numLayers = 24
        config.numHeads = 16
        config.headDim = 64
        config.ffnDim = 4096
        return config
    }
}

/// Configuration for Qwen3 text decoder
struct TextDecoderConfig: Codable, Sendable {
    var vocabSize: Int = 151936
    var hiddenSize: Int = 1024        // Model dimension
    var numLayers: Int = 28           // Transformer layers
    var numHeads: Int = 16            // Attention heads
    var numKVHeads: Int = 8           // KV heads for GQA
    var headDim: Int = 64             // Head dimension (hiddenSize / numHeads for 0.6B)
    var intermediateSize: Int = 3072  // FFN intermediate size
    var maxPositionEmbeddings: Int = 65536
    var rmsNormEps: Float = 1e-6
    var ropeTheta: Float = 1000000.0
    var ropeScaling: RopeScaling? = nil
    var tieWordEmbeddings: Bool = true

    // Quantization config
    var groupSize: Int = 64
    var bits: Int = 4

    init() {}

    /// Config for Qwen3-ASR-0.6B decoder, 4-bit (from HuggingFace model config)
    static var small: TextDecoderConfig {
        var config = TextDecoderConfig()
        config.hiddenSize = 1024
        config.numLayers = 28
        config.numHeads = 16
        config.numKVHeads = 8
        config.headDim = 128  // From config.json: head_dim = 128
        config.intermediateSize = 3072
        config.groupSize = 64
        config.bits = 4
        return config
    }

    /// Config for Qwen3-ASR-0.6B decoder, 5-bit
    static var small5bit: TextDecoderConfig {
        var config = small
        config.bits = 5
        return config
    }

    /// Config for Qwen3-ASR-0.6B decoder, 8-bit
    static var small8bit: TextDecoderConfig {
        var config = small
        config.bits = 8
        return config
    }

    /// Config for Qwen3-ASR-1.7B decoder, 4-bit
    static var large: TextDecoderConfig {
        var config = TextDecoderConfig()
        config.hiddenSize = 2048
        config.numLayers = 28
        config.numHeads = 16
        config.numKVHeads = 8
        config.headDim = 128
        config.intermediateSize = 6144
        config.groupSize = 64
        config.bits = 4
        return config
    }

    /// Config for Qwen3-ASR-1.7B decoder, 5-bit
    static var large5bit: TextDecoderConfig {
        var config = large
        config.bits = 5
        return config
    }

    /// Config for Qwen3-ASR-1.7B decoder, 8-bit
    static var large8bit: TextDecoderConfig {
        var config = large
        config.bits = 8
        return config
    }
}

/// RoPE scaling configuration
struct RopeScaling: Codable, Sendable {
    var type: String
    var factor: Float?
    var originalMaxPositionEmbeddings: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case factor
        case originalMaxPositionEmbeddings = "original_max_position_embeddings"
    }
}

/// Combined Qwen3-ASR model configuration
struct Qwen3ASRConfig: Codable, Sendable {
    var audioEncoder: AudioEncoderConfig
    var textDecoder: TextDecoderConfig
    var audioTokenIndex: Int = 151646
    var eosTokenId: Int = 151645
    var padTokenId: Int = 151643

    // ForcedAligner-specific config
    var classifyNum: Int = 5000
    var timestampSegmentTime: Float = 0.08  // 80ms per timestamp class

    init(
        audioEncoder: AudioEncoderConfig = AudioEncoderConfig(),
        textDecoder: TextDecoderConfig = TextDecoderConfig()
    ) {
        self.audioEncoder = audioEncoder
        self.textDecoder = textDecoder
    }

    /// Config for Qwen3-ASR-0.6B
    static var small: Qwen3ASRConfig {
        Qwen3ASRConfig(
            audioEncoder: .small,
            textDecoder: .small
        )
    }

    /// Config for Qwen3-ASR-1.7B
    static var large: Qwen3ASRConfig {
        Qwen3ASRConfig(
            audioEncoder: .large,
            textDecoder: .large
        )
    }
}

#endif
