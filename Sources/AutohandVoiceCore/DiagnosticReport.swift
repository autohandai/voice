import Foundation

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let product: String
    public let version: String
    public let supported: Bool
    public let architecture: String
    public let macOSVersion: String
    public let microphonePermission: String
    public let accessibilityPermission: Bool
    public let shortcut: String
    public let speechEngine: String
    public let modelVersion: String
    public let dictationLanguageCode: String
    public let remoteFallbackEnabled: Bool

    public init(
        check: SystemCheck,
        preferences: VoicePreferences
    ) {
        product = Brand.productName
        version = Brand.version
        supported = check.supported
        architecture = check.architecture
        macOSVersion = check.macOSVersion
        microphonePermission = check.microphonePermission
        accessibilityPermission = check.accessibilityPermission
        shortcut = preferences.shortcut.accessibilityName
        speechEngine = preferences.engine.rawValue
        modelVersion = preferences.modelVersion
        dictationLanguageCode = preferences.dictationLanguageCode
        remoteFallbackEnabled = check.remoteFallbackEnabled
    }

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
