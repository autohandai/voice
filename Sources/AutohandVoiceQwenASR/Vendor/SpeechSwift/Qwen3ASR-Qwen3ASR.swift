// Vendored from github.com/soniqo/speech-swift v0.0.28 (Apache-2.0).
// Modified for Autohand Voice; see NOTICE.md in this directory.
//
// Trimmed to the single-clip, offline, MLX quantized-decoder path. Batched
// decoding, Hugging Face Hub download, the 1.7B memory guards, Metal wired
// memory pinning and load-time logging were removed.

#if arch(arm64)
import Foundation
import MLX
import MLXNN
import MLXFast

/// Optional decoder tunables for `Qwen3ASRModel.transcribe(audio:options:)`.
///
/// Defaults match the historical greedy behaviour of `transcribe(audio:)`.
/// The struct also carries the "long-input auto-escalation" knobs used to
/// bound greedy degeneration on >15 s audio without affecting short clips.
struct Qwen3DecodingOptions: Sendable {
    /// Cap on decoder output per chunk.
    var maxTokens: Int = 448

    /// Optional language hint ("English", "Chinese", …). `nil` = auto-detect.
    var language: String?

    /// Context hint prepended to the decoder prompt.
    var context: String?

    /// HuggingFace-style repetition penalty. `1.0` disables.
    var repetitionPenalty: Float = 1.0

    /// If > 0, masks any next-token whose emission would form a repeated
    /// n-gram of this size. `0` disables.
    var noRepeatNgramSize: Int = 0

    /// `0` = greedy (argmax). `> 0` = sample with this temperature.
    var temperature: Float = 0.0

    /// Audio longer than this many seconds with `noRepeatNgramSize == 0`
    /// escalates to `longInputNoRepeatNgramSize`.
    var longInputThresholdSeconds: Double = 15.0

    /// n-gram size applied by the long-input auto-escalation path.
    var longInputNoRepeatNgramSize: Int = 3

    init(
        maxTokens: Int = 448,
        language: String? = nil,
        context: String? = nil,
        repetitionPenalty: Float = 1.0,
        noRepeatNgramSize: Int = 0,
        temperature: Float = 0.0,
        longInputThresholdSeconds: Double = 15.0,
        longInputNoRepeatNgramSize: Int = 3
    ) {
        self.maxTokens = maxTokens
        self.language = language
        self.context = context
        self.repetitionPenalty = repetitionPenalty
        self.noRepeatNgramSize = noRepeatNgramSize
        self.temperature = temperature
        self.longInputThresholdSeconds = longInputThresholdSeconds
        self.longInputNoRepeatNgramSize = longInputNoRepeatNgramSize
    }

    /// Length-gated auto-escalation. Returns a copy with
    /// `noRepeatNgramSize` bumped to `longInputNoRepeatNgramSize` IFF the
    /// audio is longer than the threshold, the caller left
    /// `noRepeatNgramSize` at 0, and escalation is enabled.
    func adaptedFor(audioDurationSeconds: Double) -> Qwen3DecodingOptions {
        guard audioDurationSeconds > longInputThresholdSeconds,
              noRepeatNgramSize == 0,
              longInputNoRepeatNgramSize > 0 else {
            return self
        }
        var copy = self
        copy.noRepeatNgramSize = longInputNoRepeatNgramSize
        return copy
    }
}

/// Special token IDs for Qwen3-ASR
struct Qwen3ASRTokens: Sendable {
    static let audioTokenId = 151676        // <|audio_pad|>
    static let audioStartTokenId = 151669   // <|audio_start|>
    static let audioEndTokenId = 151670     // <|audio_end|>
    static let eosTokenId = 151645          // <|im_end|>
    static let padTokenId = 151643          // <|endoftext|>
    static let imStartTokenId = 151644      // <|im_start|>
    static let imEndTokenId = 151645        // <|im_end|>
    static let timestampTokenId = 151705    // <|timestamp|>
    static let asrTextTokenId = 151704      // <asr_text>
    static let newlineTokenId = 198         // \n
    static let systemTokenId = 8948         // system
    static let userTokenId = 872            // user
    static let assistantTokenId = 77091     // assistant
}

/// Main Qwen3-ASR model for speech recognition.
///
/// - Warning: This class is not thread-safe. Use it from one serial context.
final class Qwen3ASRModel {
    let audioEncoder: Qwen3AudioEncoder
    let featureExtractor: WhisperFeatureExtractor
    var textDecoder: QuantizedTextModel?

    /// Tokenizer for decoding output tokens
    private var tokenizer: Qwen3Tokenizer?

    /// Text decoder config
    let textConfig: TextDecoderConfig

    init(
        audioConfig: Qwen3AudioEncoderConfig = .default,
        textConfig: TextDecoderConfig = .small
    ) {
        self.audioEncoder = Qwen3AudioEncoder(config: audioConfig)
        self.featureExtractor = WhisperFeatureExtractor()
        self.textConfig = textConfig
        self.textDecoder = nil
    }

    func setTokenizer(_ tokenizer: Qwen3Tokenizer) {
        self.tokenizer = tokenizer
    }

    func initializeTextDecoder() {
        self.textDecoder = QuantizedTextModel(config: textConfig)
    }

    /// Transcribe one clip. `checkCancellation` runs at cooperative
    /// checkpoints: before feature extraction, before the audio encoder,
    /// before decoder prefill and before every decoder step.
    func transcribe(
        audio: [Float],
        sampleRate: Int,
        options: Qwen3DecodingOptions,
        checkCancellation: () throws -> Void
    ) throws -> String {
        try checkCancellation()
        let durationSeconds = sampleRate > 0
            ? Double(audio.count) / Double(sampleRate)
            : 0.0
        let effective = options.adaptedFor(audioDurationSeconds: durationSeconds)

        let melFeatures = featureExtractor.process(audio, sampleRate: sampleRate)
        try checkCancellation()
        let batchedFeatures = melFeatures.expandedDimensions(axis: 0)
        var audioEmbeds = audioEncoder(batchedFeatures)
        audioEmbeds = audioEmbeds.expandedDimensions(axis: 0)
        guard let textDecoder = textDecoder else {
            throw Qwen3VendorError.decoderNotLoaded
        }
        return try generateText(
            audioEmbeds: audioEmbeds,
            textDecoder: textDecoder,
            language: effective.language,
            maxTokens: effective.maxTokens,
            context: effective.context,
            decodingOptions: effective,
            checkCancellation: checkCancellation
        )
    }

    /// Generate text from audio embeddings.
    func generateText(
        audioEmbeds: MLXArray,
        textDecoder: QuantizedTextModel,
        language: String?,
        maxTokens: Int,
        context: String? = nil,
        decodingOptions: Qwen3DecodingOptions = Qwen3DecodingOptions(),
        checkCancellation: () throws -> Void
    ) rethrows -> String {
        let T = Qwen3ASRTokens.self
        let numAudioTokens = audioEmbeds.dim(1)
        var inputIds: [Int32] = []

        // <|im_start|>system\n{context}<|im_end|>\n
        inputIds.append(contentsOf: [T.imStartTokenId, T.systemTokenId, T.newlineTokenId].map { Int32($0) })
        if let context = context, !context.isEmpty, let tokenizer = tokenizer {
            let contextTokens = tokenizer.encode(context)
            inputIds.append(contentsOf: contextTokens.map { Int32($0) })
        }
        inputIds.append(contentsOf: [T.imEndTokenId, T.newlineTokenId].map { Int32($0) })

        // <|im_start|>user\n<|audio_start|>
        inputIds.append(contentsOf: [T.imStartTokenId, T.userTokenId, T.newlineTokenId, T.audioStartTokenId].map { Int32($0) })

        // <|audio_pad|> * numAudioTokens (placeholder tokens that will be replaced)
        let audioStartIndex = inputIds.count
        for _ in 0..<numAudioTokens {
            inputIds.append(Int32(T.audioTokenId))
        }
        let audioEndIndex = inputIds.count

        // <|audio_end|><|im_end|>\n
        inputIds.append(contentsOf: [T.audioEndTokenId, T.imEndTokenId, T.newlineTokenId].map { Int32($0) })

        // <|im_start|>assistant\n
        inputIds.append(contentsOf: [T.imStartTokenId, T.assistantTokenId, T.newlineTokenId].map { Int32($0) })

        // Add language hint if specified, then always add <asr_text>. Without
        // <asr_text>, the model doesn't know it should transcribe. Without a
        // language hint, the model auto-detects and prepends "language XX".
        if let lang = language, let tokenizer = tokenizer {
            let langPrefix = "language \(lang)"
            let langTokens = tokenizer.encode(langPrefix)
            inputIds.append(contentsOf: langTokens.map { Int32($0) })
        }
        inputIds.append(Int32(T.asrTextTokenId))

        // Get text embeddings for all tokens
        let inputIdsTensor = MLXArray(inputIds).expandedDimensions(axis: 0)
        var inputEmbeds = textDecoder.embedTokens(inputIdsTensor)

        // Replace audio_pad token positions with actual audio embeddings
        let audioEmbedsTyped = audioEmbeds.asType(inputEmbeds.dtype)
        let beforeAudio = inputEmbeds[0..., 0..<audioStartIndex, 0...]
        let afterAudio = inputEmbeds[0..., audioEndIndex..., 0...]

        inputEmbeds = concatenated([beforeAudio, audioEmbedsTyped, afterAudio], axis: 1)

        // First pass: process the full input embeddings
        try checkCancellation()
        let (hiddenStates, cache) = textDecoder(inputsEmbeds: inputEmbeds, cache: nil)

        // Get logits from the last position using embedding as LM head (tied weights)
        let seqLen = hiddenStates.dim(1)
        let lastHidden = hiddenStates[0..., (seqLen-1)..<seqLen, 0...]
        let logits = textDecoder.embedTokens.asLinear(lastHidden)

        let generatedTokens: [Int32]
        if Self.isGreedyFastPath(decodingOptions) {
            generatedTokens = try Self.generateGreedyAsyncEval(
                textDecoder: textDecoder,
                initialLogits: logits,
                cache: cache,
                maxTokens: maxTokens,
                checkCancellation: checkCancellation
            )
        } else {
            generatedTokens = try Self.generateSlow(
                textDecoder: textDecoder,
                initialLogits: logits,
                cache: cache,
                maxTokens: maxTokens,
                options: decodingOptions,
                checkCancellation: checkCancellation
            )
        }

        // Decode tokens to text
        if let tokenizer = tokenizer {
            let rawText = tokenizer.decode(tokens: generatedTokens.map { Int($0) })
            // Strip "language XX<asr_text>" prefix if present (auto-detection output)
            if let range = rawText.range(of: "<asr_text>") {
                return String(rawText[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            return rawText
        } else {
            // Fallback: return token IDs
            return generatedTokens.map { String($0) }.joined(separator: " ")
        }
    }

    /// Greedy with default options: temperature 0, no repetition penalty,
    /// no n-gram blocking.
    static func isGreedyFastPath(_ options: Qwen3DecodingOptions) -> Bool {
        return options.repetitionPenalty == 1.0
            && options.noRepeatNgramSize == 0
            && options.temperature == 0.0
    }

    /// Double-buffered greedy decode loop: builds step N+1's graph and calls
    /// `asyncEval` before syncing step N's token to the CPU.
    static func generateGreedyAsyncEval(
        textDecoder: QuantizedTextModel,
        initialLogits: MLXArray,
        cache initialCache: [(MLXArray, MLXArray)],
        maxTokens: Int,
        checkCancellation: () throws -> Void
    ) rethrows -> [Int32] {
        var generatedTokens: [Int32] = []
        guard maxTokens > 0 else { return generatedTokens }
        try checkCancellation()

        // Cast to int32 explicitly: MLX's `argmax` returns uint32, and the
        // quantized embedding lookup must see int32 for token parity.
        var nextTokenArr = argMax(initialLogits, axis: -1).squeezed().asType(.int32)
        var cache = initialCache
        asyncEval(nextTokenArr, cache)

        let eosToken = Int32(Qwen3ASRTokens.eosTokenId)

        for step in 0..<maxTokens {
            var nextTokenArrN1: MLXArray? = nil
            var cacheN1: [(MLXArray, MLXArray)]? = nil
            if step + 1 < maxTokens {
                try checkCancellation()
                let nextEmbed = textDecoder.embedTokens(
                    nextTokenArr.expandedDimensions(axis: 0).expandedDimensions(axis: 0)
                )
                let (hiddenN1, newCacheN1) = textDecoder(inputsEmbeds: nextEmbed, cache: cache)
                let lastHiddenN1 = hiddenN1[0..., (-1)..., .ellipsis]
                let logitsN1 = textDecoder.embedTokens.asLinear(lastHiddenN1)
                let argN1 = argMax(logitsN1, axis: -1).squeezed().asType(.int32)
                asyncEval(argN1, newCacheN1)
                nextTokenArrN1 = argN1
                cacheN1 = newCacheN1
            }

            let nextToken = nextTokenArr.item(Int32.self)
            generatedTokens.append(nextToken)
            if nextToken == eosToken { break }

            guard let advancedCache = cacheN1, let advancedToken = nextTokenArrN1 else {
                break
            }
            cache = advancedCache
            nextTokenArr = advancedToken
        }
        return generatedTokens
    }

    /// Decode loop for the non-greedy path (repetition penalty, n-gram
    /// blocking, temperature). Pulls logits to the CPU each step.
    static func generateSlow(
        textDecoder: QuantizedTextModel,
        initialLogits: MLXArray,
        cache initialCache: [(MLXArray, MLXArray)],
        maxTokens: Int,
        options: Qwen3DecodingOptions,
        checkCancellation: () throws -> Void
    ) rethrows -> [Int32] {
        var generatedTokens: [Int32] = []
        guard maxTokens > 0 else { return generatedTokens }
        var cache: [(MLXArray, MLXArray)]? = initialCache

        try checkCancellation()
        var nextToken = Self.pickNextToken(
            logits: initialLogits,
            generatedSoFar: generatedTokens,
            options: options
        )
        generatedTokens.append(nextToken)

        for _ in 1..<max(maxTokens, 1) {
            if nextToken == Int32(Qwen3ASRTokens.eosTokenId) { break }
            try checkCancellation()

            let tokenEmbeds = textDecoder.embedTokens(
                MLXArray([nextToken]).expandedDimensions(axis: 0)
            )
            let (hiddenStates, newCache) = textDecoder(inputsEmbeds: tokenEmbeds, cache: cache)
            cache = newCache

            let lastHiddenNext = hiddenStates[0..., (-1)..., .ellipsis]
            let logits = textDecoder.embedTokens.asLinear(lastHiddenNext)
            nextToken = Self.pickNextToken(
                logits: logits,
                generatedSoFar: generatedTokens,
                options: options
            )
            generatedTokens.append(nextToken)
        }
        return generatedTokens
    }

    /// Pick the next token from a logits tensor, applying repetition
    /// penalty, no-repeat n-gram masking, and optional temperature sampling.
    static func pickNextToken(
        logits: MLXArray,
        generatedSoFar: [Int32],
        options: Qwen3DecodingOptions
    ) -> Int32 {
        if options.repetitionPenalty == 1.0,
           options.noRepeatNgramSize == 0,
           options.temperature == 0 {
            return argMax(logits, axis: -1).squeezed().item(Int32.self)
        }

        let flat = logits.squeezed().asType(.float32)
        let vocabSize = flat.size
        var scores: [Float] = flat.asArray(Float.self)
        precondition(scores.count == vocabSize, "pickNextToken: vocab size mismatch")

        if options.repetitionPenalty > 1.0 && !generatedSoFar.isEmpty {
            let penalty = options.repetitionPenalty
            for token in Set(generatedSoFar) {
                let idx = Int(token)
                guard idx >= 0, idx < vocabSize else { continue }
                let v = scores[idx]
                scores[idx] = v > 0 ? v / penalty : v * penalty
            }
        }

        let n = options.noRepeatNgramSize
        if n > 0 && generatedSoFar.count >= n - 1 {
            let lastPrefix = Array(generatedSoFar.suffix(n - 1))
            if generatedSoFar.count >= n {
                for i in 0...(generatedSoFar.count - n) {
                    let window = Array(generatedSoFar[i..<(i + n - 1)])
                    guard window == lastPrefix else { continue }
                    let forbidden = Int(generatedSoFar[i + n - 1])
                    if forbidden >= 0 && forbidden < vocabSize {
                        scores[forbidden] = -.infinity
                    }
                }
            }
        }

        if options.temperature > 0 {
            let t = options.temperature
            for i in 0..<vocabSize {
                let u = Float.random(in: 1e-6...1.0)
                scores[i] = scores[i] / t - Float.log(-Float.log(u))
            }
        }

        var bestIdx = 0
        var bestScore = -Float.infinity
        for i in 0..<vocabSize where scores[i] > bestScore {
            bestScore = scores[i]
            bestIdx = i
        }
        return Int32(bestIdx)
    }
}

enum Qwen3VendorError: Error, LocalizedError {
    case decoderNotLoaded
    case tokenizerMissing(URL)

    var errorDescription: String? {
        switch self {
        case .decoderNotLoaded:
            return "Qwen3-ASR text decoder is not loaded."
        case let .tokenizerMissing(url):
            return "Qwen3-ASR tokenizer is missing at \(url.path)."
        }
    }
}

// MARK: - Model Loading

extension Qwen3ASRModel {
    /// Load the 0.6B 4-bit model from an already verified local directory.
    /// Replaces upstream `fromPretrained`, which downloaded through the
    /// Hugging Face Hub client.
    static func load(from directory: URL) throws -> Qwen3ASRModel {
        let model = Qwen3ASRModel(
            audioConfig: .small,
            textConfig: .small
        )

        let vocabPath = directory.appendingPathComponent("vocab.json")
        guard FileManager.default.fileExists(atPath: vocabPath.path) else {
            throw Qwen3VendorError.tokenizerMissing(vocabPath)
        }
        let tokenizer = Qwen3Tokenizer()
        try tokenizer.load(from: vocabPath)
        model.setTokenizer(tokenizer)

        try WeightLoader.loadWeights(into: model.audioEncoder, from: directory)

        model.initializeTextDecoder()
        if let textDecoder = model.textDecoder {
            try WeightLoader.loadTextDecoderWeights(into: textDecoder, from: directory)
        }
        return model
    }
}

#endif
