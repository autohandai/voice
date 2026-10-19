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

/// Talk (Fn + Shift) is offered only on Macs with Apple Silicon. On Intel,
/// Fn + Shift stays plain dictation.
public enum TalkAvailability {
    public static let unavailableReason =
        "Talk needs a Mac with Apple Silicon. Dictation works as usual on this Mac."

    public static func isAvailable(architecture: String) -> Bool {
        architecture == "arm64"
    }

    public static var onThisMac: Bool {
        SystemCheck.isAppleSilicon
    }
}
