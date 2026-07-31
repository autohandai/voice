import CryptoKit
import Foundation

public enum LocalTransformLimits {
    public static let maximumTemplates = 32
    public static let maximumTemplateCharacters = 2_000
    public static let maximumInputCharacters = 100_000
    public static let maximumOutputCharacters = 100_000
    public static let maximumManifestBytes = 64 * 1_024
    public static let maximumTemplateFileBytes = 512 * 1_024
    public static let maximumModelBytes: Int64 = 8 * 1_024 * 1_024 * 1_024
}

public enum LocalTransformPreset:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    case polish
    case promptBuilder
    case custom(UUID)
}

public struct TransformTemplate:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    public let id: UUID
    public var name: String
    public var instruction: String

    public init(
        id: UUID = UUID(),
        name: String,
        instruction: String
    ) {
        self.id = id
        self.name = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(80)
        )
        self.instruction = String(
            instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(LocalTransformLimits.maximumTemplateCharacters)
        )
    }

    public var isValid: Bool {
        !name.isEmpty
            && !instruction.isEmpty
            && name.count <= 80
            && instruction.count
                <= LocalTransformLimits.maximumTemplateCharacters
    }
}

public enum TransformTemplateStoreError:
    Error,
    Equatable,
    LocalizedError
{
    case invalidTemplate
    case duplicateIdentifier
    case tooManyTemplates
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidTemplate:
            "Every local Transform template needs a name and instruction."
        case .duplicateIdentifier:
            "Local Transform template identifiers must be unique."
        case .tooManyTemplates:
            "Local Transform templates are limited to 32."
        case .fileTooLarge:
            "The local Transform template file exceeds its limit."
        }
    }
}

public struct TransformTemplateStore: Sendable {
    public let url: URL

    public init(url: URL = Brand.transformTemplatesURL) {
        self.url = url
    }

    public static func validate(
        _ templates: [TransformTemplate]
    ) throws {
        guard templates.count <= LocalTransformLimits.maximumTemplates else {
            throw TransformTemplateStoreError.tooManyTemplates
        }
        guard templates.allSatisfy(\.isValid) else {
            throw TransformTemplateStoreError.invalidTemplate
        }
        guard Set(templates.map(\.id)).count == templates.count else {
            throw TransformTemplateStoreError.duplicateIdentifier
        }
    }

    public func load() throws -> [TransformTemplate] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let size = (
            try FileManager.default.attributesOfItem(atPath: url.path)[.size]
                as? NSNumber
        )?.intValue ?? 0
        guard size <= LocalTransformLimits.maximumTemplateFileBytes else {
            throw TransformTemplateStoreError.fileTooLarge
        }
        let templates = try JSONDecoder().decode(
            [TransformTemplate].self,
            from: Data(contentsOf: url)
        )
        try Self.validate(templates)
        return templates
    }

    public func save(_ templates: [TransformTemplate]) throws {
        try Self.validate(templates)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(templates)
        guard data.count <= LocalTransformLimits.maximumTemplateFileBytes
        else {
            throw TransformTemplateStoreError.fileTooLarge
        }
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

public struct LocalTransformModelManifest:
    Codable,
    Equatable,
    Sendable
{
    public let schemaVersion: Int
    public let modelVersion: String
    public let modelSHA256: String
    public let signature: Data
    public let licenseIdentifier: String
    public let modelByteCount: Int64
    public let supportedLanguageCodes: [String]
    public let maximumInputCharacters: Int
    public let maximumOutputCharacters: Int
    public let requiresAppleNeuralEngine: Bool

    public init(
        schemaVersion: Int = 1,
        modelVersion: String,
        modelSHA256: String,
        signature: Data,
        licenseIdentifier: String,
        modelByteCount: Int64,
        supportedLanguageCodes: [String],
        maximumInputCharacters: Int =
            LocalTransformLimits.maximumInputCharacters,
        maximumOutputCharacters: Int =
            LocalTransformLimits.maximumOutputCharacters,
        requiresAppleNeuralEngine: Bool = true
    ) {
        self.schemaVersion = schemaVersion
        self.modelVersion = String(modelVersion.prefix(64))
        self.modelSHA256 = modelSHA256.lowercased()
        self.signature = signature
        self.licenseIdentifier = String(licenseIdentifier.prefix(100))
        self.modelByteCount = max(modelByteCount, 0)
        self.supportedLanguageCodes = Array(
            Set(supportedLanguageCodes.map {
                String($0.prefix(32))
            })
        ).sorted()
        self.maximumInputCharacters = min(
            max(maximumInputCharacters, 1),
            LocalTransformLimits.maximumInputCharacters
        )
        self.maximumOutputCharacters = min(
            max(maximumOutputCharacters, 1),
            LocalTransformLimits.maximumOutputCharacters
        )
        self.requiresAppleNeuralEngine = requiresAppleNeuralEngine
    }

    public var signedPayload: Data? {
        try? JSONEncoder.transform.encode(
            UnsignedLocalTransformManifest(self)
        )
    }
}

public enum LocalTransformArtifactError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case manifestTooLarge
    case invalidManifest
    case invalidSignature
    case modelMissing
    case checksumMismatch
    case unsupportedPlatform
    case unsupportedLanguage

    public var errorDescription: String? {
        switch self {
        case .manifestTooLarge:
            "The local Transform manifest exceeds its limit."
        case .invalidManifest:
            "The local Transform manifest is invalid."
        case .invalidSignature:
            "The local Transform signature is invalid."
        case .modelMissing:
            "The local Transform CoreML model is not installed."
        case .checksumMismatch:
            "The local Transform model checksum does not match."
        case .unsupportedPlatform:
            "This local Transform requires Apple Silicon and the Neural Engine."
        case .unsupportedLanguage:
            "The local Transform does not support this language."
        }
    }
}

public struct ValidatedLocalTransformArtifact: Sendable {
    public let manifest: LocalTransformModelManifest
    public let modelURL: URL
}

public enum LocalTransformArtifactValidator {
    public static func validate(
        manifestData: Data,
        modelURL: URL,
        signerPublicKey: Data,
        languageCode: String? = nil
    ) throws -> ValidatedLocalTransformArtifact {
        guard manifestData.count <= LocalTransformLimits.maximumManifestBytes
        else {
            throw LocalTransformArtifactError.manifestTooLarge
        }
        let manifest: LocalTransformModelManifest
        do {
            manifest = try JSONDecoder().decode(
                LocalTransformModelManifest.self,
                from: manifestData
            )
        } catch {
            throw LocalTransformArtifactError.invalidManifest
        }
        guard
            manifest.schemaVersion == 1,
            manifest.modelSHA256.count == 64,
            manifest.modelSHA256.allSatisfy(\.isHexDigit),
            !manifest.modelVersion.isEmpty,
            !manifest.licenseIdentifier.isEmpty,
            manifest.modelByteCount > 0,
            manifest.requiresAppleNeuralEngine,
            let payload = manifest.signedPayload
        else {
            throw LocalTransformArtifactError.invalidManifest
        }
        let publicKey: Curve25519.Signing.PublicKey
        do {
            publicKey = try Curve25519.Signing.PublicKey(
                rawRepresentation: signerPublicKey
            )
        } catch {
            throw LocalTransformArtifactError.invalidSignature
        }
        guard publicKey.isValidSignature(
            manifest.signature,
            for: payload
        ) else {
            throw LocalTransformArtifactError.invalidSignature
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalTransformArtifactError.modelMissing
        }
        let digest: (byteCount: Int64, sha256: String)
        do {
            digest = try artifactDigest(at: modelURL)
        } catch let error as LocalTransformArtifactError {
            throw error
        } catch {
            throw LocalTransformArtifactError.modelMissing
        }
        guard digest.byteCount == manifest.modelByteCount else {
            throw LocalTransformArtifactError.checksumMismatch
        }
        guard digest.sha256 == manifest.modelSHA256 else {
            throw LocalTransformArtifactError.checksumMismatch
        }
        if let languageCode,
           !manifest.supportedLanguageCodes.contains(languageCode) {
            throw LocalTransformArtifactError.unsupportedLanguage
        }
        #if arch(arm64)
        return ValidatedLocalTransformArtifact(
            manifest: manifest,
            modelURL: modelURL
        )
        #else
        throw LocalTransformArtifactError.unsupportedPlatform
        #endif
    }

    /// Hashes a regular artifact as its raw bytes. A compiled `.mlmodelc`
    /// directory is hashed as a sorted sequence of relative UTF-8 path,
    /// byte-count, and file-byte records so the signed digest is stable across
    /// filesystem enumeration order.
    public static func artifactDigest(
        at url: URL
    ) throws -> (byteCount: Int64, sha256: String) {
        let rootValues = try url.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard rootValues.isSymbolicLink != true else {
            throw LocalTransformArtifactError.checksumMismatch
        }
        if rootValues.isRegularFile == true {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard Int64(data.count) <= LocalTransformLimits.maximumModelBytes
            else {
                throw LocalTransformArtifactError.checksumMismatch
            }
            return (
                Int64(data.count),
                hex(SHA256.hash(data: data))
            )
        }
        guard rootValues.isDirectory == true else {
            throw LocalTransformArtifactError.modelMissing
        }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            throw LocalTransformArtifactError.modelMissing
        }
        var files: [(relative: String, url: URL, size: Int)] = []
        for case let child as URL in enumerator {
            let values = try child.resourceValues(
                forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                ]
            )
            guard values.isSymbolicLink != true else {
                throw LocalTransformArtifactError.checksumMismatch
            }
            guard values.isRegularFile == true else { continue }
            let relative = String(
                child.path.dropFirst(url.path.count + 1)
            )
            guard
                !relative.isEmpty,
                !relative.contains("../"),
                let size = values.fileSize,
                size >= 0
            else {
                throw LocalTransformArtifactError.checksumMismatch
            }
            files.append((relative, child, size))
        }
        files.sort { $0.relative < $1.relative }
        guard !files.isEmpty else {
            throw LocalTransformArtifactError.modelMissing
        }
        var total: Int64 = 0
        var hasher = SHA256()
        for file in files {
            total += Int64(file.size)
            guard total <= LocalTransformLimits.maximumModelBytes else {
                throw LocalTransformArtifactError.checksumMismatch
            }
            let pathData = Data(file.relative.utf8)
            var pathLength = UInt32(pathData.count).bigEndian
            withUnsafeBytes(of: &pathLength) {
                hasher.update(data: Data($0))
            }
            hasher.update(data: pathData)
            var fileLength = UInt64(file.size).bigEndian
            withUnsafeBytes(of: &fileLength) {
                hasher.update(data: Data($0))
            }
            let data = try Data(
                contentsOf: file.url,
                options: [.mappedIfSafe]
            )
            guard data.count == file.size else {
                throw LocalTransformArtifactError.checksumMismatch
            }
            hasher.update(data: data)
        }
        return (total, hex(hasher.finalize()))
    }

    private static func hex<D: Sequence>(_ digest: D) -> String
        where D.Element == UInt8
    {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

public enum LocalTransformFailure:
    String,
    Codable,
    Equatable,
    Sendable
{
    case modelUnavailable = "model_unavailable"
    case cancelled
    case inputTooLong = "input_too_long"
    case invalidOutput = "invalid_output"
    case unsupportedLanguage = "unsupported_language"
    case secureTarget = "secure_target"
    case runnerFailed = "runner_failed"
}

public struct LocalTransformRequest: Equatable, Sendable {
    public let input: String
    public let languageCode: String
    public let preset: LocalTransformPreset
    public let isSecureTarget: Bool

    public init(
        input: String,
        languageCode: String,
        preset: LocalTransformPreset,
        isSecureTarget: Bool = false
    ) {
        self.input = input
        self.languageCode = String(languageCode.prefix(32))
        self.preset = preset
        self.isSecureTarget = isSecureTarget
    }
}

public struct LocalTransformProposal: Equatable, Sendable {
    public let input: String
    public let output: String
    public let changes: [BoundedTextChange]
    public let modelVersion: String?
    public let failure: LocalTransformFailure?

    public var changed: Bool {
        failure == nil && output != input
    }
}

public protocol LocalTransformRunning: Sendable {
    var modelVersion: String { get }
    var supportedLanguageCodes: Set<String> { get }
    func run(
        input: String,
        instruction: String
    ) async throws -> String
}

public actor LocalTransformEngine {
    private let runner: (any LocalTransformRunning)?
    private let templates: [UUID: TransformTemplate]

    public init(
        runner: (any LocalTransformRunning)? = nil,
        templates: [TransformTemplate] = []
    ) {
        self.runner = runner
        self.templates = Dictionary(
            uniqueKeysWithValues: templates.map { ($0.id, $0) }
        )
    }

    public func propose(
        _ request: LocalTransformRequest
    ) async -> LocalTransformProposal {
        guard !request.isSecureTarget else {
            return unchanged(request, failure: .secureTarget)
        }
        guard
            !request.input.isEmpty,
            request.input.count
                <= LocalTransformLimits.maximumInputCharacters
        else {
            return unchanged(request, failure: .inputTooLong)
        }
        guard let runner else {
            return unchanged(request, failure: .modelUnavailable)
        }
        guard runner.supportedLanguageCodes.contains(request.languageCode)
        else {
            return unchanged(request, failure: .unsupportedLanguage)
        }
        let instruction: String
        switch request.preset {
        case .polish:
            instruction =
                "Polish the selected text while preserving its meaning."
        case .promptBuilder:
            instruction =
                "Restructure the selected text as a clear reusable prompt."
        case let .custom(id):
            guard let template = templates[id] else {
                return unchanged(request, failure: .invalidOutput)
            }
            instruction = template.instruction
        }
        do {
            try Task.checkCancellation()
            let output = try await runner.run(
                input: request.input,
                instruction: instruction
            )
            try Task.checkCancellation()
            guard
                output.contains(where: { !$0.isWhitespace }),
                output.count
                    <= LocalTransformLimits.maximumOutputCharacters
            else {
                return unchanged(request, failure: .invalidOutput)
            }
            return LocalTransformProposal(
                input: request.input,
                output: output,
                changes: output == request.input
                    ? []
                    : [
                        BoundedTextChange(
                            characterOffset: 0,
                            removedText: request.input,
                            insertedText: output
                        ),
                    ],
                modelVersion: runner.modelVersion,
                failure: nil
            )
        } catch is CancellationError {
            return unchanged(request, failure: .cancelled)
        } catch {
            return unchanged(request, failure: .runnerFailed)
        }
    }

    private func unchanged(
        _ request: LocalTransformRequest,
        failure: LocalTransformFailure
    ) -> LocalTransformProposal {
        LocalTransformProposal(
            input: request.input,
            output: request.input,
            changes: [],
            modelVersion: runner?.modelVersion,
            failure: failure
        )
    }
}

private struct UnsignedLocalTransformManifest: Encodable {
    let schemaVersion: Int
    let modelVersion: String
    let modelSHA256: String
    let licenseIdentifier: String
    let modelByteCount: Int64
    let supportedLanguageCodes: [String]
    let maximumInputCharacters: Int
    let maximumOutputCharacters: Int
    let requiresAppleNeuralEngine: Bool

    init(_ manifest: LocalTransformModelManifest) {
        schemaVersion = manifest.schemaVersion
        modelVersion = manifest.modelVersion
        modelSHA256 = manifest.modelSHA256
        licenseIdentifier = manifest.licenseIdentifier
        modelByteCount = manifest.modelByteCount
        supportedLanguageCodes = manifest.supportedLanguageCodes
        maximumInputCharacters = manifest.maximumInputCharacters
        maximumOutputCharacters = manifest.maximumOutputCharacters
        requiresAppleNeuralEngine = manifest.requiresAppleNeuralEngine
    }
}

private extension JSONEncoder {
    static var transform: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
