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
    @ObservationIgnored var onShortcutRegistration:
        ((RegisteredShortcut) -> OSStatus)?
    private(set) var state: State = .ready { didSet { onChange?() } }
    private(set) var audioLevel: Float = 0
    private(set) var audioInputHealth: AudioInputHealth = .idle
    private(set) var audioInputName = "System Default"
    private(set) var isTestingMicrophone = false
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
            && !isTestingMicrophone
    }

    var isRecordingOrStarting: Bool {
        state == .starting || state == .recording
    }

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private var recognizer: LocalSpeechRecognizer
    @ObservationIgnored private var stopWhenStarted = false
    @ObservationIgnored private var cancelWhenStarted = false
    @ObservationIgnored private var shortcutFailureActive = false
    @ObservationIgnored private var audioHealthMonitor = AudioHealthMonitor()
    @ObservationIgnored private var microphoneTestID: UUID?

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let loaded = store.load()
        preferences = loaded
        recognizer = LocalSpeechRecognizer(modelVersion: loaded.modelVersion)
    }

    func setEnabled(_ value: Bool) {
        if !value, isTestingMicrophone {
            stopMicrophoneTest()
        }
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
        cancelWhenStarted = false
        Task {
            do {
                try await capture.start(
                    deviceUID: preferences.audioInputDeviceUID
                ) { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.observeAudioLevel(level)
                    }
                }
                Self.logger.notice("Audio capture started")
                if cancelWhenStarted {
                    cancelWhenStarted = false
                    capture.cancel()
                    audioLevel = 0
                    audioHealthMonitor.reset()
                    audioInputHealth = .idle
                    state = .ready
                } else if stopWhenStarted {
                    stopWhenStarted = false
                    finishStartedRecording()
                } else {
                    state = .recording
                    if preferences.playSounds { NSSound.beep() }
                }
            } catch {
                audioLevel = 0
                if error as? AudioInputDeviceError
                    == .selectedDeviceUnavailable {
                    audioHealthMonitor.disconnect()
                    audioInputHealth = .disconnected
                }
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

    func cancelRecording() {
        if state == .starting {
            stopWhenStarted = false
            cancelWhenStarted = true
            return
        }
        guard state == .recording else { return }
        capture.cancel()
        audioLevel = 0
        audioHealthMonitor.reset()
        audioInputHealth = .idle
        state = .ready
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

    func setAudioInputDevice(_ uid: String?) {
        preferences.audioInputDeviceUID = uid
        audioHealthMonitor.reset()
        audioInputHealth = .idle
        persist()
    }

    func reportAudioInputDisconnected() {
        audioHealthMonitor.disconnect()
        audioInputHealth = .disconnected
    }

    func reportAudioInputAvailable(name: String) {
        audioInputName = name
        guard !isTestingMicrophone, state != .recording else { return }
        audioHealthMonitor.reset()
        audioInputHealth = .idle
    }

    func startMicrophoneTest() {
        guard state == .ready, !isTestingMicrophone else { return }
        let testID = UUID()
        microphoneTestID = testID
        isTestingMicrophone = true
        audioHealthMonitor.reset()
        audioInputHealth = .listening
        Task {
            do {
                try await capture.start(
                    deviceUID: preferences.audioInputDeviceUID
                ) { [weak self] level in
                    Task { @MainActor [weak self] in
                        self?.observeAudioLevel(level)
                    }
                }
                try await Task.sleep(for: .seconds(8))
                guard microphoneTestID == testID else { return }
                stopMicrophoneTest()
            } catch is CancellationError {
                stopMicrophoneTest()
            } catch {
                capture.cancel()
                microphoneTestID = nil
                isTestingMicrophone = false
                audioLevel = 0
                if error as? AudioInputDeviceError
                    == .selectedDeviceUnavailable {
                    audioHealthMonitor.disconnect()
                    audioInputHealth = .disconnected
                } else {
                    audioInputHealth = .idle
                }
                state = .failed(
                    "Microphone test failed: \(error.localizedDescription)"
                )
            }
        }
    }

    func stopMicrophoneTest() {
        guard isTestingMicrophone else { return }
        microphoneTestID = nil
        capture.cancel()
        isTestingMicrophone = false
        audioLevel = 0
        audioHealthMonitor.reset()
        audioInputHealth = .idle
    }

    func setPushToTalkKey(_ key: PushToTalkKey) {
        preferences.pushToTalkKey = key
        persist()
    }

    @discardableResult
    func setShortcut(_ shortcut: RegisteredShortcut) -> Bool {
        guard shortcut.isValid else {
            shortcutFailureActive = true
            state = .failed("Choose a valid shortcut with at least one modifier.")
            return false
        }
        let status = onShortcutRegistration?(shortcut) ?? noErr
        guard status == noErr else {
            shortcutFailureActive = true
            state = .failed(
                "That shortcut is unavailable (registration error \(status))."
            )
            return false
        }
        preferences.shortcut = shortcut
        if shortcutFailureActive {
            shortcutFailureActive = false
            state = .ready
        }
        persist()
        return true
    }

    func setRecordingMode(_ mode: RecordingMode) {
        if isRecordingOrStarting {
            cancelRecording()
        }
        preferences.recordingMode = mode
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

    private func observeAudioLevel(_ level: Float) {
        audioLevel = min(max(level * 8, 0), 1)
        audioInputHealth = audioHealthMonitor.observe(
            level: level,
            at: ProcessInfo.processInfo.systemUptime
        )
    }
}
