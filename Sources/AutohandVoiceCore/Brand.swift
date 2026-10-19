import Foundation

public enum Brand {
    public static let productName = "Autohand Voice"
    public static let commandName = "autohand-voice"
    public static let helperName = "autohand-voice-stt"
    public static let bundleIdentifier = "ai.autohand.voice"
    public static let environmentPrefix = "AUTOHAND_VOICE_"
    public static let version = "0.1.0"
    public static let websiteURL = URL(string: "https://autohand.ai/")!
    public static let companyURL = URL(
        string: "https://autohand.ai/company"
    )!
    public static let brandURL = URL(
        string: "https://autohand.ai/company/brand"
    )!
    public static let privacyPolicyURL = URL(
        string: "https://autohand.ai/privacy-policy"
    )!
    public static let repositoryURL = URL(
        string: "https://github.com/autohandai/voice"
    )!

    public static var applicationSupportDirectory: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Autohand Voice", isDirectory: true)
    }

    /// Optional on-device models (the Talk model); never backed up.
    public static var localModelsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(
            "Models",
            isDirectory: true
        )
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

    public static var vocabularySuggestionsURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "vocabulary-suggestions.json"
        )
    }

    public static var appProfilesURL: URL {
        applicationSupportDirectory.appendingPathComponent("app-profiles.json")
    }

    public static var dictationStylesURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "dictation-styles.json"
        )
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

    public static var reliabilityLedgerURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "reliability-ledger.json"
        )
    }

    public static var recoveryDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(
            "Recovery",
            isDirectory: true
        )
    }

    public static var workspaceURL: URL {
        applicationSupportDirectory.appendingPathComponent("workspace-v2.sqlite")
    }

    public static var scratchpadAssetsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent(
            "Scratchpad Assets",
            isDirectory: true
        )
    }

    public static var transformTemplatesURL: URL {
        applicationSupportDirectory.appendingPathComponent(
            "transform-templates.json"
        )
    }

    /// Every owner-only user-data location currently owned by this repository.
    ///
    /// SQLite sidecars are listed explicitly so reset verification does not
    /// mistake an open WAL or shared-memory file for erased workspace data.
    public static var ownerOnlyDataURLs: [URL] {
        [
            preferencesURL,
            historyURL,
            vocabularyURL,
            vocabularySuggestionsURL,
            appProfilesURL,
            dictationStylesURL,
            usageInsightsURL,
            operationalIssuesURL,
            reliabilityLedgerURL,
            recoveryDirectory,
            workspaceURL,
            URL(fileURLWithPath: workspaceURL.path + "-wal"),
            URL(fileURLWithPath: workspaceURL.path + "-shm"),
            URL(fileURLWithPath: workspaceURL.path + "-journal"),
            scratchpadAssetsDirectory,
            transformTemplatesURL,
        ]
    }
}
