import AVFoundation
import AutohandVoiceCore
import AutohandVoiceQwenASR
import Foundation

private struct Result: Codable {
    let text: String
    let duration_ms: Int
    // Reported for the optional Qwen3 engine only, so the default Parakeet
    // output keeps its existing shape.
    var engine: String?
    var load_ms: Int?
    var transcribe_ms: Int?
    var audio_ms: Int?
}

private struct Qwen3Status: Codable {
    let engine: String
    let supported: Bool
    let reason: String?
    let metallib: String?
    let downloaded: Bool
    let cache_directory: String
}

private enum Engine: String {
    case parakeet
    case qwen3
}

private struct Options {
    var engine: Engine = .parakeet
    var language = SupportedDictationLanguage.english.code
    var positional: [String] = []
}

private func emit<T: Encodable>(_ value: T) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(value) else { return }
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

private func fail(_ message: String) -> Never {
    fputs("autohand-voice-stt: \(message)\n", stderr)
    exit(EXIT_FAILURE)
}

private func parse(_ arguments: ArraySlice<String>) -> Options {
    var options = Options()
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
        switch argument {
        case "--engine":
            guard let raw = iterator.next(), let engine = Engine(rawValue: raw) else {
                fail("--engine expects parakeet or qwen3")
            }
            options.engine = engine
        case "--language":
            guard let code = iterator.next(), !code.isEmpty else {
                fail("--language expects a language code such as en")
            }
            options.language = code
        default:
            options.positional.append(argument)
        }
    }
    return options
}

private func milliseconds(_ duration: Duration) -> Int {
    let components = duration.components
    return Int(components.seconds) * 1_000
        + Int(components.attoseconds / 1_000_000_000_000_000)
}

private func audioMilliseconds(_ url: URL) -> Int? {
    guard let file = try? AVAudioFile(forReading: url) else { return nil }
    let rate = file.processingFormat.sampleRate
    guard rate > 0 else { return nil }
    return Int(Double(file.length) / rate * 1_000)
}

private func qwen3Status() -> Qwen3Status {
    let recognizer = Qwen3SpeechRecognizer()
    return Qwen3Status(
        engine: Engine.qwen3.rawValue,
        supported: Qwen3SpeechRecognizer.isSupportedOnThisMac,
        reason: Qwen3SpeechRecognizer.unsupportedReason,
        metallib: Qwen3SpeechRecognizer.isSupportedOnThisMac
            ? Qwen3Platform.locateMetalLibrary()?.path
            : nil,
        downloaded: recognizer.isDownloaded(),
        cache_directory: recognizer.cacheDirectory.path
    )
}

private func transcribeWithQwen3(_ file: URL, language: String) async throws -> Result {
    let recognizer = Qwen3SpeechRecognizer()
    let loadStarted = ContinuousClock.now
    try await recognizer.prepare { progress in
        if case .downloading = progress.phase {
            fputs(
                String(
                    format: "autohand-voice-stt: %@ %.0f%%\n",
                    progress.phase.label,
                    progress.fractionCompleted * 100
                ),
                stderr
            )
        }
    }
    let loaded = ContinuousClock.now
    let transcript = try await recognizer.transcribe(
        file: file,
        languageCode: language
    )
    let finished = ContinuousClock.now
    return Result(
        text: try transcript.finalText(),
        duration_ms: milliseconds(finished - loadStarted),
        engine: Engine.qwen3.rawValue,
        load_ms: milliseconds(loaded - loadStarted),
        transcribe_ms: milliseconds(finished - loaded),
        audio_ms: audioMilliseconds(file)
    )
}

@main
struct AutohandVoiceSTTCommand {
    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        guard let command = arguments.first else {
            fail("expected transcribe, serve, check, or engines")
        }
        let options = parse(arguments.dropFirst())
        switch command {
        case "check":
            let check = SystemCheck()
            emit(check)
            exit(check.supported ? EXIT_SUCCESS : EXIT_FAILURE)
        case "engines":
            emit([qwen3Status()])
        case "transcribe":
            guard let path = options.positional.first else {
                fail("transcribe requires an audio file path")
            }
            let file = URL(fileURLWithPath: path)
            if options.engine == .qwen3 {
                do {
                    emit(try await transcribeWithQwen3(file, language: options.language))
                } catch {
                    fail(error.localizedDescription)
                }
                return
            }
            let started = ContinuousClock.now
            do {
                let transcript = try await LocalSpeechRecognizer().transcribe(
                    file: file
                )
                let elapsed = ContinuousClock.now - started
                emit(
                    Result(
                        text: try transcript.finalText(),
                        duration_ms: Int(
                            Double(elapsed.components.seconds) * 1_000
                        )
                    )
                )
            } catch {
                fail(error.localizedDescription)
            }
        case "serve":
            if options.engine == .qwen3 {
                await serveQwen3(language: options.language)
                return
            }
            let recognizer = LocalSpeechRecognizer()
            do {
                try await recognizer.prepare()
                emit(["ready": true])
                while let line = readLine() {
                    guard
                        let data = line.data(using: .utf8),
                        let request = try? JSONDecoder().decode(
                            [String: String].self,
                            from: data
                        ),
                        let path = request["path"]
                    else {
                        emit(["error": "invalid request"])
                        continue
                    }
                    do {
                        let transcript = try await recognizer.transcribe(
                            file: URL(fileURLWithPath: path)
                        )
                        emit(["text": try transcript.finalText()])
                    } catch {
                        emit(["error": error.localizedDescription])
                    }
                }
            } catch {
                fail(error.localizedDescription)
            }
        default:
            fail("unknown command: \(command)")
        }
    }

    private static func serveQwen3(language: String) async {
        let recognizer = Qwen3SpeechRecognizer()
        do {
            try await recognizer.prepare()
        } catch {
            fail(error.localizedDescription)
        }
        emit(["ready": true])
        while let line = readLine() {
            guard
                let data = line.data(using: .utf8),
                let request = try? JSONDecoder().decode(
                    [String: String].self,
                    from: data
                ),
                let path = request["path"]
            else {
                emit(["error": "invalid request"])
                continue
            }
            do {
                let transcript = try await recognizer.transcribe(
                    file: URL(fileURLWithPath: path),
                    languageCode: request["language"] ?? language
                )
                emit(["text": try transcript.finalText()])
            } catch {
                emit(["error": error.localizedDescription])
            }
        }
    }
}
