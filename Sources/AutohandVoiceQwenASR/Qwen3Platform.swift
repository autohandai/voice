import Foundation
import Metal

/// Where and whether the MLX Qwen3-ASR engine can run.
///
/// MLX runs on Apple GPUs only. The x86_64 slice of the universal app links
/// MLX but never calls it: Qwen3-ASR reports itself unavailable on Intel and
/// under Rosetta instead of crashing.
public enum Qwen3Platform {
    public enum Architecture: String, Sendable, Equatable {
        case arm64
        case x86_64
    }

    public static var currentArchitecture: Architecture {
        #if arch(arm64)
        .arm64
        #else
        .x86_64
        #endif
    }

    public static func isSupported(
        architecture: Architecture,
        hasMetalDevice: Bool
    ) -> Bool {
        architecture == .arm64 && hasMetalDevice
    }

    static var hasAppleGPU: Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.supportsFamily(.apple7)
    }

    /// Mirrors the order mlx-swift 0.31.4 uses in `load_default_library`
    /// (`mlx/backend/metal/device.cpp`): `mlx.metallib` next to the binary,
    /// `Resources/mlx.metallib` next to the binary, then `default.metallib`
    /// inside an `mlx-swift_Cmlx.bundle` in the main bundle's resources.
    /// MLX throws a C++ exception (fatal in Swift) when none is found, so the
    /// recognizer checks this before it touches MLX.
    public static func locateMetalLibrary(
        executableURL: URL? = Bundle.main.executableURL,
        resourceURL: URL? = Bundle.main.resourceURL,
        bundleURL: URL? = Bundle.main.bundleURL
    ) -> URL? {
        var candidates: [URL] = []
        if let directory = executableURL?.resolvingSymlinksInPath()
            .deletingLastPathComponent() {
            candidates.append(directory.appendingPathComponent("mlx.metallib"))
            candidates.append(
                directory.appendingPathComponent("Resources/mlx.metallib")
            )
        }
        for root in [bundleURL, resourceURL].compactMap({ $0 }) {
            let bundle = root.appendingPathComponent(
                "mlx-swift_Cmlx.bundle",
                isDirectory: true
            )
            candidates.append(
                bundle.appendingPathComponent("Contents/Resources/default.metallib")
            )
            candidates.append(bundle.appendingPathComponent("default.metallib"))
        }
        return candidates.first { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ) && !isDirectory.boolValue
        }
    }
}

/// The runtime facts the recognizer gates on. Injected in tests.
public struct Qwen3RuntimeEnvironment: Sendable, Equatable {
    public let isSupported: Bool
    public let unsupportedReason: String?
    public let metalLibraryURL: URL?

    public init(
        isSupported: Bool,
        unsupportedReason: String?,
        metalLibraryURL: URL?
    ) {
        self.isSupported = isSupported
        self.unsupportedReason = unsupportedReason
        self.metalLibraryURL = metalLibraryURL
    }

    public static var current: Qwen3RuntimeEnvironment {
        let architecture = Qwen3Platform.currentArchitecture
        let hasGPU = architecture == .arm64 && Qwen3Platform.hasAppleGPU
        let supported = Qwen3Platform.isSupported(
            architecture: architecture,
            hasMetalDevice: hasGPU
        )
        let reason: String?
        if supported {
            reason = nil
        } else if architecture != .arm64 {
            reason = "Qwen3-ASR requires a Mac with Apple Silicon. Use Parakeet on this Mac."
        } else {
            reason = "Qwen3-ASR requires an Apple Silicon GPU with Metal. Use Parakeet on this Mac."
        }
        return Qwen3RuntimeEnvironment(
            isSupported: supported,
            unsupportedReason: reason,
            metalLibraryURL: supported ? Qwen3Platform.locateMetalLibrary() : nil
        )
    }
}

/// Maps Autohand Voice dictation language codes to the language names
/// Qwen3-ASR uses in its `language <Name>` prompt. Unknown codes return nil,
/// which lets the model auto-detect the language.
public enum Qwen3LanguageHint {
    /// The 30 languages documented for Qwen3-ASR (dialects excluded).
    static let names: [String: String] = [
        "ar": "Arabic",
        "cs": "Czech",
        "da": "Danish",
        "de": "German",
        "el": "Greek",
        "en": "English",
        "es": "Spanish",
        "fa": "Persian",
        "fi": "Finnish",
        "fil": "Filipino",
        "fr": "French",
        "hi": "Hindi",
        "hu": "Hungarian",
        "id": "Indonesian",
        "it": "Italian",
        "ja": "Japanese",
        "ko": "Korean",
        "mk": "Macedonian",
        "ms": "Malay",
        "nl": "Dutch",
        "pl": "Polish",
        "pt": "Portuguese",
        "ro": "Romanian",
        "ru": "Russian",
        "sv": "Swedish",
        "th": "Thai",
        "tl": "Filipino",
        "tr": "Turkish",
        "vi": "Vietnamese",
        "yue": "Cantonese",
        "zh": "Chinese",
    ]

    public static func name(forCode code: String) -> String? {
        let base = code
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
            .map(String.init) ?? ""
        return names[base]
    }
}
