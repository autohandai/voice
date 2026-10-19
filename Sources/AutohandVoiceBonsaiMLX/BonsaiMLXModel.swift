import AutohandVoiceCore
import AutohandVoiceQwenASR
import Foundation
import Metal

/// The MLX build of Ternary Bonsai 2 (2B): `prism-ml/Ternary-Bonsai-2-2B-
/// mlx-2bit` (Apache-2.0, built from Qwen3.5-2B). MLX affine 2-bit, group
/// size 128, with a signed Hadamard rotation folded into every packed
/// weight that the runtime undoes on the activations.
public enum BonsaiMLXModel {
    public static let displayName = "Ternary Bonsai 2 (2B, MLX)"

    /// Pinned by commit, size and SHA-256 (from the Hugging Face API and the
    /// pack's own `files.json`, verified by downloading at this revision).
    /// Only what the Swift runtime reads plus the license and notice: no
    /// `runtime/` Python, chat template, or image/video processor files.
    /// `model.safetensors` also carries the unused vision tower; its tensors
    /// are never read into memory.
    public static let manifest = Qwen3ModelManifest(
        repository: "prism-ml/Ternary-Bonsai-2-2B-mlx-2bit",
        revision: "1c6cbae21f8c38830ce337972b46fdae7b18eaaa",
        files: [
            Qwen3ModelFile(
                name: "model.safetensors",
                sha256: "da5095b9f34d7f0d5094090afeeadf124eef821c75136dc28957ce586ae7ac0c",
                size: 1_200_284_784
            ),
            Qwen3ModelFile(
                name: "config.json",
                sha256: "f8d80cb7fd148b8841e63051c337d2758b4bc16243c577d35eaab6779534b591",
                size: 22_998
            ),
            Qwen3ModelFile(
                name: "tokenizer.json",
                sha256: "5f9e4d4901a92b997e463c1f46055088b6cca5ca61a6522d1b9f64c4bb81cb42",
                size: 12_807_982
            ),
            Qwen3ModelFile(
                name: "generation_config.json",
                sha256: "a3345cadb9d63a91a11c2c12135da7eadc3d0c820e3287b04682b51cad1b12d2",
                size: 201
            ),
            Qwen3ModelFile(
                name: "LICENSE",
                sha256: "69849221bfb90053de2134ef5e6d540287b4b98062326492f1f96f5da685524b",
                size: 10_174
            ),
            Qwen3ModelFile(
                name: "NOTICE.txt",
                sha256: "316012fa6094c03c7b0600bec258bffb675a9261d86f37bc86e15763a1fabc99",
                size: 409
            ),
        ],
        directoryName: "ternary-bonsai-2-2b-mlx"
    )

    /// Beside the GGUF build: `~/Library/Application Support/Autohand Voice/
    /// Models/ternary-bonsai-2-2b-mlx`.
    public static var defaultDirectory: URL {
        Brand.localModelsDirectory.appendingPathComponent(
            manifest.directoryName,
            isDirectory: true
        )
    }
}

/// Where and whether the MLX runtime can run. MLX needs an Apple GPU and
/// its compiled kernels (`mlx.metallib`); the x86_64 slice of the universal
/// app links MLX but never calls it.
public struct BonsaiMLXEnvironment: Sendable, Equatable {
    public let architecture: Qwen3Platform.Architecture
    public let isSupported: Bool
    public let unavailableReason: String?
    public let metalLibraryURL: URL?

    public static func isSupported(
        architecture: Qwen3Platform.Architecture,
        hasAppleGPU: Bool
    ) -> Bool {
        Qwen3Platform.isSupported(
            architecture: architecture,
            hasMetalDevice: hasAppleGPU
        )
    }

    public static func make(
        architecture: Qwen3Platform.Architecture,
        hasAppleGPU: Bool,
        metalLibraryURL: URL?
    ) -> BonsaiMLXEnvironment {
        let reason: String?
        if architecture != .arm64 {
            reason = "The MLX runtime needs a Mac with Apple Silicon. Talk uses llama.cpp on this Mac."
        } else if !hasAppleGPU {
            reason = "The MLX runtime needs an Apple Silicon GPU with Metal. Talk uses llama.cpp on this Mac."
        } else if metalLibraryURL == nil {
            reason = "The MLX GPU kernels (mlx.metallib) are missing from this build. Reinstall Autohand Voice."
        } else {
            reason = nil
        }
        return BonsaiMLXEnvironment(
            architecture: architecture,
            isSupported: reason == nil,
            unavailableReason: reason,
            metalLibraryURL: metalLibraryURL
        )
    }

    public static let current: BonsaiMLXEnvironment = {
        let architecture = Qwen3Platform.currentArchitecture
        let hasGPU = architecture == .arm64 && hasAppleGPU
        return make(
            architecture: architecture,
            hasAppleGPU: hasGPU,
            metalLibraryURL: hasGPU ? Qwen3Platform.locateMetalLibrary() : nil
        )
    }()

    private static var hasAppleGPU: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsFamily(.apple7)
    }
}

public enum BonsaiMLXError: Error, LocalizedError, Equatable {
    case unavailable(String)
    case invalidModel(String)
    case promptTooLong(Int)
    case notLoaded

    public var errorDescription: String? {
        switch self {
        case let .unavailable(reason): reason
        case let .invalidModel(reason): "The MLX Talk model couldn't be loaded: \(reason)"
        case let .promptTooLong(count):
            "The conversation is too long for the model (\(count) tokens)."
        case .notLoaded: "The MLX Talk model isn't loaded."
        }
    }
}
