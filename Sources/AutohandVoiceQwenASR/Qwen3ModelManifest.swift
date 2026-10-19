import AutohandVoiceCore
import Foundation

/// One pinned file of the Qwen3-ASR model repository.
public struct Qwen3ModelFile: Sendable, Equatable, Hashable {
    public let name: String
    /// Lowercase hex SHA-256 of the file contents.
    public let sha256: String
    public let size: Int64

    public init(name: String, sha256: String, size: Int64) {
        self.name = name
        self.sha256 = sha256
        self.size = size
    }
}

/// The exact Hugging Face repository revision and files Autohand Voice
/// downloads for the optional Qwen3-ASR engine. Every file is pinned by
/// commit, size and SHA-256 so a moved branch or a tampered mirror cannot
/// change what runs on the user's Mac.
public struct Qwen3ModelManifest: Sendable, Equatable {
    public let repository: String
    /// Full 40-character commit SHA of the model repository.
    public let revision: String
    public let files: [Qwen3ModelFile]
    /// Folder name under the shared local model cache.
    public let directoryName: String

    public init(
        repository: String,
        revision: String,
        files: [Qwen3ModelFile],
        directoryName: String
    ) {
        self.repository = repository
        self.revision = revision
        self.files = files
        self.directoryName = directoryName
    }

    /// `aufklarer/Qwen3-ASR-0.6B-MLX-4bit` (Apache-2.0), quantized from
    /// `Qwen/Qwen3-ASR-0.6B`. Sizes and hashes come from the Hugging Face
    /// API (`siblings[].lfs.sha256` for the LFS weights) and were verified by
    /// downloading each file at this revision.
    public static let qwen3ASR06B4bit = Qwen3ModelManifest(
        repository: "aufklarer/Qwen3-ASR-0.6B-MLX-4bit",
        revision: "bc441bd1e4295c1f42d9879f056049a925b6e013",
        files: [
            Qwen3ModelFile(
                name: "model.safetensors",
                sha256: "70c7e67e588062adce4f10796e47ad42ead51c6671eda61a0987eae38ca95ddf",
                size: 708_236_945
            ),
            Qwen3ModelFile(
                name: "vocab.json",
                sha256: "ca10d7e9fb3ed18575dd1e277a2579c16d108e32f27439684afa0e10b1440910",
                size: 2_776_833
            ),
            Qwen3ModelFile(
                name: "merges.txt",
                sha256: "8831e4f1a044471340f7c0a83d7bd71306a5b867e95fd870f74d0c5308a904d5",
                size: 1_671_853
            ),
            Qwen3ModelFile(
                name: "tokenizer_config.json",
                sha256: "4942d005604266809309cabc9f4e9cb89ce855d59b14681fdc0e1cc62ea26c4c",
                size: 12_487
            ),
        ],
        directoryName: "qwen3-asr-0.6b-mlx-4bit"
    )

    public static let `default` = qwen3ASR06B4bit

    public var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    /// `https://huggingface.co/<repository>/resolve/<revision>/<file>`.
    public func remoteURL(for file: Qwen3ModelFile) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "huggingface.co"
        components.path = "/\(repository)/resolve/\(revision)/\(file.name)"
        return components.url!
    }

    /// Sibling of the Parakeet model folders in the shared local model
    /// cache, e.g. `~/Library/Application Support/FluidAudio/Models/
    /// qwen3-asr-0.6b-mlx-4bit`.
    public var defaultCacheDirectory: URL {
        SpeechModelVariant.v3.cacheDirectory
            .deletingLastPathComponent()
            .appendingPathComponent(directoryName, isDirectory: true)
    }

    /// True when the manifest is fully pinned and every file name is a plain
    /// file name that cannot escape the cache directory.
    public var isPinned: Bool {
        Self.isHex(revision, length: 40)
            && !files.isEmpty
            && Set(files.map(\.name)).count == files.count
            && files.allSatisfy { file in
                Self.isHex(file.sha256, length: 64)
                    && file.size > 0
                    && Self.isSafeFileName(file.name)
            }
            && Self.isSafeFileName(directoryName)
    }

    static func isHex(_ value: String, length: Int) -> Bool {
        value.count == length
            && value.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty
            && name != "."
            && name != ".."
            && !name.hasPrefix(".")
            && !name.contains("/")
            && !name.contains("\\")
            && !name.contains("\0")
    }
}
