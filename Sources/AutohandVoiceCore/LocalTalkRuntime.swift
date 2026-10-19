import Foundation

/// Which in-process runtime answers Talk "On this Mac". Both run Ternary
/// Bonsai 2 (2B) locally; neither sends anything off the Mac.
public enum LocalTalkRuntime: String, CaseIterable, Codable, Sendable {
    /// llama.cpp with the Q2_0 GGUF. Metal on Apple Silicon, CPU on Intel.
    case llamaCpp = "llama"
    /// MLX with the 2-bit Hadamard pack. Apple Silicon GPUs only.
    case mlx

    /// Accepts the names the CLI documents (`mlx`, `llama`, `llama.cpp`,
    /// `gguf`), case-insensitively.
    public init?(argument: String) {
        switch argument.lowercased() {
        case "mlx": self = .mlx
        case "llama", "llama.cpp", "llamacpp", "gguf": self = .llamaCpp
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .llamaCpp: "llama.cpp"
        case .mlx: "MLX"
        }
    }

    /// The runtime to use. An explicit request is honoured as is, so a
    /// runtime that cannot run here fails visibly rather than being swapped
    /// for the other one. Without a request, MLX is preferred only when it
    /// can run on this Mac and its model is already installed; otherwise
    /// llama.cpp (the only runtime on Intel and under Rosetta).
    public static func resolve(
        requested: LocalTalkRuntime?,
        mlxSupported: Bool,
        mlxInstalled: Bool
    ) -> LocalTalkRuntime {
        if let requested { return requested }
        return mlxSupported && mlxInstalled ? .mlx : .llamaCpp
    }
}

/// An on-device Talk model runtime: downloads its pinned model once,
/// loads it, and streams replies with reasoning removed.
public protocol OnDeviceTalkEngine: AnyObject, Sendable {
    var runtime: LocalTalkRuntime { get }
    var displayName: String { get }
    /// Bytes the first download fetches.
    var downloadSize: Int64 { get }
    var isInstalled: Bool { get }
    var isLoaded: Bool { get }
    /// Why this runtime can't run on this Mac, or nil when it can.
    var unavailableReason: String? { get }

    /// Downloads (first use only) and loads the model.
    func prepare(onProgress: @escaping @Sendable (Double) -> Void) async throws
    /// Streams the reply text for a conversation (system prompt first).
    func reply(
        to messages: [TalkMessage],
        maxTokens: Int
    ) -> AsyncThrowingStream<String, Error>
    /// Frees the model's memory; it reloads on the next question.
    func unload()
    func removeDownloadedModel() throws
}

/// Token counts and timings of one on-device reply (CLI diagnostics).
public struct LocalTalkGenerationStatistics: Sendable, Equatable {
    public let promptTokens: Int
    public let generatedTokens: Int
    /// Prompt processing up to the first sampled token.
    public let prefillSeconds: Double
    /// From the first sampled token to the end of generation.
    public let decodeSeconds: Double

    public init(
        promptTokens: Int,
        generatedTokens: Int,
        prefillSeconds: Double,
        decodeSeconds: Double
    ) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.prefillSeconds = prefillSeconds
        self.decodeSeconds = decodeSeconds
    }

    public var decodeTokensPerSecond: Double {
        decodeSeconds > 0 ? Double(generatedTokens) / decodeSeconds : 0
    }

    public var prefillTokensPerSecond: Double {
        prefillSeconds > 0 ? Double(promptTokens) / prefillSeconds : 0
    }
}
