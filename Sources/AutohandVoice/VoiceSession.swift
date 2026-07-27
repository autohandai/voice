import AppKit
import AutohandVoiceCore
import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class VoiceSession {
    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "dictation"
    )

    enum State: Equatable {
        case ready
        case starting
        case recording
        case processing
        case failed(String)

        var label: String {
            switch self {
            case .ready: "Ready"
            case .starting: "Starting microphone…"
            case .recording: "Recording…"
            case .processing: "Processing locally…"
            case let .failed(message): message
            }
        }

        var symbol: String {
            switch self {
            case .ready: "waveform"
            case .starting: "mic.badge.plus"
            case .recording: "waveform.circle.fill"
            case .processing: "ellipsis.circle"
            case .failed: "exclamationmark.triangle"
            }
        }
    }

    enum ModelState: Equatable {
        case notChecked
        case preparing
        case ready
        case failed(String)

        var label: String {
            switch self {
            case .notChecked: "Not checked"
            case .preparing: "Preparing local model…"
            case .ready: "Ready offline"
            case let .failed(message): message
            }
        }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    private(set) var state: State = .ready { didSet { onChange?() } }
    private(set) var audioLevel: Float = 0
    private(set) var modelState: ModelState = .notChecked {
        didSet { onChange?() }
    }
    private(set) var lastTranscript: String? { didSet { onChange?() } }
    private(set) var isEnabled = true { didSet { onChange?() } }
    private(set) var preferences: VoicePreferences

    var statusLabel: String {
        if state == .ready {
            return modelState.label
        }
        return state.label
    }

    var statusSymbol: String {
        if state == .ready, modelState == .preparing {
            return "arrow.down.circle"
        }
        return state.symbol
    }

    var canStartRecording: Bool {
        isEnabled && state == .ready && modelState == .ready
    }

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private var recognizer: LocalSpeechRecognizer
    @ObservationIgnored private var stopWhenStarted = false

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let loaded = store.load()
        preferences = loaded
        recognizer = LocalSpeechRecognizer(modelVersion: loaded.modelVersion)
    }

    func setEnabled(_ value: Bool) {
        if !value, state == .recording {
            capture.cancel()
            audioLevel = 0
            state = .ready
        }
        isEnabled = value
    }

    func beginRecording() {
        guard canStartRecording else { return }
        Self.logger.notice("Push-to-talk pressed; starting audio capture")
        state = .starting
        stopWhenStarted = false
        Task {
            do {
                try await capture.start { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.audioLevel = min(max(level * 8, 0), 1)
                    }
                }
                Self.logger.notice("Audio capture started")
                if stopWhenStarted {
                    stopWhenStarted = false
                    finishStartedRecording()
                } else {
                    state = .recording
                    if preferences.playSounds { NSSound.beep() }
                }
            } catch {
                audioLevel = 0
                Self.logger.error(
                    "Audio capture failed: \(error.localizedDescription)"
                )
                state = .failed(error.localizedDescription)
            }
        }
    }

    func finishRecording() {
        if state == .starting {
            stopWhenStarted = true
            return
        }
        guard state == .recording else { return }
        finishStartedRecording()
    }

    func requestMicrophonePermission() {
        Task {
            _ = await requestMicrophonePermissionResult()
        }
    }

    func requestMicrophonePermissionResult() async -> Bool {
        let granted = await capture.requestPermission()
        onChange?()
        return granted
    }

    func prepareLocalModel() {
        Task {
            do {
                try await prepareModelForUse()
            } catch {
                Self.logger.error(
                    "Local model preparation failed: \(error.localizedDescription)"
                )
                modelState = .failed(error.localizedDescription)
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func finishStartedRecording() {
        audioLevel = 0
        state = .processing
        Task {
            do {
                let samples = try capture.stop()
                Self.logger.notice(
                    "Audio capture stopped with \(samples.count) local samples"
                )
                try await prepareModelForUse()
                let transcript = try await recognizer.transcribe(samples: samples)
                let finalText = try transcript.finalText()
                Self.logger.notice(
                    "Final local transcript produced with \(finalText.count) characters"
                )
                try inserter.commit(transcript, mode: preferences.outputMode)
                Self.logger.notice("Final transcript committed at the cursor")
                lastTranscript = finalText
                state = .ready
                if preferences.playSounds { NSSound.beep() }
            } catch {
                Self.logger.error(
                    "Dictation failed: \(error.localizedDescription)"
                )
                state = .failed(error.localizedDescription)
            }
        }
    }

    func recover() {
        guard case .failed = state else { return }
        audioLevel = 0
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

    func setShowRecordingHUD(_ value: Bool) {
        preferences.showRecordingHUD = value
        persist()
    }

    func setLaunchAtLogin(_ value: Bool) {
        preferences.launchAtLogin = value
        persist()
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        persist()
    }

    private func prepareModelForUse() async throws {
        guard modelState != .ready else { return }
        modelState = .preparing
        Self.logger.notice("Preparing pinned local CoreML speech model")
        do {
            try await recognizer.prepare()
            modelState = .ready
            Self.logger.notice("Local CoreML speech model is ready")
        } catch {
            modelState = .failed(error.localizedDescription)
            throw error
        }
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
