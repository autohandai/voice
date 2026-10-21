import AppKit
import AVFoundation
import AutohandVoiceBonsaiMLX
import AutohandVoiceCore
import AutohandVoiceLLM
import Foundation
import ServiceManagement
import SwiftUI

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
      autohand-voice talk-local [--runtime mlx|llama] [--temperature <t>]
                                [--presence-penalty <p>] [--max-tokens <n>]
                                [--seed <n>] <question>
      autohand-voice talk-endpoint <audio-file> [--reply]
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
/// `talk-local` options. Anything that is not an option is the question.
private struct LocalTalkOptions {
    var runtime: LocalTalkRuntime?
    var temperature: Float?
    var presencePenalty: Float?
    var maxTokens = FantailChatRequest.spokenMaxTokens
    var seed: UInt64?
    var question = ""

    init(_ arguments: ArraySlice<String>) throws {
        var words: [String] = []
        var iterator = arguments.makeIterator()
        func value(for flag: String) throws -> String {
            guard let value = iterator.next() else {
                throw CommandError.invalidArguments("\(flag) needs a value")
            }
            return value
        }
        while let argument = iterator.next() {
            switch argument {
            case "--runtime":
                let name = try value(for: argument)
                guard let runtime = LocalTalkRuntime(argument: name) else {
                    throw CommandError.invalidArguments("--runtime must be mlx or llama")
                }
                self.runtime = runtime
            case "--temperature":
                guard let number = Float(try value(for: argument)), number >= 0 else {
                    throw CommandError.invalidArguments("--temperature must be a number >= 0")
                }
                temperature = number
            case "--presence-penalty":
                guard let number = Float(try value(for: argument)) else {
                    throw CommandError.invalidArguments("--presence-penalty must be a number")
                }
                presencePenalty = number
            case "--max-tokens":
                guard let number = Int(try value(for: argument)), (1...2_048).contains(number) else {
                    throw CommandError.invalidArguments("--max-tokens must be 1 to 2048")
                }
                maxTokens = number
            case "--seed":
                guard let number = UInt64(try value(for: argument)) else {
                    throw CommandError.invalidArguments("--seed must be a whole number")
                }
                seed = number
            default:
                words.append(argument)
            }
        }
        question = words.joined(separator: " ")
    }
}

private func runLocalTalk(_ arguments: ArraySlice<String>) async throws {
    let options = try LocalTalkOptions(arguments)
    guard !options.question.isEmpty else {
        printUsage()
        exit(EXIT_FAILURE)
    }
    let mlxCandidate = BonsaiMLXEngine()
    let runtime = LocalTalkRuntime.resolve(
        requested: options.runtime,
        mlxSupported: mlxCandidate.unavailableReason == nil,
        mlxInstalled: mlxCandidate.isInstalled
    )
    let messages = [
        TalkMessage(role: .system, content: FantailChatRequest.spokenSystemPrompt),
        TalkMessage(role: .user, content: options.question),
    ]
    let statistics = StatisticsBox()
    let engine: any OnDeviceTalkEngine
    let reply: () -> AsyncThrowingStream<String, Error>
    switch runtime {
    case .mlx:
        var sampling = BonsaiSamplingSettings()
        if let temperature = options.temperature { sampling.temperature = temperature }
        if let penalty = options.presencePenalty { sampling.presencePenalty = penalty }
        let mlx = BonsaiMLXEngine(sampling: sampling)
        engine = mlx
        reply = {
            mlx.reply(
                to: messages,
                maxTokens: options.maxTokens,
                seed: options.seed,
                onFinish: { statistics.set($0) }
            )
        }
    case .llamaCpp:
        var sampling = LlamaChatRuntime.Sampling()
        if let temperature = options.temperature { sampling.temperature = temperature }
        if let penalty = options.presencePenalty { sampling.presencePenalty = penalty }
        let llama = LocalTalkEngine(sampling: sampling)
        engine = llama
        reply = {
            llama.reply(
                to: messages,
                maxTokens: options.maxTokens,
                onFinish: { statistics.set($0) }
            )
        }
    }
    if let reason = engine.unavailableReason {
        throw CommandError.invalidArguments(reason)
    }
    fputs("Runtime: \(runtime.displayName) (\(engine.displayName))\n", stderr)
    let started = Date()
    if !engine.isInstalled {
        fputs("Downloading \(engine.displayName)…\n", stderr)
    }
    try await engine.prepare { progress in
        if progress < 1 {
            fputs(String(format: "\r%3.0f%%", progress * 100), stderr)
        }
    }
    let loaded = Date()
    fputs(
        String(format: "\nLoaded in %.2fs\n", loaded.timeIntervalSince(started)),
        stderr
    )
    for try await text in reply() {
        print(text, terminator: "")
        fflush(stdout)
    }
    print()
    fflush(stdout)
    if let stats = statistics.value {
        fputs(
            String(
                format: "%d prompt tokens in %.2fs (%.0f tok/s); %d tokens in %.2fs (%.1f tok/s)\n",
                stats.promptTokens,
                stats.prefillSeconds,
                stats.prefillTokensPerSecond,
                stats.generatedTokens,
                stats.decodeSeconds,
                stats.decodeTokensPerSecond
            ),
            stderr
        )
    }
}

private final class StatisticsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: LocalTalkGenerationStatistics?

    func set(_ value: LocalTalkGenerationStatistics) {
        lock.lock()
        stored = value
        lock.unlock()
    }

    var value: LocalTalkGenerationStatistics? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}

/// Replays an audio file through hands-free Talk's end-of-turn detector in
/// 50 ms windows, like the microphone tap, and prints where turns end. With
/// `--reply` (16 kHz files), each turn is transcribed locally and answered
/// by the on-device model, carrying the conversation, like a hands-free chat.
private func runTalkEndpoint(_ url: URL, reply: Bool) async throws {
    let file = try AVAudioFile(forReading: url)
    let format = file.processingFormat
    let window = AVAudioFrameCount(format.sampleRate / 20)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window)
    else { return }
    if reply, format.sampleRate != 16_000 {
        throw CommandError.invalidArguments("--reply needs a 16 kHz audio file")
    }
    let recognizer = LocalSpeechRecognizer(
        modelVersion: PreferencesStore().load().modelVersion
    )
    let talk = LocalTalkEngine()
    var conversation = TalkConversation()
    var turnSamples: [Float] = []
    var endpointer = TalkEndpointer()
    var time = 0.0
    var last = TalkEndpointer.Decision.waiting
    while file.framePosition < file.length {
        try file.read(into: buffer, frameCount: window)
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0
        else { break }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            sum += channel[index] * channel[index]
        }
        let rms = (sum / Float(buffer.frameLength)).squareRoot()
        if reply {
            turnSamples += UnsafeBufferPointer(
                start: channel,
                count: Int(buffer.frameLength)
            )
        }
        let decision = endpointer.observe(rms: rms, at: time)
        if decision != last {
            print(String(format: "%6.2fs %@", time, "\(decision)"))
            last = decision
        }
        if decision == .endOfTurn, reply {
            let question = try await recognizer.transcribe(samples: turnSamples)
                .finalText()
            print("  You: \(question)")
            conversation.appendUser(question)
            try await talk.prepare()
            var answer = ""
            for try await piece in talk.reply(
                to: conversation.requestMessages(
                    systemPrompt: FantailChatRequest.spokenSystemPrompt
                ),
                maxTokens: FantailChatRequest.spokenMaxTokens
            ) {
                answer += piece
            }
            conversation.appendAssistant(answer)
            print("  Model: \(answer)")
            turnSamples.removeAll()
        }
        if decision == .endOfTurn {
            // The app starts a new turn after sending; do the same here.
            endpointer = TalkEndpointer(noiseFloorDB: endpointer.noiseFloorDB)
            last = .waiting
        }
        time += Double(buffer.frameLength) / format.sampleRate
    }
    print(String(format: "%6.2fs end of file", time))
}

/// Asks Talk one question from the command line with the signed-in account
/// and tools, voice muted, printing each step. Anything that needs approval
/// is denied.
@MainActor
private func runTalkCheck(_ question: String, renderPath: String? = nil) async {
    let preferences = PreferencesStore().load()
    let speaker = TalkSpeaker()
    speaker.isMuted = true
    let talk = TalkController(speaker: speaker)
    talk.engine = { preferences.talkEngine }
    talk.toolbox = TalkAgentToolbox(
        workspaceURL: { preferences.talkWorkspaceURL },
        computerUseEnabled: { preferences.talkComputerUseEnabled }
    )
    var last = ""
    func report() {
        let line: String
        switch talk.phase {
        case let .thinking(question): line = "thinking: \(question)"
        case let .working(_, activity): line = "tool: \(activity)"
        case let .awaitingApproval(_, request):
            line = "approval needed (denied): \(request.summary)"
            // Deny after printing, outside this onChange callback.
            Task { @MainActor in talk.denyPendingTool() }
        case let .replying(_, reply, _): line = "reply: \(reply)"
        case let .failed(failure, _): line = "failed: \(failure.message)"
        case .needsSignIn: line = "needs sign-in"
        case .idle, .listening: line = ""
        }
        if !line.isEmpty, line != last {
            if line.hasPrefix("reply: "), last.hasPrefix("reply: ") {
                last = line
                return
            }
            print(line)
            last = line
        }
    }
    talk.onChange = { report() }
    talk.ask(question)
    let started = Date()
    while Date().timeIntervalSince(started) < 180 {
        report()
        if case .replying(_, _, false) = talk.phase, !talk.isWorking { break }
        if case .failed = talk.phase { break }
        if case .needsSignIn = talk.phase { break }
        try? await Task.sleep(for: .milliseconds(200))
    }
    if case let .replying(_, reply, _) = talk.phase { print("final: \(reply)") }
    if let renderPath {
        renderTalkCard(talk, to: URL(fileURLWithPath: renderPath))
    }
}

/// Draws the Talk card at its window size into a PNG, to check layout.
@MainActor
private func renderTalkCard(_ talk: TalkController, to url: URL) {
    let size = RecordingHUDPlacement.talkContentSize
    let view = NSHostingView(rootView: TalkCardView(talk: talk)
        .frame(width: size.width, height: size.height)
        .background(Color.gray))
    view.frame = NSRect(origin: .zero, size: size)
    let window = NSWindow(
        contentRect: view.frame,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    view.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    print("rendered: \(url.path)")
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
            case "talk-check":
                var words = Array(arguments.dropFirst())
                var renderPath: String?
                if let index = words.firstIndex(of: "--render"), index + 1 < words.count {
                    renderPath = words[index + 1]
                    words.removeSubrange(index...(index + 1))
                }
                let question = words.joined(separator: " ")
                guard !question.isEmpty else {
                    printUsage()
                    exit(EXIT_FAILURE)
                }
                await runTalkCheck(question, renderPath: renderPath)
            case "talk-local":
                try await runLocalTalk(arguments.dropFirst())
            case "talk-endpoint":
                guard let path = arguments.dropFirst().first else {
                    printUsage()
                    exit(EXIT_FAILURE)
                }
                try await runTalkEndpoint(
                    URL(fileURLWithPath: path),
                    reply: arguments.contains("--reply")
                )
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
                    let loginStatus: String
                    switch SMAppService.mainApp.status {
                    case .enabled: loginStatus = "enabled"
                    case .requiresApproval: loginStatus = "needs approval in System Settings"
                    case .notRegistered: loginStatus = "not registered"
                    case .notFound: loginStatus = "unavailable for this build"
                    @unknown default: loginStatus = "unknown"
                    }
                    print(
                        "Launch at login: \(loginStatus) (setting "
                            + (preferences.launchAtLogin ? "on" : "off") + ")"
                    )
                    print(
                        "Talk: "
                            + (TalkAvailability.onThisMac
                                ? (preferences.talkEnabled ? "on" : "off")
                                : "unavailable (needs Apple Silicon)")
                    )
                    print(
                        "Talk sign-in storage: "
                            + (CodeSignature.isAdHoc
                                ? "owner-only file (ad-hoc signed build)"
                                : "Keychain")
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
