import Foundation

public enum SpeechEngine: String, Codable, CaseIterable, Sendable {
    case coreML = "coreml"
}

public enum OutputMode: String, Codable, CaseIterable, Sendable {
    case type
    case clipboard
}

public enum PushToTalkKey: String, Codable, CaseIterable, Sendable {
    case controlOptionSpace = "control_option_space"

    public var displayName: String {
        "Control + Option + Space"
    }

    public var requiresInputMonitoring: Bool { false }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case Self.controlOptionSpace.rawValue, "right_option", "right_control":
            self = .controlOptionSpace
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown push-to-talk shortcut: \(rawValue)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct VoicePreferences: Codable, Equatable, Sendable {
    public var engine: SpeechEngine
    public var outputMode: OutputMode
    public var pushToTalkKey: PushToTalkKey
    public var playSounds: Bool
    public var launchAtLogin: Bool
    public var modelVersion: String
    public var hasCompletedOnboarding: Bool
    public var showRecordingHUD: Bool
    public var livePreviewEnabled: Bool
    public var recordingHUDTheme: RecordingHUDTheme
    public var talkEnabled: Bool
    public var audioInputDeviceUID: String?
    public var audioInputDevicePriority: [String]
    public var automaticAudioHandoffEnabled: Bool
    public var recordingHUDMode: RecordingHUDPresentationMode
    public var recordingHUDOpacity: Double
    public var recordingHUDPlacements: [RecordingHUDDisplayPreference]
    public var shortcut: RegisteredShortcut
    public var scratchpadShortcut: RegisteredShortcut
    public var inputBindings: [InputBinding]
    public var pointerMonitoringEnabled: Bool
    public var functionKeyLongPressEnabled: Bool
    public var recordingMode: RecordingMode
    public var historyEnabled: Bool
    public var historyRetentionDays: Int
    public var historyMaximumItems: Int
    public var dictationCommandsEnabled: Bool
    public var smartFormattingEnabled: Bool
    public var cleanupLevel: CleanupLevel
    public var defaultStyleID: UUID?
    public var minimalContextEnabled: Bool
    public var sensitiveAppDenylist: [String]
    public var automaticTerminalPunctuation: Bool
    public var dictationLanguageCode: String
    public var englishSpellingPolicy: EnglishSpellingPolicy
    public var canadianEnglishRecommendation:
        CanadianEnglishRecommendationResponse
    public var usageInsightsEnabled: Bool
    public var vocabularySuggestionsEnabled: Bool
    public var notificationPreferences: VoiceNotificationPreferences

    public init(
        engine: SpeechEngine = .coreML,
        outputMode: OutputMode = .type,
        pushToTalkKey: PushToTalkKey = .controlOptionSpace,
        playSounds: Bool = true,
        launchAtLogin: Bool = false,
        modelVersion: String = "v3",
        hasCompletedOnboarding: Bool = false,
        showRecordingHUD: Bool = true,
        livePreviewEnabled: Bool = false,
        recordingHUDTheme: RecordingHUDTheme = .flow,
        talkEnabled: Bool = true,
        audioInputDeviceUID: String? = nil,
        audioInputDevicePriority: [String] = [],
        automaticAudioHandoffEnabled: Bool = false,
        recordingHUDMode: RecordingHUDPresentationMode = .automatic,
        recordingHUDOpacity: Double = 0.8,
        recordingHUDPlacements: [RecordingHUDDisplayPreference] = [],
        shortcut: RegisteredShortcut = .controlOptionSpace,
        scratchpadShortcut: RegisteredShortcut = .optionS,
        inputBindings: [InputBinding]? = nil,
        pointerMonitoringEnabled: Bool = false,
        functionKeyLongPressEnabled: Bool = true,
        recordingMode: RecordingMode = .pressAndHold,
        historyEnabled: Bool = false,
        historyRetentionDays: Int = 30,
        historyMaximumItems: Int = 500,
        dictationCommandsEnabled: Bool = false,
        smartFormattingEnabled: Bool = false,
        cleanupLevel: CleanupLevel? = nil,
        defaultStyleID: UUID? = nil,
        minimalContextEnabled: Bool = false,
        sensitiveAppDenylist: [String] = [],
        automaticTerminalPunctuation: Bool = true,
        dictationLanguageCode: String = "en",
        englishSpellingPolicy: EnglishSpellingPolicy = .automatic,
        canadianEnglishRecommendation:
            CanadianEnglishRecommendationResponse = .notPresented,
        usageInsightsEnabled: Bool = false,
        vocabularySuggestionsEnabled: Bool = false,
        notificationPreferences: VoiceNotificationPreferences = .init()
    ) {
        self.engine = engine
        self.outputMode = outputMode
        self.pushToTalkKey = pushToTalkKey
        self.playSounds = playSounds
        self.launchAtLogin = launchAtLogin
        self.modelVersion = modelVersion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.showRecordingHUD = showRecordingHUD
        self.livePreviewEnabled = livePreviewEnabled
        self.recordingHUDTheme = recordingHUDTheme
        self.talkEnabled = talkEnabled
        self.audioInputDeviceUID = audioInputDeviceUID
        self.audioInputDevicePriority = AudioRoutePolicy.normalized(
            audioInputDevicePriority.isEmpty
                ? audioInputDeviceUID.map { [$0] } ?? []
                : audioInputDevicePriority
        )
        self.automaticAudioHandoffEnabled =
            automaticAudioHandoffEnabled
        let hudPreferences = RecordingHUDPreferences(
            mode: recordingHUDMode,
            opacity: recordingHUDOpacity,
            displays: recordingHUDPlacements
        )
        self.recordingHUDMode = hudPreferences.mode
        self.recordingHUDOpacity = hudPreferences.opacity
        self.recordingHUDPlacements = hudPreferences.displays
        self.shortcut = shortcut
        self.scratchpadShortcut = scratchpadShortcut
        self.inputBindings = (
            try? InputConfiguration(
                bindings: inputBindings ?? [
                    InputBinding(
                        action: .startStop,
                        trigger: .keyboard(shortcut)
                    ),
                ]
            ).bindings
        ) ?? [
            InputBinding(
                action: .startStop,
                trigger: .keyboard(shortcut)
            ),
        ]
        self.pointerMonitoringEnabled = pointerMonitoringEnabled
        self.functionKeyLongPressEnabled = functionKeyLongPressEnabled
        self.recordingMode = recordingMode
        self.historyEnabled = historyEnabled
        self.historyRetentionDays = min(max(historyRetentionDays, 1), 365)
        self.historyMaximumItems = min(max(historyMaximumItems, 1), 1_000)
        self.dictationCommandsEnabled = dictationCommandsEnabled
        let resolvedCleanupLevel = cleanupLevel
            ?? (smartFormattingEnabled ? .medium : .literal)
        self.cleanupLevel = resolvedCleanupLevel
        self.defaultStyleID = defaultStyleID
        self.smartFormattingEnabled = resolvedCleanupLevel != .literal
        self.minimalContextEnabled = minimalContextEnabled
        self.sensitiveAppDenylist = Self.normalizedDenylist(
            sensitiveAppDenylist
        )
        self.automaticTerminalPunctuation = automaticTerminalPunctuation
        self.dictationLanguageCode =
            SupportedDictationLanguage(rawValue: dictationLanguageCode) != nil
            ? dictationLanguageCode
            : "en"
        self.englishSpellingPolicy = englishSpellingPolicy
        self.canadianEnglishRecommendation =
            canadianEnglishRecommendation
        self.usageInsightsEnabled = usageInsightsEnabled
        self.vocabularySuggestionsEnabled =
            vocabularySuggestionsEnabled
        self.notificationPreferences = notificationPreferences
        if SpeechModelVariant(rawValue: self.modelVersion)?
            .supports(languageCode: self.dictationLanguageCode) == false {
            self.modelVersion = SpeechModelVariant.v3.rawValue
        }
    }

    public var allowsRemoteServices: Bool { false }

    public var primaryActivationMethod: VoiceActivationMethod {
        functionKeyLongPressEnabled
            ? .functionKeyLongPress
            : .keyboard(shortcut)
    }

    private enum CodingKeys: String, CodingKey {
        case engine
        case outputMode
        case pushToTalkKey
        case playSounds
        case launchAtLogin
        case modelVersion
        case hasCompletedOnboarding
        case showRecordingHUD
        case livePreviewEnabled
        case recordingHUDTheme
        case talkEnabled
        case audioInputDeviceUID
        case audioInputDevicePriority
        case automaticAudioHandoffEnabled
        case recordingHUDMode
        case recordingHUDOpacity
        case recordingHUDPlacements
        case shortcut
        case scratchpadShortcut
        case inputBindings
        case pointerMonitoringEnabled
        case functionKeyLongPressEnabled
        case recordingMode
        case historyEnabled
        case historyRetentionDays
        case historyMaximumItems
        case dictationCommandsEnabled
        case smartFormattingEnabled
        case cleanupLevel
        case defaultStyleID
        case minimalContextEnabled
        case sensitiveAppDenylist
        case automaticTerminalPunctuation
        case dictationLanguageCode
        case englishSpellingPolicy
        case canadianEnglishRecommendation
        case usageInsightsEnabled
        case vocabularySuggestionsEnabled
        case notificationPreferences
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decode(SpeechEngine.self, forKey: .engine)
        outputMode = try container.decode(OutputMode.self, forKey: .outputMode)
        pushToTalkKey = try container.decode(
            PushToTalkKey.self,
            forKey: .pushToTalkKey
        )
        playSounds = try container.decode(Bool.self, forKey: .playSounds)
        launchAtLogin = try container.decode(Bool.self, forKey: .launchAtLogin)
        modelVersion = try container.decode(String.self, forKey: .modelVersion)
        hasCompletedOnboarding = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasCompletedOnboarding
        ) ?? false
        showRecordingHUD = try container.decodeIfPresent(
            Bool.self,
            forKey: .showRecordingHUD
        ) ?? true
        livePreviewEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .livePreviewEnabled
        ) ?? false
        recordingHUDTheme = (try? container.decodeIfPresent(
            RecordingHUDTheme.self,
            forKey: .recordingHUDTheme
        )) ?? .flow
        talkEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .talkEnabled
        ) ?? true
        audioInputDeviceUID = try container.decodeIfPresent(
            String.self,
            forKey: .audioInputDeviceUID
        )
        let decodedAudioPriority = try container.decodeIfPresent(
            [String].self,
            forKey: .audioInputDevicePriority
        ) ?? []
        audioInputDevicePriority = AudioRoutePolicy.normalized(
            decodedAudioPriority.isEmpty
                ? audioInputDeviceUID.map { [$0] } ?? []
                : decodedAudioPriority
        )
        automaticAudioHandoffEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticAudioHandoffEnabled
        ) ?? false
        let decodedHUDPreferences = RecordingHUDPreferences(
            mode: try container.decodeIfPresent(
                RecordingHUDPresentationMode.self,
                forKey: .recordingHUDMode
            ) ?? .automatic,
            opacity: try container.decodeIfPresent(
                Double.self,
                forKey: .recordingHUDOpacity
            ) ?? 0.8,
            displays: try container.decodeIfPresent(
                [RecordingHUDDisplayPreference].self,
                forKey: .recordingHUDPlacements
            ) ?? []
        )
        recordingHUDMode = decodedHUDPreferences.mode
        recordingHUDOpacity = decodedHUDPreferences.opacity
        recordingHUDPlacements = decodedHUDPreferences.displays
        shortcut = try container.decodeIfPresent(
            RegisteredShortcut.self,
            forKey: .shortcut
        ) ?? .controlOptionSpace
        scratchpadShortcut = try container.decodeIfPresent(
            RegisteredShortcut.self,
            forKey: .scratchpadShortcut
        ) ?? .optionS
        let decodedBindings = try container.decodeIfPresent(
            [InputBinding].self,
            forKey: .inputBindings
        )
        inputBindings = (
            try? InputConfiguration(
                bindings: decodedBindings ?? [
                    InputBinding(
                        action: .startStop,
                        trigger: .keyboard(shortcut)
                    ),
                ]
            ).bindings
        ) ?? [
            InputBinding(
                action: .startStop,
                trigger: .keyboard(shortcut)
            ),
        ]
        pointerMonitoringEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .pointerMonitoringEnabled
        ) ?? false
        functionKeyLongPressEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .functionKeyLongPressEnabled
        ) ?? true
        recordingMode = try container.decodeIfPresent(
            RecordingMode.self,
            forKey: .recordingMode
        ) ?? .pressAndHold
        historyEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .historyEnabled
        ) ?? false
        historyRetentionDays = min(
            max(
                1,
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .historyRetentionDays
                ) ?? 30
            ),
            365
        )
        historyMaximumItems = min(
            max(
                1,
                try container.decodeIfPresent(
                    Int.self,
                    forKey: .historyMaximumItems
                ) ?? 500
            ),
            1_000
        )
        dictationCommandsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .dictationCommandsEnabled
        ) ?? false
        let legacySmartFormattingEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .smartFormattingEnabled
        ) ?? false
        cleanupLevel = try container.decodeIfPresent(
            CleanupLevel.self,
            forKey: .cleanupLevel
        ) ?? (legacySmartFormattingEnabled ? .medium : .literal)
        defaultStyleID = try container.decodeIfPresent(
            UUID.self,
            forKey: .defaultStyleID
        )
        smartFormattingEnabled = cleanupLevel != .literal
        minimalContextEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .minimalContextEnabled
        ) ?? false
        sensitiveAppDenylist = Self.normalizedDenylist(
            try container.decodeIfPresent(
                [String].self,
                forKey: .sensitiveAppDenylist
            ) ?? []
        )
        automaticTerminalPunctuation = try container.decodeIfPresent(
            Bool.self,
            forKey: .automaticTerminalPunctuation
        ) ?? true
        let decodedLanguage = try container.decodeIfPresent(
            String.self,
            forKey: .dictationLanguageCode
        ) ?? "en"
        dictationLanguageCode =
            SupportedDictationLanguage(rawValue: decodedLanguage) != nil
            ? decodedLanguage
            : "en"
        englishSpellingPolicy = try container.decodeIfPresent(
            EnglishSpellingPolicy.self,
            forKey: .englishSpellingPolicy
        ) ?? .automatic
        canadianEnglishRecommendation = try container.decodeIfPresent(
            CanadianEnglishRecommendationResponse.self,
            forKey: .canadianEnglishRecommendation
        ) ?? .notPresented
        usageInsightsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .usageInsightsEnabled
        ) ?? false
        vocabularySuggestionsEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .vocabularySuggestionsEnabled
        ) ?? false
        notificationPreferences = try container.decodeIfPresent(
            VoiceNotificationPreferences.self,
            forKey: .notificationPreferences
        ) ?? .init()
        if SpeechModelVariant(rawValue: modelVersion)?
            .supports(languageCode: dictationLanguageCode) == false {
            modelVersion = SpeechModelVariant.v3.rawValue
        }
    }

    private static func normalizedDenylist(
        _ bundleIdentifiers: [String]
    ) -> [String] {
        var seen = Set<String>()
        return bundleIdentifiers.compactMap { value in
            let candidate = value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            guard
                !candidate.isEmpty,
                candidate.contains("."),
                seen.insert(candidate).inserted
            else { return nil }
            return String(candidate.prefix(255))
        }
        .prefix(128)
        .map { $0 }
    }
}

public struct PreferencesStore: Sendable {
    public let url: URL

    public init(url: URL = Brand.preferencesURL) {
        self.url = url
    }

    public func load() -> VoicePreferences {
        guard
            let data = try? Data(contentsOf: url),
            let value = try? JSONDecoder().decode(VoicePreferences.self, from: data)
        else {
            return VoicePreferences()
        }
        return value
    }

    public func save(_ preferences: VoicePreferences) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let data = try JSONEncoder.pretty.encode(preferences)
        try data.write(to: url, options: [.atomic])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
