import Foundation

/// Talk's sampling settings. The defaults are the llama.cpp runtime's
/// (`LlamaChatRuntime.Sampling`), so both runtimes answer alike.
public struct BonsaiSamplingSettings: Sendable, Equatable {
    /// 0 or below decodes greedily.
    public var temperature: Float
    /// 1 disables nucleus filtering.
    public var topP: Float
    /// 0 disables top-k filtering.
    public var topK: Int
    /// Subtracted once from the logit of any token seen in the window.
    public var presencePenalty: Float
    /// How many recent tokens the presence penalty looks at.
    public var penaltyWindow: Int

    public init(
        temperature: Float = 0.7,
        topP: Float = 0.8,
        topK: Int = 20,
        presencePenalty: Float = 1.5,
        penaltyWindow: Int = 64
    ) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.penaltyWindow = penaltyWindow
    }

    /// Deterministic argmax decoding, no penalties.
    public static let greedy = BonsaiSamplingSettings(
        temperature: 0,
        topP: 1,
        topK: 0,
        presencePenalty: 0,
        penaltyWindow: 64
    )
}

/// Picks the next token the way llama.cpp's Talk sampler chain does:
/// top-k, presence penalty, top-p (at temperature 1), temperature, then a
/// draw from the softmax. Pure Swift over a candidate list, so the model
/// only has to hand over the top-k logits.
public struct BonsaiSampler: Sendable {
    public struct Candidate: Sendable, Equatable {
        public var id: Int
        public var logit: Float

        public init(id: Int, logit: Float) {
            self.id = id
            self.logit = logit
        }
    }

    public let settings: BonsaiSamplingSettings
    private var generator: SplitMix64

    public init(settings: BonsaiSamplingSettings, seed: UInt64? = nil) {
        self.settings = settings
        self.generator = SplitMix64(seed: seed ?? UInt64.random(in: .min ... .max))
    }

    /// The `k` highest logits, best first. `k <= 0` or `k >= count` keeps
    /// all of them.
    public static func topK(_ logits: [Float], k: Int) -> [Candidate] {
        var all = logits.enumerated().map { Candidate(id: $0.offset, logit: $0.element) }
        if k > 0, k < all.count {
            // Partial selection: keep a sorted window of the best k.
            var best: [Candidate] = []
            best.reserveCapacity(k + 1)
            for candidate in all {
                if best.count == k, let last = best.last, candidate.logit <= last.logit {
                    continue
                }
                let index = best.firstIndex { $0.logit < candidate.logit } ?? best.count
                best.insert(candidate, at: index)
                if best.count > k { best.removeLast() }
            }
            return best
        }
        all.sort { $0.logit > $1.logit }
        return all
    }

    public mutating func sample(
        _ candidates: [Candidate],
        recentTokens: [Int]
    ) -> Int {
        var pool = candidates.sorted { $0.logit > $1.logit }
        guard !pool.isEmpty else { return 0 }
        if settings.topK > 0, pool.count > settings.topK {
            pool.removeLast(pool.count - settings.topK)
        }

        if settings.presencePenalty != 0, settings.penaltyWindow > 0 {
            let recent = Set(recentTokens.suffix(settings.penaltyWindow))
            for index in pool.indices where recent.contains(pool[index].id) {
                pool[index].logit -= settings.presencePenalty
            }
            pool.sort { $0.logit > $1.logit }
        }

        if settings.topP < 1, pool.count > 1 {
            let probabilities = Self.softmax(pool.map(\.logit))
            var cumulative: Float = 0
            var keep = pool.count
            for (index, probability) in probabilities.enumerated() {
                cumulative += probability
                if cumulative >= settings.topP {
                    keep = index + 1
                    break
                }
            }
            pool.removeLast(pool.count - keep)
        }

        guard settings.temperature > 0 else { return pool[0].id }
        let probabilities = Self.softmax(pool.map { $0.logit / settings.temperature })
        let draw = Float(Double(generator.next() >> 11) / Double(1 << 53))
        var cumulative: Float = 0
        for (index, probability) in probabilities.enumerated() {
            cumulative += probability
            if draw < cumulative { return pool[index].id }
        }
        return pool[pool.count - 1].id
    }

    static func softmax(_ logits: [Float]) -> [Float] {
        guard let maximum = logits.max() else { return [] }
        let exps = logits.map { Float(exp(Double($0 - maximum))) }
        let sum = exps.reduce(0, +)
        return exps.map { $0 / sum }
    }
}

/// Small, fast, seedable generator (Steele et al., SplitMix64).
struct SplitMix64: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
