import AppKit
import AutohandVoiceCore
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
    Autohand Voice — private, native voice input for Apple Silicon

    Usage:
      autohand-voice run
      autohand-voice transcribe <audio-file>
      autohand-voice check [--json]
      autohand-voice config [show|path|reset|set <key> <value>]
      autohand-voice --version

    Run without a command to open the menu bar app. Hold Control + Option + Space to speak.
    Speech recognition stays on-device; no remote fallback is available.
    """)
}

private func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
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
        case "sounds":
            guard ["on", "off"].contains(raw) else {
                throw CommandError.invalidArguments(
                    "sounds must be on or off"
                )
            }
            value.playSounds = raw == "on"
        default:
            throw CommandError.invalidArguments("unknown preference: \(key)")
        }
        try store.save(value)
        print("Updated \(key).")
    default:
        throw CommandError.invalidArguments("unknown config action: \(action)")
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
                let recognizer = LocalSpeechRecognizer()
                let transcript = try await recognizer.transcribe(
                    file: URL(fileURLWithPath: path)
                )
                try printJSON(["text": try transcript.finalText()])
            case "check", "doctor":
                let check = SystemCheck()
                if arguments.contains("--json") {
                    try printJSON(
                        DiagnosticReport(
                            check: check,
                            preferences: PreferencesStore().load()
                        )
                    )
                } else {
                    print("Platform: \(check.supported ? "supported" : "unsupported")")
                    print("Architecture: \(check.architecture)")
                    print("macOS: \(check.macOSVersion)")
                    print("Microphone: \(check.microphonePermission)")
                    print("Accessibility: \(check.accessibilityPermission ? "authorized" : "not authorized")")
                    print("Remote fallback: disabled")
                }
                if !check.supported { exit(EXIT_FAILURE) }
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
