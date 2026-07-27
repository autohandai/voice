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
    public var audioInputDeviceUID: String?
    public var shortcut: RegisteredShortcut
    public var recordingMode: RecordingMode

    public init(
        engine: SpeechEngine = .coreML,
        outputMode: OutputMode = .type,
        pushToTalkKey: PushToTalkKey = .controlOptionSpace,
        playSounds: Bool = true,
        launchAtLogin: Bool = false,
        modelVersion: String = "v3",
        hasCompletedOnboarding: Bool = false,
        showRecordingHUD: Bool = true,
        audioInputDeviceUID: String? = nil,
        shortcut: RegisteredShortcut = .controlOptionSpace,
        recordingMode: RecordingMode = .pressAndHold
    ) {
        self.engine = engine
        self.outputMode = outputMode
        self.pushToTalkKey = pushToTalkKey
        self.playSounds = playSounds
        self.launchAtLogin = launchAtLogin
        self.modelVersion = modelVersion
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.showRecordingHUD = showRecordingHUD
        self.audioInputDeviceUID = audioInputDeviceUID
        self.shortcut = shortcut
        self.recordingMode = recordingMode
    }

    public var allowsRemoteServices: Bool { false }

    private enum CodingKeys: String, CodingKey {
        case engine
        case outputMode
        case pushToTalkKey
        case playSounds
        case launchAtLogin
        case modelVersion
        case hasCompletedOnboarding
        case showRecordingHUD
        case audioInputDeviceUID
        case shortcut
        case recordingMode
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
        audioInputDeviceUID = try container.decodeIfPresent(
            String.self,
            forKey: .audioInputDeviceUID
        )
        shortcut = try container.decodeIfPresent(
            RegisteredShortcut.self,
            forKey: .shortcut
        ) ?? .controlOptionSpace
        recordingMode = try container.decodeIfPresent(
            RecordingMode.self,
            forKey: .recordingMode
        ) ?? .pressAndHold
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
