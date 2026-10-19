import Foundation

/// Who answers Talk questions.
public enum TalkEngine: String, Codable, CaseIterable, Sendable {
    /// Autohand's Fantail model; needs a signed-in Autohand account.
    case fantail
    /// A small model that runs on this Mac; nothing leaves it.
    case local

    public var usesNetwork: Bool { self == .fantail }
}

/// Which local model turns speech into text.
public enum DictationModel: String, Codable, CaseIterable, Sendable {
    /// NVIDIA Parakeet on Core ML (the default).
    case parakeet
    /// Qwen3-ASR 0.6B on MLX (Apple Silicon).
    case qwen3

    public var usesNetwork: Bool { false }
}
