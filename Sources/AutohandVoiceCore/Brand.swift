import Foundation

public enum Brand {
    public static let productName = "Autohand Voice"
    public static let commandName = "autohand-voice"
    public static let helperName = "autohand-voice-stt"
    public static let bundleIdentifier = "ai.autohand.voice"
    public static let environmentPrefix = "AUTOHAND_VOICE_"
    public static let version = "1.0.0"

    public static var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Autohand Voice", isDirectory: true)
    }

    public static var preferencesURL: URL {
        applicationSupportDirectory.appendingPathComponent("preferences.json")
    }
}
