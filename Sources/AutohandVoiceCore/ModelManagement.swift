import FluidAudio
import Foundation

/// The finite Parakeet v3 language set documented by pinned FluidAudio 0.14.4.
public enum SupportedDictationLanguage: String, CaseIterable, Codable, Sendable {
    case bulgarian = "bg"
    case croatian = "hr"
    case czech = "cs"
    case danish = "da"
    case dutch = "nl"
    case english = "en"
    case estonian = "et"
    case finnish = "fi"
    case french = "fr"
    case german = "de"
    case greek = "el"
    case hungarian = "hu"
    case italian = "it"
    case latvian = "lv"
    case lithuanian = "lt"
    case maltese = "mt"
    case polish = "pl"
    case portuguese = "pt"
    case romanian = "ro"
    case russian = "ru"
    case slovak = "sk"
    case slovenian = "sl"
    case spanish = "es"
    case swedish = "sv"
    case ukrainian = "uk"

    public var code: String { rawValue }

    public static var displayOrder: [Self] {
        [.english] + allCases
            .filter { $0 != .english }
            .sorted {
                $0.displayName.localizedStandardCompare($1.displayName)
                    == .orderedAscending
            }
    }

    public var displayName: String {
        Locale.current.localizedString(
            forLanguageCode: rawValue
        ) ?? rawValue
    }

    public var testPhrase: String {
        switch self {
        case .bulgarian: "Здравейте, това е тест."
        case .croatian: "Pozdrav, ovo je test."
        case .czech: "Dobrý den, toto je test."
        case .danish: "Hej, dette er en test."
        case .dutch: "Hallo, dit is een test."
        case .english: "Hello, this is a test."
        case .estonian: "Tere, see on test."
        case .finnish: "Hei, tämä on testi."
        case .french: "Bonjour, ceci est un test."
        case .german: "Hallo, dies ist ein Test."
        case .greek: "Γεια σας, αυτή είναι μια δοκιμή."
        case .hungarian: "Helló, ez egy teszt."
        case .italian: "Ciao, questo è un test."
        case .latvian: "Sveiki, šis ir tests."
        case .lithuanian: "Sveiki, tai yra testas."
        case .maltese: "Bonġu, dan huwa test."
        case .polish: "Dzień dobry, to jest test."
        case .portuguese: "Olá, isto é um teste."
        case .romanian: "Bună, acesta este un test."
        case .russian: "Здравствуйте, это тест."
        case .slovak: "Dobrý deň, toto je test."
        case .slovenian: "Pozdravljeni, to je preizkus."
        case .spanish: "Hola, esto es una prueba."
        case .swedish: "Hej, det här är ett test."
        case .ukrainian: "Вітаю, це тест."
        }
    }
}

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

    public var supportedLanguages: [SupportedDictationLanguage] {
        switch self {
        case .v2: [.english]
        case .v3: SupportedDictationLanguage.displayOrder
        }
    }

    public func supports(languageCode: String) -> Bool {
        supportedLanguages.contains { $0.code == languageCode }
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

public enum ModelCacheError: LocalizedError, Equatable {
    case unsafeTarget

    public var errorDescription: String? {
        "Only a known Autohand Voice model cache can be removed."
    }
}

public enum ModelCacheManager {
    public static func remove(_ variant: SpeechModelVariant) throws {
        try removeCache(
            at: variant.cacheDirectory,
            allowedDirectories: SpeechModelVariant.allCases.map(
                \.cacheDirectory
            )
        )
    }

    static func removeCache(
        at directory: URL,
        allowedDirectories: [URL]
    ) throws {
        let target = directory.standardizedFileURL
        let allowed = Set(allowedDirectories.map(\.standardizedFileURL))
        guard allowed.contains(target) else {
            throw ModelCacheError.unsafeTarget
        }
        guard FileManager.default.fileExists(atPath: target.path) else {
            return
        }
        try FileManager.default.removeItem(at: target)
    }
}
