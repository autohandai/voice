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
    @ObservationIgnored var onHistoryChange: (() -> Void)?
    private(set) var state: State = .ready { didSet { onChange?() } }
    private(set) var audioLevel: Float = 0
    private(set) var audioInputHealth: AudioInputHealth = .idle
    private(set) var audioInputName = "System Default"
    private(set) var isTestingMicrophone = false
    private(set) var modelState: ModelState = .notChecked {
        didSet { onChange?() }
    }
    private(set) var modelProgress: Double = 0
    private(set) var modelPhase: ModelPreparationPhase? {
        didSet { onChange?() }
    }
    private(set) var modelStorageBytes: Int64 = 0
    private(set) var modelLastValidated: Date?
    private(set) var modelFailureKind: ModelFailureKind?
    private(set) var lastTranscript: String? { didSet { onChange?() } }
    private(set) var lastUnformattedTranscript: String? {
        didSet { onChange?() }
    }
    private(set) var pendingTranscript: String? { didSet { onChange?() } }
    private(set) var hasRecoverableAudio = false { didSet { onChange?() } }
    private(set) var recoverableAudioDuration: TimeInterval = 0
    private(set) var historyError: String?
    private(set) var vocabularyError: String? { didSet { onChange?() } }
    private(set) var profileError: String? { didSet { onChange?() } }
    private(set) var appProfiles: [AppProfile] = []
    private(set) var activeConfiguration: ResolvedAppProfile
    private(set) var isEnabled = true { didSet { onChange?() } }
    private(set) var preferences: VoicePreferences

    var statusLabel: String {
        if state == .ready {
            return modelStatusLabel
        }
        return state.label
    }

    var modelStatusLabel: String {
        if modelState == .preparing, let modelPhase {
            return modelPhase.label
        }
        return modelState.label
    }

    var statusSymbol: String {
        if state == .ready, modelState == .preparing {
            return "arrow.down.circle"
        }
        return state.symbol
    }

    var canStartRecording: Bool {
        isEnabled && state == .ready && modelState == .ready
            && !isTestingMicrophone && !hasRecoverableAudio
    }

    var isRecordingOrStarting: Bool {
        state == .starting || state == .recording
    }

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let capture = AudioCapture()
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private var recognizer: LocalSpeechRecognizer
    @ObservationIgnored private var recognizerModelVersion: String
    @ObservationIgnored private var stopWhenStarted = false
    @ObservationIgnored private var cancelWhenStarted = false
    @ObservationIgnored private var shortcutFailureActive = false
    @ObservationIgnored private var audioHealthMonitor = AudioHealthMonitor()
    @ObservationIgnored private var microphoneTestID: UUID?
    @ObservationIgnored private var insertionTarget: TextInsertionTarget?
    @ObservationIgnored private var audioRecovery = InMemoryAudioRecovery()
    @ObservationIgnored private var audioRecoveryID: UUID?
    @ObservationIgnored private var modelTask: Task<Void, Never>?
    @ObservationIgnored private var modelOperationID: UUID?
    @ObservationIgnored private let historyStore = HistoryStore()
    @ObservationIgnored private let vocabularyStore = VocabularyStore()
    @ObservationIgnored private let appProfileStore = AppProfileStore()
    @ObservationIgnored private var historyEntryID: UUID?

    init(store: PreferencesStore = PreferencesStore()) {
        self.store = store
        let loaded = store.load()
        preferences = loaded
        activeConfiguration = AppProfileResolver.resolve(
            preferences: loaded,
            profiles: [],
            bundleIdentifier: nil
        )
        recognizer = LocalSpeechRecognizer(modelVersion: loaded.modelVersion)
        recognizerModelVersion = loaded.modelVersion
        reloadAppProfiles()
        refreshActiveProfile()
    }

    var activeProfileLabel: String {
        activeConfiguration.profileName ?? "Global"
    }

    var activeAppProfile: AppProfile? {
        guard let id = activeConfiguration.profileID else { return nil }
        return appProfiles.first { $0.id == id }
    }

    var effectiveRecordingMode: RecordingMode {
        activeConfiguration.recordingMode
    }

    var effectiveShowRecordingHUD: Bool {
        activeConfiguration.showRecordingHUD
    }

    var effectivePlaySounds: Bool {
        activeConfiguration.playSounds
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
        refreshActiveProfile()
        guard canStartRecording else { return }
        let configuration = activeConfiguration
        insertionTarget = nil
        if configuration.outputMode == .type {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                state = .failed(
                    VoiceError.accessibilityPermissionDenied.localizedDescription
                )
                return
            }
            guard let target = inserter.captureTarget() else {
                state = .failed(VoiceError.noFocusedTextField.localizedDescription)
                return
            }
            insertionTarget = target
        } else {
            insertionTarget = nil
        }
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
                    insertionTarget = nil
                    state = .ready
                } else if stopWhenStarted {
                    stopWhenStarted = false
                    finishStartedRecording()
                } else {
                    state = .recording
                    if activeConfiguration.playSounds { NSSound.beep() }
                }
            } catch {
                audioLevel = 0
                insertionTarget = nil
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
        insertionTarget = nil
        audioLevel = 0
        audioHealthMonitor.reset()
        audioInputHealth = .idle
        state = .ready
    }

    func refreshActiveProfile() {
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier
        activeConfiguration = AppProfileResolver.resolve(
            preferences: preferences,
            profiles: appProfiles,
            bundleIdentifier: bundleIdentifier
        )
        synchronizeRecognizerWithActiveProfile()
        onChange?()
    }

    func replaceAppProfiles(_ profiles: [AppProfile]) {
        appProfiles = profiles
        profileError = nil
        refreshActiveProfile()
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
        startModelPreparation(repair: false)
    }

    func repairLocalModel() {
        startModelPreparation(repair: true)
    }

    func cancelModelPreparation() {
        modelTask?.cancel()
        modelTask = nil
        modelOperationID = nil
        modelProgress = 0
        modelPhase = nil
        modelState = .notChecked
    }

    func validateLocalModel() {
        guard modelState != .preparing else { return }
        modelPhase = .validating
        modelState = .preparing
        Task {
            do {
                let isValid = try await recognizer.validate()
                try Task.checkCancellation()
                guard isValid else {
                    throw VoiceError.modelUnavailable(
                        "CoreML validation did not pass"
                    )
                }
                modelStorageBytes = try await recognizer.storageBytes()
                modelLastValidated = Date()
                modelProgress = 1
                modelPhase = nil
                modelFailureKind = nil
                modelState = .ready
            } catch {
                setModelFailure(error)
            }
        }
    }

    func setModelVariant(_ variant: SpeechModelVariant) {
        guard
            !isRecordingOrStarting,
            state != .processing,
            preferences.modelVersion != variant.rawValue
        else { return }
        cancelModelPreparation()
        if !variant.supports(
            languageCode: preferences.dictationLanguageCode
        ) {
            preferences.dictationLanguageCode =
                SupportedDictationLanguage.english.code
        }
        preferences.modelVersion = variant.rawValue
        recognizer = LocalSpeechRecognizer(modelVersion: variant.rawValue)
        recognizerModelVersion = variant.rawValue
        modelStorageBytes = 0
        modelLastValidated = nil
        modelFailureKind = nil
        persist()
        prepareLocalModel()
    }

    func setDictationLanguage(_ language: SupportedDictationLanguage) {
        guard !isRecordingOrStarting, state != .processing else { return }
        let current = SpeechModelVariant(
            rawValue: preferences.modelVersion
        ) ?? .default
        preferences.dictationLanguageCode = language.code
        if !current.supports(languageCode: language.code) {
            cancelModelPreparation()
            preferences.modelVersion = SpeechModelVariant.v3.rawValue
            recognizerModelVersion = SpeechModelVariant.v3.rawValue
            recognizer = LocalSpeechRecognizer(
                modelVersion: SpeechModelVariant.v3.rawValue
            )
            modelStorageBytes = 0
            modelLastValidated = nil
            modelFailureKind = nil
            persist()
            prepareLocalModel()
        } else {
            persist()
        }
    }

    func removeLocalModel(_ variant: SpeechModelVariant) {
        guard !isRecordingOrStarting, state != .processing else { return }
        do {
            if recognizerModelVersion == variant.rawValue {
                cancelModelPreparation()
                recognizer = LocalSpeechRecognizer(
                    modelVersion: variant.rawValue
                )
                modelStorageBytes = 0
                modelLastValidated = nil
                modelFailureKind = nil
            }
            try ModelCacheManager.remove(variant)
            if recognizerModelVersion == variant.rawValue {
                modelState = .notChecked
            }
        } catch {
            state = .failed(
                "Could not remove \(variant.displayName): \(error.localizedDescription)"
            )
        }
    }

    private func finishStartedRecording() {
        audioLevel = 0
        state = .processing
        Task {
            do {
                let samples = try capture.stop()
                retainAudioRecovery(samples)
                Self.logger.notice(
                    "Audio capture stopped with \(samples.count) local samples"
                )
                try await transcribeAndCommit(
                    samples: samples,
                    target: insertionTarget
                )
            } catch {
                insertionTarget = nil
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

    func copyLastUnformattedTranscript() {
        guard let lastUnformattedTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            lastUnformattedTranscript,
            forType: .string
        )
    }

    func retryPendingTranscriptHere() {
        guard let pendingTranscript else { return }
        do {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                throw VoiceError.accessibilityPermissionDenied
            }
            guard let target = inserter.captureTarget() else {
                throw VoiceError.noFocusedTextField
            }
            try inserter.commitVerifiedFinalText(
                pendingTranscript,
                mode: .type,
                target: target
            )
            lastTranscript = pendingTranscript
            updateHistoryOutcome(.inserted)
            self.pendingTranscript = nil
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func copyPendingTranscript() {
        guard let pendingTranscript else { return }
        do {
            try inserter.commitVerifiedFinalText(
                pendingTranscript,
                mode: .clipboard
            )
            lastTranscript = pendingTranscript
            historyEntryID = nil
            self.pendingTranscript = nil
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func discardPendingTranscript() {
        historyEntryID = nil
        pendingTranscript = nil
        insertionTarget = nil
        if case .failed = state {
            state = .ready
        }
    }

    func retryRecoverableAudio() {
        guard state != .processing else { return }
        guard let samples = audioRecovery.samples(
            at: ProcessInfo.processInfo.systemUptime
        ) else {
            discardAudioRecovery()
            state = .failed("Recovery audio expired and was erased.")
            return
        }

        refreshActiveProfile()
        let target: TextInsertionTarget?
        if activeConfiguration.outputMode == .type {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                state = .failed(
                    VoiceError.accessibilityPermissionDenied.localizedDescription
                )
                return
            }
            guard let currentTarget = inserter.captureTarget() else {
                state = .failed(VoiceError.noFocusedTextField.localizedDescription)
                return
            }
            target = currentTarget
        } else {
            target = nil
        }

        state = .processing
        Task {
            do {
                try await transcribeAndCommit(samples: samples, target: target)
            } catch {
                Self.logger.error(
                    "Recovery failed: \(error.localizedDescription)"
                )
                state = .failed(error.localizedDescription)
            }
        }
    }

    func discardRecoverableAudio() {
        discardAudioRecovery()
        if case .failed = state, pendingTranscript == nil {
            state = .ready
        }
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

    func setHistoryEnabled(_ value: Bool) {
        preferences.historyEnabled = value
        persist()
        onHistoryChange?()
    }

    func setHistoryRetentionDays(_ value: Int) {
        preferences.historyRetentionDays = max(1, value)
        persist()
        pruneHistory()
    }

    func setHistoryMaximumItems(_ value: Int) {
        preferences.historyMaximumItems = max(1, value)
        persist()
        pruneHistory()
    }

    func setDictationCommandsEnabled(_ value: Bool) {
        preferences.dictationCommandsEnabled = value
        persist()
    }

    func setSmartFormattingEnabled(_ value: Bool) {
        preferences.smartFormattingEnabled = value
        persist()
    }

    func setAutomaticTerminalPunctuation(_ value: Bool) {
        preferences.automaticTerminalPunctuation = value
        persist()
    }

    func deleteAllHistory() {
        do {
            try historyStore.deleteAll()
            historyError = nil
            onHistoryChange?()
        } catch {
            historyError = "Could not erase history: \(error.localizedDescription)"
            onChange?()
        }
    }

    func completeOnboarding() {
        preferences.hasCompletedOnboarding = true
        persist()
    }

    private func prepareModelForUse() async throws {
        guard modelState != .ready else { return }
        if modelState == .preparing, let modelTask {
            await modelTask.value
            guard modelState == .ready else {
                throw VoiceError.modelUnavailable(modelState.label)
            }
            return
        }
        let operationID = UUID()
        modelOperationID = operationID
        modelState = .preparing
        modelProgress = 0
        modelPhase = .checking
        Self.logger.notice("Preparing pinned local CoreML speech model")
        do {
            try await runModelOperation(
                repair: false,
                operationID: operationID
            )
            try Task.checkCancellation()
            guard modelOperationID == operationID else {
                throw CancellationError()
            }
            modelOperationID = nil
            modelState = .ready
            Self.logger.notice("Local CoreML speech model is ready")
        } catch {
            if modelOperationID == operationID {
                modelOperationID = nil
            }
            if error is CancellationError {
                modelState = .notChecked
            } else {
                setModelFailure(error)
            }
            throw error
        }
    }

    private func startModelPreparation(repair: Bool) {
        modelTask?.cancel()
        let operationID = UUID()
        modelOperationID = operationID
        modelProgress = 0
        modelPhase = .checking
        modelFailureKind = nil
        modelState = .preparing
        modelTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runModelOperation(
                    repair: repair,
                    operationID: operationID
                )
                try Task.checkCancellation()
                guard self.modelOperationID == operationID else { return }
                self.modelOperationID = nil
                self.modelTask = nil
                self.modelState = .ready
                if case .failed = self.state {
                    self.state = .ready
                }
            } catch is CancellationError {
                guard self.modelOperationID == operationID else { return }
                self.modelOperationID = nil
                self.modelTask = nil
                self.modelProgress = 0
                self.modelPhase = nil
                self.modelState = .notChecked
            } catch {
                guard self.modelOperationID == operationID else { return }
                self.modelOperationID = nil
                self.modelTask = nil
                self.setModelFailure(error)
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    private func runModelOperation(
        repair: Bool,
        operationID: UUID
    ) async throws {
        let progressHandler: @Sendable (ModelPreparationProgress) -> Void = {
            [weak self] progress in
            Task { @MainActor [weak self] in
                guard self?.modelOperationID == operationID else { return }
                self?.modelProgress = progress.fractionCompleted
                self?.modelPhase = progress.phase
            }
        }
        if repair {
            try await recognizer.repair(onProgress: progressHandler)
        } else {
            try await recognizer.prepare(onProgress: progressHandler)
        }
        try Task.checkCancellation()
        modelPhase = .validating
        let isValid = try await recognizer.validate()
        guard isValid else {
            throw VoiceError.modelUnavailable("CoreML validation did not pass")
        }
        modelStorageBytes = try await recognizer.storageBytes()
        modelLastValidated = Date()
        modelProgress = 1
        modelPhase = nil
        modelFailureKind = nil
    }

    private func setModelFailure(_ error: Error) {
        let message = error.localizedDescription
        modelFailureKind = .classify(message)
        modelProgress = 0
        modelPhase = nil
        modelState = .failed(
            "\(modelFailureKind?.label ?? "Model preparation failed"): \(message)"
        )
    }

    private func transcribeAndCommit(
        samples: [Float],
        target: TextInsertionTarget?
    ) async throws {
        try await prepareModelForUse()
        let transcript = try await recognizer.transcribe(samples: samples)
        let recognizedText = try transcript.finalText()
        let configuration = activeConfiguration
        let commandResult = DictationCommandProcessor.process(
            recognizedText,
            enabled: configuration.dictationCommandsEnabled,
            locale: Locale(
                identifier: configuration.dictationLanguageCode
            )
        )
        if commandResult.shouldCancel {
            discardAudioRecovery()
            pendingTranscript = nil
            insertionTarget = nil
            state = .ready
            Self.logger.notice(
                "Dictation cancelled by explicit local voice command"
            )
            return
        }
        guard commandResult.text.contains(where: { !$0.isWhitespace }) else {
            throw VoiceError.emptyTranscript
        }
        let replacementText: String
        do {
            replacementText = VocabularyProcessor.apply(
                to: commandResult.text,
                rules: try vocabularyStore.load(),
                locale: Locale(
                    identifier: configuration.dictationLanguageCode
                )
            )
            vocabularyError = nil
        } catch {
            replacementText = commandResult.text
            vocabularyError = "Replacements could not be loaded: \(error.localizedDescription)"
            Self.logger.error(
                "Vocabulary load failed; preserving recognized text: \(error.localizedDescription)"
            )
        }
        let finalText = SmartTextFormatter.format(
            replacementText,
            context: target?.context ?? .unknown,
            enabled: configuration.smartFormattingEnabled,
            addsTerminalPunctuation:
                configuration.automaticTerminalPunctuation,
            locale: Locale(
                identifier: configuration.dictationLanguageCode
            )
        )
        lastUnformattedTranscript = finalText == replacementText
            ? nil
            : replacementText
        pendingTranscript = finalText
        discardAudioRecovery()
        recordHistory(text: finalText, outcome: .insertionFailed)
        Self.logger.notice(
            "Final local transcript produced with \(finalText.count) characters"
        )
        try inserter.commitVerifiedFinalText(
            finalText,
            mode: configuration.outputMode,
            target: target
        )
        Self.logger.notice("Final transcript committed at the cursor")
        lastTranscript = finalText
        updateHistoryOutcome(.inserted)
        pendingTranscript = nil
        insertionTarget = nil
        state = .ready
        if configuration.playSounds { NSSound.beep() }
    }

    private func reloadAppProfiles() {
        do {
            appProfiles = try appProfileStore.load()
            profileError = nil
        } catch {
            appProfiles = []
            profileError = "App profiles could not be loaded: \(error.localizedDescription)"
        }
    }

    private func synchronizeRecognizerWithActiveProfile() {
        guard
            !isRecordingOrStarting,
            state != .processing,
            activeConfiguration.modelVersion != recognizerModelVersion
        else { return }
        cancelModelPreparation()
        recognizerModelVersion = activeConfiguration.modelVersion
        recognizer = LocalSpeechRecognizer(
            modelVersion: activeConfiguration.modelVersion
        )
        modelStorageBytes = 0
        modelLastValidated = nil
        modelFailureKind = nil
        prepareLocalModel()
    }

    private func retainAudioRecovery(_ samples: [Float]) {
        let recoveryID = UUID()
        audioRecoveryID = recoveryID
        audioRecovery.store(
            samples,
            at: ProcessInfo.processInfo.systemUptime
        )
        recoverableAudioDuration = audioRecovery.duration
        hasRecoverableAudio = audioRecovery.sampleCount > 0

        Task { [weak self] in
            try? await Task.sleep(
                for: .seconds(InMemoryAudioRecovery.defaultExpiration)
            )
            guard let self, self.audioRecoveryID == recoveryID else { return }
            self.discardAudioRecovery()
            if self.pendingTranscript == nil {
                self.state = .failed("Recovery audio expired and was erased.")
            }
        }
    }

    private func discardAudioRecovery() {
        audioRecoveryID = nil
        audioRecovery.discard()
        clearAudioRecoveryState()
    }

    private func clearAudioRecoveryState() {
        recoverableAudioDuration = 0
        hasRecoverableAudio = false
    }

    private func recordHistory(
        text: String,
        outcome: HistoryOutcome
    ) {
        guard preferences.historyEnabled else {
            historyEntryID = nil
            return
        }
        do {
            let entry = try historyStore.append(
                text: text,
                outcome: outcome,
                retentionDays: preferences.historyRetentionDays,
                maximumItems: preferences.historyMaximumItems
            )
            historyEntryID = entry.id
            historyError = nil
            onHistoryChange?()
        } catch {
            historyEntryID = nil
            historyError = "Could not save local history: \(error.localizedDescription)"
            onChange?()
        }
    }

    private func updateHistoryOutcome(_ outcome: HistoryOutcome) {
        guard let historyEntryID else { return }
        do {
            try historyStore.updateOutcome(
                id: historyEntryID,
                outcome: outcome
            )
            self.historyEntryID = nil
            historyError = nil
            onHistoryChange?()
        } catch {
            historyError = "Could not update local history: \(error.localizedDescription)"
            onChange?()
        }
    }

    private func pruneHistory() {
        guard preferences.historyEnabled else { return }
        do {
            _ = try historyStore.load(
                retentionDays: preferences.historyRetentionDays,
                maximumItems: preferences.historyMaximumItems
            )
            historyError = nil
            onHistoryChange?()
        } catch {
            historyError = "Could not prune local history: \(error.localizedDescription)"
            onChange?()
        }
    }

    private func persist() {
        do {
            try store.save(preferences)
        } catch {
            state = .failed("Could not save settings: \(error.localizedDescription)")
        }
        if !isRecordingOrStarting, state != .processing {
            refreshActiveProfile()
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
