import AppKit
import AutohandVoiceCore
import AutohandVoiceLLM
import Foundation

private enum CommandError: LocalizedError {
    case invalidArguments(String)

    var errorDescription: String? {
        switch self {
        case let .invalidArguments(message): message
        }
    }
}

private func printUsage() {
    print("""
    Autohand Voice — private, native voice input for Mac

    Usage:
      autohand-voice run
      autohand-voice transcribe <audio-file>
      autohand-voice talk-local <question>
      autohand-voice check [--json]
      autohand-voice model-check [--json]
      autohand-voice reliability [show|path|reset|export <file>] [--json]
      autohand-voice config [show|path|reset|set <key> <value>]
      autohand-voice --version

    Run without a command to open the menu bar app.
    The default activation is long-press Fn.
    Control + Option + Space remains the fallback shortcut.
    Speech recognition stays on-device; no remote fallback is available.
    """)
}

private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
}

private func runConfig(_ arguments: ArraySlice<String>) throws {
    let store = PreferencesStore()
    let action = arguments.first ?? "show"
    switch action {
    case "path":
        print(store.url.path)
    case "reset":
        try store.save(VoicePreferences())
        print("Preferences reset.")
    case "show":
        try printJSON(store.load())
    case "set":
        guard arguments.count >= 3 else {
            throw CommandError.invalidArguments(
                "config set requires a key and value"
            )
        }
        var value = store.load()
        let key = arguments[arguments.index(after: arguments.startIndex)]
        let raw = arguments[arguments.index(arguments.startIndex, offsetBy: 2)]
        switch key {
        case "output":
            guard let mode = OutputMode(rawValue: raw) else {
                throw CommandError.invalidArguments(
                    "output must be type or clipboard"
                )
            }
            value.outputMode = mode
        case "ptt_key":
            guard let hotKey = PushToTalkKey(rawValue: raw) else {
                throw CommandError.invalidArguments(
                    "ptt_key must be control_option_space"
                )
            }
            value.pushToTalkKey = hotKey
            value.shortcut = .controlOptionSpace
        case "recording_mode":
            guard let mode = RecordingMode(rawValue: raw) else {
                throw CommandError.invalidArguments(
                    "recording_mode must be press_and_hold, toggle, or hands_free"
                )
            }
            value.recordingMode = mode
        case "function_key_long_press":
            guard ["on", "off"].contains(raw) else {
                throw CommandError.invalidArguments(
                    "function_key_long_press must be on or off"
                )
            }
            value.functionKeyLongPressEnabled = raw == "on"
        case "model":
            guard let variant = SpeechModelVariant(rawValue: raw) else {
                throw CommandError.invalidArguments("model must be v2 or v3")
            }
            value.modelVersion = variant.rawValue
            if !variant.supports(
                languageCode: value.dictationLanguageCode
            ) {
                value.dictationLanguageCode = "en"
            }
        case "language":
            guard let language = SupportedDictationLanguage(rawValue: raw) else {
                throw CommandError.invalidArguments(
                    "language must be one of: "
                        + SupportedDictationLanguage.allCases
                            .map(\.code)
                            .joined(separator: ", ")
                )
            }
            value.dictationLanguageCode = language.code
            let variant = SpeechModelVariant(
                rawValue: value.modelVersion
            ) ?? .default
            if !variant.supports(languageCode: language.code) {
                value.modelVersion = SpeechModelVariant.v3.rawValue
            }
        case "sounds":
            guard ["on", "off"].contains(raw) else {
                throw CommandError.invalidArguments(
                    "sounds must be on or off"
                )
            }
            value.playSounds = raw == "on"
        case "live_preview":
            guard ["on", "off"].contains(raw) else {
                throw CommandError.invalidArguments(
                    "live_preview must be on or off"
                )
            }
            value.livePreviewEnabled = raw == "on"
            if value.livePreviewEnabled {
                value.showRecordingHUD = true
            }
        default:
            throw CommandError.invalidArguments("unknown preference: \(key)")
        }
        try store.save(value)
        print("Updated \(key).")
    default:
        throw CommandError.invalidArguments("unknown config action: \(action)")
    }
}

private func runReliability(
    _ arguments: ArraySlice<String>
) async throws {
    let ledger = ReliabilityLedger()
    let action = arguments.first ?? "show"

    switch action {
    case "show", "--json":
        let now = Date()
        let snapshot = try await ledger.snapshot(
            DateInterval(
                start: now.addingTimeInterval(
                    -ReliabilityLedger.maximumAge
                ),
                end: now
            ),
            now: now
        )
        if action == "--json" || arguments.contains("--json") {
            try printJSON(snapshot)
        } else {
            print("Reliability rows: \(snapshot.rows.count)")
            for category in ReliabilityEventCategory.allCases {
                let success = snapshot.count(
                    category: category,
                    outcome: .success
                )
                let failure = snapshot.count(
                    category: category,
                    outcome: .failure
                )
                let interrupted = snapshot.count(
                    category: category,
                    outcome: .interrupted
                )
                guard success + failure + interrupted > 0 else {
                    continue
                }
                print(
                    "\(category.rawValue): "
                        + "\(success) success, "
                        + "\(failure) failure, "
                        + "\(interrupted) interrupted"
                )
            }
        }
    case "path":
        guard arguments.count == 1 else {
            throw CommandError.invalidArguments(
                "reliability path does not accept additional arguments"
            )
        }
        print(await ledger.url.path)
    case "reset":
        guard arguments.count == 1 else {
            throw CommandError.invalidArguments(
                "reliability reset does not accept additional arguments"
            )
        }
        try await ledger.reset()
        print("Reliability aggregates reset.")
    case "export":
        guard arguments.count == 2, let path = arguments.dropFirst().first else {
            throw CommandError.invalidArguments(
                "reliability export requires an output file"
            )
        }
        let data = try await ledger.exportRedacted()
        let outputURL = URL(fileURLWithPath: path)
        try data.write(to: outputURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
        print("Redacted reliability report exported.")
    default:
        throw CommandError.invalidArguments(
            "unknown reliability action: \(action)"
        )
    }
}

@MainActor
private func runMenuBar() -> Never {
    let application = NSApplication.shared
    let delegate = MenuBarController()
    application.delegate = delegate
    withExtendedLifetime(delegate) {
        application.run()
    }
    exit(EXIT_SUCCESS)
}

@MainActor
private func runHotKeyCheck() -> Never {
    let application = NSApplication.shared
    let delegate = HotKeyCheckDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.prohibited)
    withExtendedLifetime(delegate) {
        application.finishLaunching()
        application.run()
    }
    exit(EXIT_SUCCESS)
}

/// Asks the on-device Talk model one question and prints the reply as it
/// streams, with load and generation timings on stderr.
private func runLocalTalk(_ question: String) async throws {
    let engine = LocalTalkEngine()
    let started = Date()
    if !engine.isInstalled {
        fputs("Downloading \(engine.manifest.displayName)…\n", stderr)
    }
    try await engine.prepare { progress in
        if progress < 1 {
            fputs(String(format: "\r%3.0f%%", progress * 100), stderr)
        }
    }
    let loaded = Date()
    fputs(
        String(format: "\nLoaded in %.1fs\n", loaded.timeIntervalSince(started)),
        stderr
    )
    var pieces = 0
    for try await text in engine.reply(
        to: [
            TalkMessage(role: .system, content: FantailChatRequest.spokenSystemPrompt),
            TalkMessage(role: .user, content: question),
        ],
        maxTokens: FantailChatRequest.spokenMaxTokens
    ) {
        print(text, terminator: "")
        fflush(stdout)
        pieces += 1
    }
    print()
    fputs(
        String(
            format: "%d pieces in %.1fs\n",
            pieces,
            Date().timeIntervalSince(loaded)
        ),
        stderr
    )
}

@main
struct AutohandVoiceCommand {
    static func main() async {
        do {
            let arguments = CommandLine.arguments.dropFirst()
            let command = arguments.first ?? "run"
            switch command {
            case "run":
                runMenuBar()
            case "hotkey-check":
                runHotKeyCheck()
            case "transcribe":
                guard arguments.count == 2, let path = arguments.dropFirst().first else {
                    printUsage()
                    exit(EXIT_FAILURE)
                }
                let preferences = PreferencesStore().load()
                let recognizer = LocalSpeechRecognizer(
                    modelVersion: preferences.modelVersion
                )
                let transcript = try await recognizer.transcribe(
                    file: URL(fileURLWithPath: path),
                    languageCode: preferences.dictationLanguageCode
                )
                try printJSON(["text": try transcript.finalText()])
            case "talk-local":
                let question = arguments.dropFirst().joined(separator: " ")
                guard !question.isEmpty else {
                    printUsage()
                    exit(EXIT_FAILURE)
                }
                try await runLocalTalk(question)
            case "check", "doctor":
                let check = SystemCheck()
                let preferences = PreferencesStore().load()
                let issues =
                    (try? OperationalIssueStore().load()) ?? []
                let diagnostics = DiagnosticSnapshot(
                    check: check,
                    preferences: preferences,
                    runtime: .commandLine(
                        preferences: preferences,
                        issues: issues
                    )
                )
                if arguments.contains("--json") {
                    try printJSON(diagnostics.report)
                } else {
                    for item in diagnostics.checks {
                        print("\(item.title): \(item.value)")
                    }
                    print(
                        "Recent operational issue categories: "
                            + "\(issues.count)"
                    )
                }
                if !check.supported { exit(EXIT_FAILURE) }
            case "model-check":
                let preferences = PreferencesStore().load()
                let variant = SpeechModelVariant(
                    rawValue: preferences.modelVersion
                ) ?? .default
                let recognizer = LocalSpeechRecognizer(
                    modelVersion: variant.rawValue
                )
                let isValid = try await recognizer.validate()
                let storageBytes = try await recognizer.storageBytes()
                if arguments.contains("--json") {
                    try printJSON([
                        "languageCoverage": variant.languageCoverage,
                        "selectedLanguage": preferences.dictationLanguageCode,
                        "model": variant.rawValue,
                        "storageBytes": String(storageBytes),
                        "valid": String(isValid),
                    ])
                } else {
                    print("Model: \(variant.displayName)")
                    print("Languages: \(variant.languageCoverage)")
                    print("Storage: \(storageBytes) bytes")
                    print("Valid: \(isValid)")
                }
                if !isValid { exit(EXIT_FAILURE) }
            case "reliability":
                try await runReliability(arguments.dropFirst())
            case "config":
                try runConfig(arguments.dropFirst())
            case "--version", "version":
                print("\(Brand.productName) \(Brand.version)")
            case "--help", "-h", "help":
                printUsage()
            default:
                printUsage()
                exit(EXIT_FAILURE)
            }
        } catch {
            fputs("autohand-voice: \(error.localizedDescription)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
