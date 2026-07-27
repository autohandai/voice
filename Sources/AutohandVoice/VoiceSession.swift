import AppKit
import AutohandVoiceCore
import Foundation

@MainActor
final class VoiceSession {
    enum State: Equatable {
        case ready
        case recording
        case processing
        case failed(String)

        var label: String {
            switch self {
            case .ready: "Ready"
            case .recording: "Recording…"
            case .processing: "Processing locally…"
            case let .failed(message): message
            }
        }

        var symbol: String {
            switch self {
            case .ready: "waveform"
            case .recording: "waveform.circle.fill"
            case .processing: "ellipsis.circle"
            case .failed: "exclamationmark.triangle"
            }
        }
    }

    var onChange: (() -> Void)?
    private(set) var state: State = .ready { didSet { onChange?() } }
    private(set) var lastTranscript: String? { didSet { onChange?() } }
    private(set) var isEnabled = true { didSet { onChange?() } }
    private(set) var preferences: VoicePreferences

    private let store: PreferencesStore
    private let capture = AudioCapture()
    private let inserter = TextInserter()
    private var recognizer: LocalSpeechRecognizer

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let loaded = store.load()
        preferences = loaded
        recognizer = LocalSpeechRecognizer(modelVersion: loaded.modelVersion)
    }

    func setEnabled(_ value: Bool) {
        if !value, state == .recording {
            capture.cancel()
            state = .ready
        }
        isEnabled = value
    }

    func beginRecording() {
        guard isEnabled, state == .ready else { return }
        state = .recording
        if preferences.playSounds { NSSound.beep() }
        Task {
            do {
                try await capture.start()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func finishRecording() {
        guard state == .recording else { return }
        state = .processing
        Task {
            do {
                let samples = try capture.stop()
                let transcript = try await recognizer.transcribe(samples: samples)
                let finalText = try transcript.finalText()
                try inserter.commit(transcript, mode: preferences.outputMode)
                lastTranscript = finalText
                state = .ready
                if preferences.playSounds { NSSound.beep() }
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func recover() {
        guard case .failed = state else { return }
        state = .ready
    }

    func reportFailure(_ message: String) {
        state = .failed(message)
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    func setOutputMode(_ mode: OutputMode) {
        preferences.outputMode = mode
        persist()
    }

    func setPushToTalkKey(_ key: PushToTalkKey) {
        preferences.pushToTalkKey = key
        persist()
    }

    func setPlaySounds(_ value: Bool) {
        preferences.playSounds = value
        persist()
    }

    private func persist() {
        do {
            try store.save(preferences)
        } catch {
            state = .failed("Could not save settings: \(error.localizedDescription)")
        }
        onChange?()
    }
}
