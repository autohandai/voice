import AutohandVoiceCore
import Foundation

private struct Result: Codable {
    let text: String
    let duration_ms: Int
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

@main
struct AutohandVoiceSTTCommand {
    static func main() async {
        let arguments = CommandLine.arguments.dropFirst()
        guard let command = arguments.first else {
            fail("expected transcribe, serve, or check")
        }
        switch command {
        case "check":
            let check = SystemCheck()
            emit(check)
            exit(check.supported ? EXIT_SUCCESS : EXIT_FAILURE)
        case "transcribe":
            guard let path = arguments.dropFirst().first else {
                fail("transcribe requires an audio file path")
            }
            let started = ContinuousClock.now
            do {
                let transcript = try await LocalSpeechRecognizer().transcribe(
                    file: URL(fileURLWithPath: path)
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
}
