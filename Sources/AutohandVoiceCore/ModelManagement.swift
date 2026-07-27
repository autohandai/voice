import FluidAudio
import Foundation

public enum SpeechModelVariant: String, Codable, CaseIterable, Sendable {
    case v2
    case v3

    public static let `default`: Self = .v3

    public var displayName: String {
        switch self {
        case .v2: "Parakeet v2"
        case .v3: "Parakeet v3"
        }
    }

    public var languageCoverage: String {
        switch self {
        case .v2: "English"
        case .v3: "Multilingual (25 European languages)"
        }
    }

    var asrVersion: AsrModelVersion {
        switch self {
        case .v2: .v2
        case .v3: .v3
        }
    }

    public var cacheDirectory: URL {
        AsrModels.defaultCacheDirectory(for: asrVersion)
    }
}

public enum ModelPreparationPhase: Equatable, Sendable {
    case checking
    case listing
    case downloading(completedFiles: Int, totalFiles: Int)
    case compiling(String)
    case loading
    case validating

    public var label: String {
        switch self {
        case .checking: "Checking local model…"
        case .listing: "Checking model files…"
        case let .downloading(completed, total):
            total > 0
                ? "Downloading model files \(completed) of \(total)…"
                : "Downloading model files…"
        case let .compiling(name):
            name.isEmpty ? "Compiling CoreML models…" : "Compiling \(name)…"
        case .loading: "Loading on the Neural Engine…"
        case .validating: "Validating offline readiness…"
        }
    }
}

public struct ModelPreparationProgress: Equatable, Sendable {
    public let fractionCompleted: Double
    public let phase: ModelPreparationPhase

    public init(
        fractionCompleted: Double,
        phase: ModelPreparationPhase
    ) {
        self.fractionCompleted = min(max(fractionCompleted, 0), 1)
        self.phase = phase
    }
}

public enum ModelFailureKind: String, Equatable, Sendable {
    case download
    case storage
    case compilation
    case loading
    case validation

    public static func classify(_ message: String) -> Self {
        let normalized = message.lowercased()
        if normalized.contains("offline")
            || normalized.contains("network")
            || normalized.contains("download")
            || normalized.contains("internet") {
            return .download
        }
        if normalized.contains("missing")
            || normalized.contains("not found")
            || normalized.contains("no such file")
            || normalized.contains("coremldata") {
            return .storage
        }
        if normalized.contains("compile") {
            return .compilation
        }
        if normalized.contains("valid") || normalized.contains("corrupt") {
            return .validation
        }
        return .loading
    }

    public var label: String {
        switch self {
        case .download: "Download failed"
        case .storage: "Model files are missing"
        case .compilation: "CoreML compilation failed"
        case .loading: "Model load failed"
        case .validation: "Model validation failed"
        }
    }
}

public enum ModelCacheInspector {
    public static func storageBytes(at directory: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return 0
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .isSymbolicLinkKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            guard
                values.isRegularFile == true,
                values.isSymbolicLink != true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}
