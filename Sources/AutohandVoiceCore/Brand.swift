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

    public static var historyURL: URL {
        applicationSupportDirectory.appendingPathComponent("history.json")
    }

    public static var vocabularyURL: URL {
        applicationSupportDirectory.appendingPathComponent("vocabulary.json")
    }

    public static var appProfilesURL: URL {
        applicationSupportDirectory.appendingPathComponent("app-profiles.json")
    }

    public static var usageInsightsURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "usage-insights.json"
        )
    }

    public static var operationalIssuesURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "operational-issues.json"
        )
    }
}
