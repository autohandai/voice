import Foundation

public enum SpeechEngine: String, Codable, CaseIterable, Sendable {
    case coreML = "coreml"
}

public enum OutputMode: String, Codable, CaseIterable, Sendable {
    case type
    case clipboard
}

public enum PushToTalkKey: String, Codable, CaseIterable, Sendable {
    case rightOption = "right_option"
    case rightControl = "right_control"

    public var displayName: String {
        switch self {
        case .rightOption: "Right Option"
        case .rightControl: "Right Control"
        }
    }

    public var keyCode: UInt16 {
        switch self {
        case .rightOption: 61
        case .rightControl: 62
        }
    }
}

public struct VoicePreferences: Codable, Equatable, Sendable {
    public var engine: SpeechEngine
    public var outputMode: OutputMode
    public var pushToTalkKey: PushToTalkKey
    public var playSounds: Bool
    public var launchAtLogin: Bool
    public var modelVersion: String

    public init(
        engine: SpeechEngine = .coreML,
        outputMode: OutputMode = .type,
        pushToTalkKey: PushToTalkKey = .rightOption,
        playSounds: Bool = true,
        launchAtLogin: Bool = false,
        modelVersion: String = "v3"
    ) {
        self.engine = engine
        self.outputMode = outputMode
        self.pushToTalkKey = pushToTalkKey
        self.playSounds = playSounds
        self.launchAtLogin = launchAtLogin
        self.modelVersion = modelVersion
    }

    public var allowsRemoteServices: Bool { false }
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
