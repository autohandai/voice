import Foundation

public struct AppProfile: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var bundleIdentifier: String
    public var outputMode: OutputMode?
    public var recordingMode: RecordingMode?
    public var modelVersion: String?
    public var dictationLanguageCode: String?
    public var dictationCommandsEnabled: Bool?
    public var smartFormattingEnabled: Bool?
    public var automaticTerminalPunctuation: Bool?
    public var showRecordingHUD: Bool?
    public var playSounds: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        outputMode: OutputMode? = nil,
        recordingMode: RecordingMode? = nil,
        modelVersion: String? = nil,
        dictationLanguageCode: String? = nil,
        dictationCommandsEnabled: Bool? = nil,
        smartFormattingEnabled: Bool? = nil,
        automaticTerminalPunctuation: Bool? = nil,
        showRecordingHUD: Bool? = nil,
        playSounds: Bool? = nil
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.outputMode = outputMode
        self.recordingMode = recordingMode
        self.modelVersion = modelVersion
        self.dictationLanguageCode = dictationLanguageCode
        self.dictationCommandsEnabled = dictationCommandsEnabled
        self.smartFormattingEnabled = smartFormattingEnabled
        self.automaticTerminalPunctuation = automaticTerminalPunctuation
        self.showRecordingHUD = showRecordingHUD
        self.playSounds = playSounds
    }

    public var isValid: Bool {
        !name.isEmpty
            && !bundleIdentifier.isEmpty
            && bundleIdentifier.contains(".")
            && name.count <= 100
            && bundleIdentifier.count <= 255
            && modelVersion.map {
                SpeechModelVariant(rawValue: $0) != nil
            } != false
            && dictationLanguageCode.map {
                SupportedDictationLanguage(rawValue: $0) != nil
            } != false
            && modelSupportsSelectedLanguage
    }

    private var modelSupportsSelectedLanguage: Bool {
        guard
            let modelVersion,
            let languageCode = dictationLanguageCode,
            let model = SpeechModelVariant(rawValue: modelVersion)
        else { return true }
        return model.supports(languageCode: languageCode)
    }
}

public struct ResolvedAppProfile: Equatable, Sendable {
    public let profileID: UUID?
    public let profileName: String?
    public let outputMode: OutputMode
    public let recordingMode: RecordingMode
    public let modelVersion: String
    public let dictationLanguageCode: String
    public let dictationCommandsEnabled: Bool
    public let smartFormattingEnabled: Bool
    public let automaticTerminalPunctuation: Bool
    public let showRecordingHUD: Bool
    public let playSounds: Bool
}

public enum AppProfileResolver {
    public static func resolve(
        preferences: VoicePreferences,
        profiles: [AppProfile],
        bundleIdentifier: String?
    ) -> ResolvedAppProfile {
        let profile = bundleIdentifier.flatMap { identifier in
            profiles.first { $0.bundleIdentifier == identifier }
        }
        let languageCode = profile?.dictationLanguageCode
            ?? preferences.dictationLanguageCode
        let requestedModel = SpeechModelVariant(
            rawValue: profile?.modelVersion ?? preferences.modelVersion
        ) ?? .default
        let resolvedModel = requestedModel.supports(
            languageCode: languageCode
        ) ? requestedModel : .v3
        return ResolvedAppProfile(
            profileID: profile?.id,
            profileName: profile?.name,
            outputMode: profile?.outputMode ?? preferences.outputMode,
            recordingMode: profile?.recordingMode ?? preferences.recordingMode,
            modelVersion: resolvedModel.rawValue,
            dictationLanguageCode: languageCode,
            dictationCommandsEnabled: profile?.dictationCommandsEnabled
                ?? preferences.dictationCommandsEnabled,
            smartFormattingEnabled: profile?.smartFormattingEnabled
                ?? preferences.smartFormattingEnabled,
            automaticTerminalPunctuation:
                profile?.automaticTerminalPunctuation
                ?? preferences.automaticTerminalPunctuation,
            showRecordingHUD: profile?.showRecordingHUD
                ?? preferences.showRecordingHUD,
            playSounds: profile?.playSounds ?? preferences.playSounds
        )
    }
}

public enum AppProfileError: LocalizedError, Equatable {
    case invalidProfile
    case duplicateBundleIdentifier
    case tooManyProfiles
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidProfile:
            "Each profile needs a name and a valid bundle identifier."
        case .duplicateBundleIdentifier:
            "Only one profile can match each bundle identifier."
        case .tooManyProfiles:
            "App profiles are limited to 100."
        case .fileTooLarge:
            "The app profile file must be smaller than 1 MB."
        }
    }
}

public struct AppProfileStore: Sendable {
    public static let maximumProfiles = 100
    public static let maximumFileBytes = 1_024 * 1_024
    public let url: URL

    public init(url: URL = Brand.appProfilesURL) {
        self.url = url
    }

    public static func validate(_ profiles: [AppProfile]) throws {
        guard profiles.count <= maximumProfiles else {
            throw AppProfileError.tooManyProfiles
        }
        guard profiles.allSatisfy(\.isValid) else {
            throw AppProfileError.invalidProfile
        }
        let identifiers = profiles.map(\.bundleIdentifier)
        guard Set(identifiers).count == identifiers.count else {
            throw AppProfileError.duplicateBundleIdentifier
        }
    }

    public func load() throws -> [AppProfile] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )
        let fileSize = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard fileSize <= Self.maximumFileBytes else {
            throw AppProfileError.fileTooLarge
        }
        let profiles = try JSONDecoder().decode(
            [AppProfile].self,
            from: Data(contentsOf: url)
        )
        try Self.validate(profiles)
        return profiles
    }

    public func save(_ profiles: [AppProfile]) throws {
        try Self.validate(profiles)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: directory.path
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
