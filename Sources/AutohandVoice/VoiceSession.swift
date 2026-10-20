import AppKit
import AutohandVoiceCore
import AutohandVoiceQwenASR
import Foundation
import Observation
import OSLog

private struct PreviewAudioChunk: Sendable {
    let samples: [Float]
    let sampleRate: Double
}

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
    @ObservationIgnored var onScratchpadShortcutRegistration:
        ((RegisteredShortcut) -> OSStatus)?
    @ObservationIgnored var onInputBindingsRegistration:
        (([InputBinding]) -> OSStatus)?
    @ObservationIgnored var onPointerMonitoringChange:
        ((Bool, Bool) -> PointerInputMonitorResult)?
    @ObservationIgnored var onFunctionKeyMonitoringChange:
        ((Bool, Bool) -> FunctionKeyMonitorResult)?
    @ObservationIgnored var onHistoryChange: (() -> Void)?
    @ObservationIgnored var onInsightsChange: (() -> Void)?
    @ObservationIgnored var onOperationalIssuesChange: (() -> Void)?
    @ObservationIgnored var onReliabilityChange: (() -> Void)?
    @ObservationIgnored var onQuickDictation:
        ((String) async throws -> Void)?
    @ObservationIgnored var onOpenScratchpad: (() -> Void)?
    @ObservationIgnored var onSystemNotification:
        ((SystemVoiceNotification) -> Void)?
    @ObservationIgnored var onNotificationPermissionRequest:
        (() async -> Bool)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored var onOpenHistory: (() -> Void)?
    @ObservationIgnored var onPrepareLocalDataReset:
        (() async -> Void)?
    @ObservationIgnored var onLocalDataReset: (() -> Void)?
    private(set) var state: State = .ready { didSet { onChange?() } }
    private(set) var audioLevel: Float = 0
    private(set) var recordingStartedWithFunctionKey = false
    /// The current recording is a Talk question (Fn+Shift), not dictation.
    private(set) var isTalkRecording = false
    /// A hands-free Talk conversation is running: Voice listens, sends the
    /// turn after a pause, speaks the reply, then listens again.
    private(set) var isTalkHandsFree = false
    @ObservationIgnored let talk: TalkController
    @ObservationIgnored private var handsFreeEndpointer = TalkEndpointer()
    @ObservationIgnored private var handsFreeNoiseFloorDB: Double?
    @ObservationIgnored private var handsFreeEmptyTurns = 0
    @ObservationIgnored private var handsFreeLastDecision: TalkEndpointer.Decision?
    @ObservationIgnored private var handsFreeModelWaitStarted: TimeInterval?
    @ObservationIgnored private var handsFreeAssembler = HandsFreeTurnAssembler()
    @ObservationIgnored private var handsFreeTranscribing = false
    @ObservationIgnored private var handsFreeResumeTask: Task<Void, Never>?
    /// The current Fn press started or ended a hands-free conversation, so
    /// its remaining intents are ignored.
    @ObservationIgnored private var functionKeyPressHandledByTalk = false
    @ObservationIgnored private(set) var audioInputRMS: Float = 0
    @ObservationIgnored private var functionKeyHoldConfirmed = false
    @ObservationIgnored private var discardAudioWhenStarted = false
    private(set) var audioInputHealth: AudioInputHealth = .idle
    private(set) var audioInputName = "System Default"
    private(set) var shortcutRegistrationState:
        DiagnosticShortcutState = .notChecked {
        didSet { onChange?() }
    }
    private(set) var scratchpadShortcutError: String?
    private(set) var pointerInputStatus = "Off" {
        didSet { onChange?() }
    }
    private(set) var functionKeyLongPressStatus = "Off" {
        didSet { onChange?() }
    }
    private(set) var observedPointerButton: Int? {
        didSet { onChange?() }
    }
    private(set) var inputBindingError: String? {
        didSet { onChange?() }
    }
    private(set) var inAppNotificationMessage: String? {
        didSet { onChange?() }
    }
    private(set) var isTestingMicrophone = false
    private(set) var modelState: ModelState = .notChecked {
        didSet { onChange?() }
    }
    private(set) var modelProgress: Double = 0
    private(set) var modelPhase: ModelPreparationPhase? {
        didSet { onChange?() }
    }
    private(set) var modelPreparationPresentation:
        ModelPreparationPresentation = .background {
        didSet { onChange?() }
    }
    private(set) var modelStorageBytes: Int64 = 0
    private(set) var modelLastValidated: Date?
    private(set) var modelFailureKind: ModelFailureKind?
    private(set) var lastTranscript: String? { didSet { onChange?() } }
    private(set) var completionPresentation: String? {
        didSet { onChange?() }
    }
    private(set) var lastUnformattedTranscript: String? {
        didSet { onChange?() }
    }
    private(set) var currentRevision: TranscriptRevision? {
        didSet { onChange?() }
    }
    private(set) var currentRawFinal: RawFinalTranscript? {
        didSet { onChange?() }
    }
    private(set) var pendingTranscript: String? { didSet { onChange?() } }
    private(set) var provisionalTranscript: String? {
        didSet { onChange?() }
    }
    private(set) var provisionalPreviewNotice: String? {
        didSet { onChange?() }
    }
    private(set) var recordingElapsed: TimeInterval = 0 {
        didSet { onChange?() }
    }
    private(set) var durationWarning: DictationDurationWarning? {
        didSet { onChange?() }
    }
    private(set) var hasRecoverableAudio = false { didSet { onChange?() } }
    private(set) var recoverableAudioDuration: TimeInterval = 0
    private(set) var recoverableAudioWasCancelled = false {
        didSet { onChange?() }
    }
    private(set) var persistentRecoverySummaries: [RecoverySummary] = [] {
        didSet { onChange?() }
    }
    private(set) var persistentRecoveryError: String? {
        didSet { onChange?() }
    }
    private(set) var isCheckingPersistentRecovery = false {
        didSet { onChange?() }
    }
    private(set) var isResettingLocalData = false {
        didSet { onChange?() }
    }
    private(set) var localDataResetMessage: String? {
        didSet { onChange?() }
    }
    private(set) var historyError: String?
    private(set) var usageInsightsError: String? {
        didSet { onChange?() }
    }
    private(set) var vocabularyError: String? { didSet { onChange?() } }
    private(set) var profileError: String? { didSet { onChange?() } }
    private(set) var isFileTranscriptionActive = false {
        didSet { onChange?() }
    }
    private(set) var appProfiles: [AppProfile] = []
    private(set) var customDictationStyles: [DictationStylePreset] = []
    private(set) var styleError: String?
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
        if modelState == .preparing,
            !modelPreparationPresentation.showsDetailedProgress {
            return "Starting local speech engine…"
        }
        if modelState == .preparing, let modelPhase {
            return modelPhase.label
        }
        return modelState.label
    }

    var showsModelPreparationProgress: Bool {
        modelState == .preparing
            && modelPreparationPresentation.showsDetailedProgress
    }

    var statusSymbol: String {
        if state == .ready, modelState == .preparing {
            return modelPreparationPresentation.showsDetailedProgress
                ? "arrow.down.circle"
                : state.symbol
        }
        return state.symbol
    }

    var canStartRecording: Bool {
        var gate = DictationStartGate()
        gate.isEnabled = isEnabled
        switch state {
        case .ready: gate.activity = .ready
        case .failed: gate.activity = .failed
        case .starting, .recording, .processing: gate.activity = .busy
        }
        gate.modelReady = modelState == .ready
        gate.isTestingMicrophone = isTestingMicrophone
        gate.hasRecoverableAudio = hasRecoverableAudio
        gate.isCheckingPersistentRecovery = isCheckingPersistentRecovery
        gate.hasPendingPersistentRecovery = persistentRecoveryEnabled
            && !persistentRecoverySummaries.isEmpty
        gate.isFileTranscriptionActive = isFileTranscriptionActive
        return gate.canStart
    }

    var isRecordingOrStarting: Bool {
        state == .starting || state == .recording
    }

    var lifecycleActivity: DictationActivity {
        switch state {
        case .starting: .starting
        case .recording: .recording
        case .processing: .processing
        case .ready, .failed: .ready
        }
    }

    var requiresTerminationConfirmation: Bool {
        VoiceLifecyclePolicy.action(
            for: .termination,
            activity: lifecycleActivity
        ) == .confirmDiscard
    }

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private let capture: AudioCapture
    @ObservationIgnored private let durationPolicy: DictationDurationPolicy
    @ObservationIgnored private let featureFlags: FeatureFlags
    @ObservationIgnored private let clamshellStateChecker:
        any ClamshellStateChecking
    @ObservationIgnored private let inserter = TextInserter()
    @ObservationIgnored private var recognizer: LocalSpeechRecognizer
    /// Optional Qwen3-ASR engine (MLX, Apple Silicon), used when chosen.
    @ObservationIgnored private let qwenRecognizer = Qwen3SpeechRecognizer()
    /// Qwen3-ASR download/load progress while it prepares, 0...1.
    private(set) var qwenPreparationProgress: Double?
    private(set) var qwenStatus: String?
    @ObservationIgnored private var qwenPreparationTask: Task<Void, Never>?
    @ObservationIgnored private var recognizerModelVersion: String
    @ObservationIgnored private var stopWhenStarted = false
    @ObservationIgnored private var cancelWhenStarted = false
    @ObservationIgnored private var pendingLifecycleInterruption: String?
    @ObservationIgnored private var shortcutFailureActive = false
    @ObservationIgnored private var audioHealthMonitor = AudioHealthMonitor()
    @ObservationIgnored private var microphoneTestID: UUID?
    @ObservationIgnored private var insertionTarget: TextInsertionTarget?
    @ObservationIgnored private var audioRecovery = InMemoryAudioRecovery()
    @ObservationIgnored private var audioRecoveryID: UUID?
    @ObservationIgnored private var persistentRecoveryID: UUID?
    @ObservationIgnored private var modelTask: Task<Void, Never>?
    @ObservationIgnored private var modelOperationID: UUID?
    @ObservationIgnored private let historyStore = HistoryStore()
    @ObservationIgnored private let vocabularyStore = VocabularyStore()
    @ObservationIgnored private let appProfileStore = AppProfileStore()
    @ObservationIgnored private let dictationStyleStore =
        DictationStyleStore()
    @ObservationIgnored private let usageInsightsStore = UsageInsightsStore()
    @ObservationIgnored private let operationalIssueStore =
        OperationalIssueStore()
    @ObservationIgnored private let reliabilityLedger = ReliabilityLedger()
    @ObservationIgnored private let dictationCoordinator =
        DictationCoordinator()
    @ObservationIgnored private let revisionEngine = Revision()
    @ObservationIgnored private let sensitiveContextPolicy =
        SensitiveContextPolicy()
    @ObservationIgnored private let recoveryVault = RecoveryVault()
    @ObservationIgnored private let notificationPolicy =
        NotificationPolicy()
    @ObservationIgnored private let faultInjector: any VoiceFaultInjecting
    @ObservationIgnored private var recordingStartRequestedAt:
        TimeInterval?
    @ObservationIgnored private var coordinatorSessionID: UUID?
    @ObservationIgnored private var historyEntryID: UUID?
    @ObservationIgnored private var pendingUsageDay: Date?
    @ObservationIgnored private var previewBuffer = ProvisionalPreviewBuffer()
    @ObservationIgnored private var previewAudioContinuation:
        AsyncStream<PreviewAudioChunk>.Continuation?
    @ObservationIgnored private var previewAudioTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryAudioContinuation:
        AsyncStream<PreviewAudioChunk>.Continuation?
    @ObservationIgnored private var recoveryAudioTask:
        Task<String?, Never>?
    @ObservationIgnored private var recoveryStreamBackpressure = false
    @ObservationIgnored private var currentAudioDeviceUID: String?
    @ObservationIgnored private var audioRouteTimeline = AudioRouteTimeline()
    @ObservationIgnored private var audioHandoffInProgress = false
    @ObservationIgnored private var durationTimerTask: Task<Void, Never>?
    @ObservationIgnored private var temporaryStyleID: UUID?
    @ObservationIgnored private var temporaryStyleExpiresAtUptime:
        TimeInterval?
    @ObservationIgnored private var quickDictationTargetActive = false
    @ObservationIgnored private var inputBindingReducer =
        InputBindingReducer()
    @ObservationIgnored private var commitEnterTarget:
        TextInsertionTarget?
    @ObservationIgnored private var commitEnterExpiresAtUptime:
        TimeInterval?
    @ObservationIgnored private var recordingActivity:
        NSObjectProtocol?
    @ObservationIgnored private var completionTask:
        Task<Void, Never>?
    @ObservationIgnored private var completionExpiresAtUptime:
        TimeInterval?
    @ObservationIgnored private var postDictationRedoRevisionID: UUID?

    init(
        store: PreferencesStore = PreferencesStore(),
        faultInjector: any VoiceFaultInjecting = NoVoiceFaultInjector(),
        clamshellStateChecker: any ClamshellStateChecking =
            SystemClamshellStateChecker(),
        talk: TalkController? = nil
    ) {
        self.talk = talk ?? TalkController()
        self.store = store
        self.faultInjector = faultInjector
        self.clamshellStateChecker = clamshellStateChecker
        let featureFlags = FeatureFlags()
        self.featureFlags = featureFlags
        let durationPolicy = DictationDurationPolicy(flags: featureFlags)
        self.durationPolicy = durationPolicy
        capture = AudioCapture(
            maximumDuration: durationPolicy.maximumDuration
        )
        let loaded = store.load()
        preferences = loaded
        activeConfiguration = AppProfileResolver.resolve(
            preferences: loaded,
            profiles: [],
            bundleIdentifier: nil
        )
        recognizer = LocalSpeechRecognizer(modelVersion: loaded.modelVersion)
        recognizerModelVersion = loaded.modelVersion
        isCheckingPersistentRecovery =
            featureFlags.isEnabled(.persistentRecovery)
        reloadDictationStyles()
        reloadAppProfiles()
        refreshActiveProfile()
        self.talk.onInsert = { [weak self] reply in
            self?.insertTalkReply(reply)
        }
        self.talk.onTurnEnded = { [weak self] keepListening in
            self?.talkTurnEnded(keepListening: keepListening)
        }
        self.talk.onConversationEnded = { [weak self] in
            self?.endHandsFreeTalk()
        }
        self.talk.engine = { [weak self] in
            self?.preferences.talkEngine ?? .fantail
        }
        self.talk.localModel = BonsaiTalkModel()
        self.talk.toolbox = TalkAgentToolbox(
            workspaceURL: { [weak self] in
                self?.preferences.talkWorkspaceURL ?? WorkspaceSandbox.defaultRoot
            },
            computerUseEnabled: { [weak self] in
                self?.preferences.talkComputerUseEnabled ?? false
            }
        )
    }

    var activeProfileLabel: String {
        activeConfiguration.profileName ?? "Global"
    }

    var dictationStyles: [DictationStylePreset] {
        DictationStyleStore.all(custom: customDictationStyles)
    }

    var activeStyleLabel: String {
        activeConfiguration.styleName
            ?? activeConfiguration.cleanupLevel.rawValue.capitalized
    }

    var activeStyleSource: DictationStyleSource {
        activeConfiguration.styleSource
    }

    var activeDictationLanguage: SupportedDictationLanguage {
        SupportedDictationLanguage(
            rawValue: activeConfiguration.dictationLanguageCode
        ) ?? .english
    }

    var compatibleDictationLanguages: [SupportedDictationLanguage] {
        (
            SpeechModelVariant(
                rawValue: activeConfiguration.modelVersion
            ) ?? .default
        ).supportedLanguages
    }

    var shouldRecommendCanadianEnglish: Bool {
        CanadianEnglishRecommendation.shouldPresent(
            locale: .current,
            dictationLanguageCode: preferences.dictationLanguageCode,
            modelSupportsEnglish: (
                SpeechModelVariant(
                    rawValue: preferences.modelVersion
                ) ?? .default
            ).supports(languageCode: "en"),
            response: preferences.canadianEnglishRecommendation
        )
    }

    var temporaryStyleOverrideID: UUID? {
        expireTemporaryStyleIfNeeded()
        return temporaryStyleID
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

    var effectiveLivePreviewEnabled: Bool {
        activeConfiguration.livePreviewEnabled
            && activeConfiguration.showRecordingHUD
    }

    var effectivePlaySounds: Bool {
        activeConfiguration.playSounds
    }

    var hudCustomizationEnabled: Bool {
        featureFlags.isEnabled(.hudEdgePlacement)
    }

    var pointerInputCapabilityEnabled: Bool {
        featureFlags.isEnabled(.mouseFlow)
    }

    var localTransformsEnabled: Bool {
        featureFlags.isEnabled(.localTransforms)
    }

    var minimalContextCapabilityEnabled: Bool {
        featureFlags.isEnabled(.minimalContext)
    }

    var persistentRecoveryEnabled: Bool {
        featureFlags.isEnabled(.persistentRecovery)
    }

    var scratchpadEnabled: Bool {
        featureFlags.isEnabled(.workspaceV2)
            && featureFlags.isEnabled(.scratchpad)
    }

    var notificationCapabilityEnabled: Bool {
        featureFlags.isEnabled(.notifications)
    }

    var advancedInsightsEnabled: Bool {
        featureFlags.isEnabled(.advancedInsights)
    }

    var localStatusSnapshot: LocalStatusSnapshot {
        let system = SystemCheck()
        let captureStatus: LocalStatusItem
        switch state {
        case .ready:
            captureStatus = .init(
                domain: .capture,
                state: .healthy,
                detail: "Ready"
            )
        case .starting, .recording, .processing:
            captureStatus = .init(
                domain: .capture,
                state: .healthy,
                detail: state.label
            )
        case .failed:
            captureStatus = .init(
                domain: .capture,
                state: .degraded,
                detail: "Needs attention"
            )
        }
        let modelStatus: LocalStatusItem
        switch modelState {
        case .ready:
            modelStatus = .init(
                domain: .model,
                state: .healthy,
                detail: "Validated offline"
            )
        case .preparing, .notChecked:
            modelStatus = .init(
                domain: .model,
                state: .checking,
                detail: modelState.label
            )
        case .failed:
            modelStatus = .init(
                domain: .model,
                state: .unavailable,
                detail: "Local model unavailable"
            )
        }
        let storageFailure = [
            historyError,
            usageInsightsError,
            persistentRecoveryError,
            styleError,
        ].contains { $0 != nil }
        return LocalStatusSnapshot(items: [
            captureStatus,
            modelStatus,
            LocalStatusItem(
                domain: .shortcut,
                state: shortcutRegistrationState == .registered
                    ? .healthy
                    : .unavailable,
                detail: shortcutRegistrationState.rawValue
            ),
            LocalStatusItem(
                domain: .microphone,
                state: system.microphonePermission == "authorized"
                    && audioInputHealth != .disconnected
                    ? .healthy
                    : .unavailable,
                detail: system.microphonePermission == "authorized"
                    ? audioInputHealth.rawValue
                    : system.microphonePermission
            ),
            LocalStatusItem(
                domain: .insertion,
                state: activeConfiguration.outputMode == .clipboard
                    || system.accessibilityPermission
                    ? (pendingTranscript == nil ? .healthy : .degraded)
                    : .unavailable,
                detail: activeConfiguration.outputMode == .clipboard
                    ? "Explicit clipboard output"
                    : (system.accessibilityPermission
                        ? "Accessibility ready"
                        : "Accessibility unavailable")
            ),
            LocalStatusItem(
                domain: .storage,
                state: storageFailure ? .degraded : .healthy,
                detail: storageFailure
                    ? "A local store needs attention"
                    : "Owner-only stores ready"
            ),
            LocalStatusItem(
                domain: .sync,
                state: .notEnabled,
                detail: "Encrypted sync is not configured"
            ),
        ])
    }

    var effectiveHUDPresentationMode: RecordingHUDPresentationMode {
        hudCustomizationEnabled ? preferences.recordingHUDMode : .compact
    }

    var effectiveHUDOpacity: Double {
        hudCustomizationEnabled ? preferences.recordingHUDOpacity : 1
    }

    func setEnabled(_ value: Bool) {
        if !value, isTestingMicrophone {
            stopMicrophoneTest()
        }
        if !value, state == .recording {
            endRecordingActivity()
            stopDurationTimer()
            capture.cancel()
            finishAudioRouteTimeline(as: .cancelled)
            currentAudioDeviceUID = nil
            Task {
                await stopProvisionalPreview()
                await discardPersistentRecoverySpool()
            }
            audioLevel = 0
            state = .ready
        }
        isEnabled = value
    }

    func beginFileTranscription() -> Bool {
        guard
            !isFileTranscriptionActive,
            !isRecordingOrStarting,
            state != .processing,
            !isTestingMicrophone
        else { return false }
        isFileTranscriptionActive = true
        return true
    }

    func endFileTranscription() {
        isFileTranscriptionActive = false
    }

    func beginRecording(
        origin: DictationOrigin = .shortcut,
        viaFunctionKey: Bool = false,
        forTalk: Bool = false
    ) {
        refreshActiveProfile()
        touchTemporaryStyleOverride()
        guard canStartRecording else { return }
        recordingStartedWithFunctionKey = viaFunctionKey
        isTalkRecording = false
        audioInputRMS = 0
        clearCompletionPresentation()
        quickDictationTargetActive = origin == .scratchpad
        let configuration = activeConfiguration
        clearProvisionalPreview()
        currentRevision = nil
        currentRawFinal = nil
        postDictationRedoRevisionID = nil
        recordingElapsed = 0
        durationWarning = nil
        insertionTarget = nil
        commitEnterTarget = nil
        commitEnterExpiresAtUptime = nil
        // Talk answers on its card, so it needs no text field to type into.
        if configuration.outputMode == .type,
           !quickDictationTargetActive,
           !forTalk {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                recordOperationalIssue(.accessibility)
                recordReliability(
                    category: .recordingStart,
                    outcome: .failure
                )
                state = .failed(
                    VoiceError.accessibilityPermissionDenied.localizedDescription
                )
                return
            }
            let target: TextInsertionTarget
            do {
                target = try captureInsertionTarget()
            } catch {
                recordOperationalIssue(.insertion)
                recordReliability(
                    category: .recordingStart,
                    outcome: .failure
                )
                state = .failed(error.localizedDescription)
                return
            }
            insertionTarget = target
        } else {
            insertionTarget = nil
        }
        Self.logger.notice("Push-to-talk pressed; starting audio capture")
        state = .starting
        recordingStartRequestedAt = ProcessInfo.processInfo.systemUptime
        stopWhenStarted = false
        cancelWhenStarted = false
        pendingLifecycleInterruption = nil
        Task {
            do {
                let coordinatorStart = await dictationCoordinator.handle(
                    .start(
                        origin: origin,
                        profile: coordinatorProfile(
                            for: configuration
                        )
                    )
                )
                guard let coordinatorSessionID =
                    coordinatorStart.sessionID
                else {
                    throw VoiceInjectedFailure(
                        category: .capture(.startFailed)
                    )
                }
                self.coordinatorSessionID = coordinatorSessionID
                await startPersistentRecoverySpool(
                    sessionID: coordinatorSessionID
                )
                if configuration.livePreviewEnabled
                    && configuration.showRecordingHUD
                {
                    await startProvisionalPreview()
                }
                try await throwInjectedFailure(at: .captureStart)
                let previewSink = previewAudioContinuation
                let recoverySink = recoveryAudioContinuation
                let audioInputDeviceUID =
                    try resolvedAudioInputDeviceUID()
                currentAudioDeviceUID = audioInputDeviceUID
                audioRouteTimeline = AudioRouteTimeline()
                if let audioInputDeviceUID {
                    audioRouteTimeline.start(
                        deviceUID: audioInputDeviceUID,
                        at: ProcessInfo.processInfo.systemUptime
                    )
                    await updatePersistentRecoveryRouteMetadata()
                }
                try await capture.start(
                    deviceUID: audioInputDeviceUID,
                    onLevel: { [weak self] level in
                        Task { @MainActor [weak self] in
                            self?.observeAudioLevel(level)
                        }
                    },
                    onSamples: { samples, sampleRate in
                        let chunk = PreviewAudioChunk(
                            samples: samples,
                            sampleRate: sampleRate
                        )
                        previewSink?.yield(chunk)
                        if case .dropped = recoverySink?.yield(chunk) {
                            Task { @MainActor [weak self] in
                                self?.recoveryStreamBackpressure = true
                            }
                        }
                    }
                )
                Self.logger.notice("Audio capture started")
                _ = await dictationCoordinator.handle(
                    .captureStarted(coordinatorSessionID)
                )
                recordReliability(
                    category: .recordingStart,
                    outcome: .success,
                    latencyMetric: .recordingStart,
                    startedAt: recordingStartRequestedAt
                )
                recordingStartRequestedAt = nil
                if cancelWhenStarted {
                    cancelWhenStarted = false
                    let discardAudio = discardAudioWhenStarted
                    discardAudioWhenStarted = false
                    let cancelledSamples =
                        capture.cancelRetainingSamples()
                    if !discardAudio, cancelledSamples.count >= Int(
                        AudioCapture.targetSampleRate * 0.1
                    ) {
                        retainAudioRecovery(
                            cancelledSamples,
                            wasCancelled: true
                        )
                    }
                    await stopProvisionalPreview()
                    await discardPersistentRecoverySpool()
                    audioLevel = 0
                    audioHealthMonitor.reset()
                    audioInputHealth = .idle
                    finishAudioRouteTimeline(as: .cancelled)
                    insertionTarget = nil
                    if let pendingLifecycleInterruption {
                        self.pendingLifecycleInterruption = nil
                        state = .failed(pendingLifecycleInterruption)
                    } else {
                        state = .ready
                    }
                } else if stopWhenStarted {
                    stopWhenStarted = false
                    finishStartedRecording()
                } else {
                    state = .recording
                    beginRecordingActivity()
                    startDurationTimer()
                    // Hands-free Talk stays silent: the beep would reach the
                    // microphone it just opened.
                    if activeConfiguration.playSounds, !isTalkHandsFree,
                       !recordingStartedWithFunctionKey
                        || functionKeyHoldConfirmed
                    {
                        NSSound.beep()
                    }
                }
            } catch {
                endRecordingActivity()
                await stopProvisionalPreview()
                await discardPersistentRecoverySpool()
                await reportCoordinatorFailure(error)
                recordReliability(
                    category: .recordingStart,
                    outcome: .failure,
                    latencyMetric: .recordingStart,
                    startedAt: recordingStartRequestedAt
                )
                recordingStartRequestedAt = nil
                audioLevel = 0
                finishAudioRouteTimeline(as: .failed)
                currentAudioDeviceUID = nil
                insertionTarget = nil
                quickDictationTargetActive = false
                recordOperationalIssue(.microphone)
                if error as? AudioInputDeviceError
                    == .selectedDeviceUnavailable {
                    audioHealthMonitor.disconnect()
                    audioInputHealth = .disconnected
                }
                Self.logger.error(
                    "Audio capture failed: \(error.localizedDescription)"
                )
                if let pendingLifecycleInterruption {
                    self.pendingLifecycleInterruption = nil
                    state = .failed(
                        "\(pendingLifecycleInterruption) "
                            + error.localizedDescription
                    )
                } else {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }

    func beginQuickDictationToScratchpad() {
        guard scratchpadEnabled, onQuickDictation != nil else {
            state = .failed("Scratchpad is unavailable.")
            return
        }
        beginRecording(origin: .scratchpad)
    }

    func openScratchpad() {
        guard scratchpadEnabled, let onOpenScratchpad else {
            state = .failed("Scratchpad is unavailable.")
            return
        }
        onOpenScratchpad()
    }

    func finishRecording() {
        if state == .starting {
            stopWhenStarted = true
            return
        }
        guard state == .recording else { return }
        finishStartedRecording()
    }

    func cancelRecording(discardingAudio: Bool = false) {
        if isTalkHandsFree {
            // Cancelling during a hands-free conversation ends it.
            endHandsFreeTalk()
            return
        }
        endTalkRecording()
        if state == .starting {
            stopWhenStarted = false
            cancelWhenStarted = true
            discardAudioWhenStarted = discardingAudio
            Task {
                _ = await dictationCoordinator.handle(.cancel)
            }
            return
        }
        guard state == .recording else { return }
        endRecordingActivity()
        stopDurationTimer()
        let cancelledSamples = capture.cancelRetainingSamples()
        if !discardingAudio, cancelledSamples.count >= Int(
            AudioCapture.targetSampleRate * 0.1
        ) {
            retainAudioRecovery(
                cancelledSamples,
                wasCancelled: true
            )
        }
        finishAudioRouteTimeline(as: .cancelled)
        currentAudioDeviceUID = nil
        Task {
            _ = await dictationCoordinator.handle(.cancel)
        }
        state = .processing
        Task {
            await stopProvisionalPreview()
            await discardPersistentRecoverySpool()
            state = .ready
        }
        recordingStartRequestedAt = nil
        insertionTarget = nil
        quickDictationTargetActive = false
        audioLevel = 0
        audioHealthMonitor.reset()
        audioInputHealth = .idle
    }

    func handleSleepInterruption() {
        let message = "Recording stopped because this Mac went to sleep."
        endRecordingActivity()
        stopDurationTimer()
        Task {
            _ = await dictationCoordinator.handle(
                .handleLifecycleEvent(.sleep)
            )
        }
        recordReliability(
            category: .sessionInterruption,
            outcome: .interrupted
        )
        switch VoiceLifecyclePolicy.action(
            for: .sleep,
            activity: lifecycleActivity
        ) {
        case .cancelAndReport:
            stopWhenStarted = false
            cancelWhenStarted = true
            pendingLifecycleInterruption =
                "\(message) No transcript was inserted."
        case .retainAudioAndReport:
            do {
                let samples = try capture.stop()
                finishAudioRouteTimeline(as: .disconnected)
                currentAudioDeviceUID = nil
                retainAudioRecovery(samples)
                state = .processing
                Task {
                    await stopProvisionalPreview()
                    await completePersistentRecovery(samples)
                    state = .failed(
                        "\(message) Captured audio is available for local retry."
                    )
                }
                insertionTarget = nil
                audioLevel = 0
                audioHealthMonitor.reset()
                audioInputHealth = .idle
            } catch {
                capture.cancel()
                finishAudioRouteTimeline(as: .failed)
                currentAudioDeviceUID = nil
                Task {
                    await stopProvisionalPreview()
                    await discardPersistentRecoverySpool()
                }
                insertionTarget = nil
                audioLevel = 0
                state = .failed(
                    "\(message) No recoverable audio was available: "
                        + error.localizedDescription
                )
            }
        case .none, .restoreRuntimeHandlers, .confirmDiscard:
            break
        }
    }

    func prepareForConfirmedTermination() {
        guard isRecordingOrStarting else { return }
        endRecordingActivity()
        stopDurationTimer()
        Task {
            _ = await dictationCoordinator.handle(
                .handleLifecycleEvent(.terminationConfirmed)
            )
        }
        capture.cancel()
        finishAudioRouteTimeline(as: .cancelled)
        currentAudioDeviceUID = nil
        previewAudioContinuation?.finish()
        previewAudioTask?.cancel()
        recoveryAudioContinuation?.finish()
        recoveryAudioTask?.cancel()
        insertionTarget = nil
        clearProvisionalPreview()
    }

    func refreshActiveProfile() {
        expireTemporaryStyleIfNeeded()
        let bundleIdentifier = NSWorkspace.shared.frontmostApplication?
            .bundleIdentifier
        activeConfiguration = AppProfileResolver.resolve(
            preferences: preferences,
            profiles: appProfiles,
            bundleIdentifier: bundleIdentifier,
            styles: dictationStyles,
            temporaryStyleID: temporaryStyleID
        )
        synchronizeRecognizerWithActiveProfile()
        onChange?()
    }

    func replaceAppProfiles(_ profiles: [AppProfile]) {
        appProfiles = profiles
        profileError = nil
        refreshActiveProfile()
    }

    func setDefaultDictationStyle(_ id: UUID?) {
        preferences.defaultStyleID = id.flatMap { requested in
            dictationStyles.contains { $0.id == requested }
                ? requested
                : nil
        }
        persist()
    }

    func setTemporaryDictationStyle(_ id: UUID?) {
        temporaryStyleID = id.flatMap { requested in
            dictationStyles.contains { $0.id == requested }
                ? requested
                : nil
        }
        temporaryStyleExpiresAtUptime = temporaryStyleID == nil
            ? nil
            : ProcessInfo.processInfo.systemUptime
                + TemporaryStylePolicy.inactivityExpiration
        refreshActiveProfile()
    }

    func saveCustomDictationStyles(
        _ styles: [DictationStylePreset]
    ) {
        do {
            try dictationStyleStore.save(styles)
            customDictationStyles = styles
            styleError = nil
            refreshActiveProfile()
        } catch {
            styleError =
                "Dictation styles could not be saved: \(error.localizedDescription)"
            onChange?()
        }
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
        guard modelState != .preparing else {
            modelPreparationPresentation = .foreground
            return
        }
        startModelPreparation(repair: false, presentation: .foreground)
    }

    func warmLocalModel() {
        startModelPreparation(repair: false, presentation: .background)
    }

    func repairLocalModel() {
        startModelPreparation(repair: true, presentation: .foreground)
    }

    func cancelModelPreparation() {
        modelTask?.cancel()
        modelTask = nil
        modelOperationID = nil
        modelProgress = 0
        modelPhase = nil
        modelPreparationPresentation = .background
        modelState = .notChecked
    }

    func validateLocalModel() {
        guard modelState != .preparing else {
            modelPreparationPresentation = .foreground
            return
        }
        modelPreparationPresentation = .foreground
        modelPhase = .validating
        modelState = .preparing
        Task {
            do {
                try await throwInjectedFailure(at: .modelValidation)
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
                recordReliability(
                    category: .modelValidation,
                    outcome: .success
                )
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
            refreshActiveProfile()
            prepareLocalModel()
        } else {
            persist()
            refreshActiveProfile()
        }
    }

    func setEnglishSpellingPolicy(_ policy: EnglishSpellingPolicy) {
        guard !isRecordingOrStarting, state != .processing else { return }
        preferences.englishSpellingPolicy = policy
        persist()
    }

    func acceptCanadianEnglishRecommendation() {
        guard shouldRecommendCanadianEnglish else { return }
        preferences.englishSpellingPolicy = .canadian
        preferences.canadianEnglishRecommendation = .accepted
        persist()
    }

    func dismissCanadianEnglishRecommendation() {
        guard shouldRecommendCanadianEnglish else { return }
        preferences.canadianEnglishRecommendation = .dismissed
        persist()
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
        endRecordingActivity()
        stopDurationTimer()
        audioLevel = 0
        state = .processing
        Task {
            do {
                _ = await dictationCoordinator.handle(.stop)
                let samples = try capture.stop()
                let capturedDeviceUID = currentAudioDeviceUID
                finishAudioRouteTimeline(as: .finalized)
                currentAudioDeviceUID = nil
                await stopProvisionalPreview()
                retainAudioRecovery(samples)
                await completePersistentRecovery(samples)
                Self.logger.notice(
                    "Audio capture stopped with \(samples.count) local samples"
                )
                if CapturedAudioLevel.isSilent(samples) {
                    throw VoiceError.silentRecording(
                        AudioInputDevices.name(forUID: capturedDeviceUID)
                            ?? audioInputName
                    )
                }
                try await transcribeAndCommit(
                    samples: samples,
                    target: insertionTarget
                )
            } catch {
                await stopProvisionalPreview()
                await reportCoordinatorFailure(error)
                insertionTarget = nil
                if isTalkHandsFree, VoiceSession.isNoSpeech(error) {
                    discardAudioRecovery()
                    await resolvePersistentRecovery(as: .discarded)
                    if resumeHandsFreeAfterEmptyTurn() { return }
                }
                endHandsFreeTalk()
                endTalkRecording()
                if !FailedCaptureRecoveryPolicy.retainsAudio(after: error) {
                    discardAudioRecovery()
                    await resolvePersistentRecovery(as: .discarded)
                }
                if case .failed = modelState {
                    // Model preparation records its own finite issue category.
                } else {
                    recordOperationalIssue(
                        pendingTranscript == nil ? .transcription : .insertion
                    )
                }
                Self.logger.error(
                    "Dictation failed: \(error.localizedDescription)"
                )
                state = .failed(error.localizedDescription)
                emitNotification(
                    VoiceNotificationEvent(
                        category: .failures,
                        title: "Dictation needs attention",
                        body:
                            "The final transcript or recovery action remains available in Autohand Voice.",
                        deduplicationKey:
                            "dictation.failure.\(failureCategory(for: error).code)"
                    )
                )
            }
        }
    }

    private func startProvisionalPreview() async {
        do {
            try await recognizer.startProvisionalPreview {
                [weak self] transcript in
                Task { @MainActor [weak self] in
                    self?.receiveProvisionalTranscript(transcript)
                }
            }
            let (stream, continuation) =
                AsyncStream<PreviewAudioChunk>.makeStream(
                    bufferingPolicy: .bufferingNewest(64)
                )
            previewAudioContinuation = continuation
            previewAudioTask = Task { [weak self] in
                guard let self else { return }
                for await chunk in stream {
                    guard !Task.isCancelled else { return }
                    await self.recognizer.appendProvisionalSamples(
                        chunk.samples,
                        sampleRate: chunk.sampleRate
                    )
                }
            }
            provisionalPreviewNotice = nil
        } catch {
            provisionalPreviewNotice =
                "Live preview unavailable: \(error.localizedDescription)"
            Self.logger.error(
                "Provisional preview failed; final local transcription remains available: \(error.localizedDescription)"
            )
        }
    }

    private func stopProvisionalPreview() async {
        previewAudioContinuation?.finish()
        previewAudioContinuation = nil
        let audioTask = previewAudioTask
        audioTask?.cancel()
        previewAudioTask = nil
        _ = await audioTask?.result
        await recognizer.stopProvisionalPreview()
        clearProvisionalPreview()
    }

    private func receiveProvisionalTranscript(_ transcript: Transcript) {
        guard transcript.phase == .provisional, state == .recording else {
            return
        }
        previewBuffer.update(transcript.text)
        provisionalTranscript = previewBuffer.transcript?.text
    }

    private func clearProvisionalPreview() {
        previewBuffer.clear()
        provisionalTranscript = nil
    }

    func recover() {
        guard case .failed = state else { return }
        audioLevel = 0
        state = .ready
    }

    func reportFailure(
        _ message: String,
        kind: OperationalIssueKind = .runtime
    ) {
        recordOperationalIssue(kind)
        state = .failed(message)
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    var canCopyFinalFromHUD: Bool {
        guard
            lastTranscript != nil,
            let completionExpiresAtUptime
        else { return false }
        return completionExpiresAtUptime
            > ProcessInfo.processInfo.systemUptime
    }

    var recordingHUDIdlePresentation: RecordingHUDIdlePresentation {
        .resolve(
            canCopyFinal: canCopyFinalFromHUD,
            hasRecoverableAudio: hasRecoverableAudio,
            recoveryWasCancelled: recoverableAudioWasCancelled
        )
    }

    func copyFinalFromHUD() {
        guard canCopyFinalFromHUD else { return }
        let text = currentRevision?.text ?? lastTranscript
        guard let text else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            text,
            forType: .string
        )
        completionPresentation = "Selected revision copied"
    }

    func dismissCompletionHUD() {
        clearCompletionPresentation()
    }

    var canUndoPostDictationRevision: Bool {
        canCopyFinalFromHUD && currentRevision?.parentID != nil
    }

    var canRedoPostDictationRevision: Bool {
        canCopyFinalFromHUD
            && currentRevision != nil
            && postDictationRedoRevisionID != nil
    }

    func undoPostDictationRevision() {
        guard
            canUndoPostDictationRevision,
            let revision = currentRevision
        else { return }
        Task {
            do {
                currentRevision = try await revisionEngine.undo(
                    revision.id
                )
                postDictationRedoRevisionID = revision.id
                completionPresentation =
                    "Earlier revision selected — Copy Final to use it"
            } catch {
                completionPresentation = error.localizedDescription
            }
        }
    }

    func redoPostDictationRevision() {
        guard
            canRedoPostDictationRevision,
            let revision = currentRevision,
            let expectedID = postDictationRedoRevisionID
        else { return }
        Task {
            do {
                let redone = try await revisionEngine.redo(revision.id)
                guard redone.id == expectedID else {
                    throw RevisionError.noRedoRevision
                }
                currentRevision = redone
                postDictationRedoRevisionID = nil
                completionPresentation =
                    "Later revision selected — Copy Final to use it"
            } catch {
                completionPresentation = error.localizedDescription
            }
        }
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
        let insertionStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                throw VoiceError.accessibilityPermissionDenied
            }
            let target = try captureInsertionTarget()
            try inserter.commitVerifiedFinalText(
                pendingTranscript,
                mode: .type,
                target: target
            )
            armExplicitEnter(target)
            lastTranscript = pendingTranscript
            updateHistoryOutcome(.inserted)
            markPendingUsageInsertionSucceeded()
            self.pendingTranscript = nil
            state = .ready
            presentCompletion("Inserted at the current cursor")
            recordReliability(
                category: .insertion,
                outcome: .success,
                latencyMetric: .insertion,
                startedAt: insertionStartedAt
            )
            Task {
                await recordCoordinatorInsertionRetry(
                    outcome: .inserted
                )
            }
        } catch {
            updateHistoryOutcome(
                .insertionFailed,
                failureCategory: failureCategory(for: error)
            )
            recordOperationalIssue(.insertion)
            recordReliability(
                category: .insertion,
                outcome: .failure,
                latencyMetric: .insertion,
                startedAt: insertionStartedAt
            )
            Task {
                await recordCoordinatorInsertionRetry(error: error)
            }
            state = .failed(error.localizedDescription)
        }
    }

    func retryHistoryEntryHere(_ entry: HistoryEntry) {
        guard
            entry.outcome == .insertionFailed,
            !isRecordingOrStarting,
            state != .processing
        else { return }
        let insertionStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                throw VoiceError.accessibilityPermissionDenied
            }
            let target = try captureInsertionTarget()
            try inserter.commitVerifiedFinalText(
                entry.text,
                mode: .type,
                target: target
            )
            armExplicitEnter(target)
            try historyStore.updateOutcome(
                id: entry.id,
                outcome: .inserted
            )
            lastTranscript = entry.text
            currentRawFinal = entry.rawFinal
            currentRevision = entry.revision
            historyError = nil
            state = .ready
            presentCompletion("Inserted at the current cursor")
            onHistoryChange?()
            recordReliability(
                category: .insertion,
                outcome: .success,
                latencyMetric: .insertion,
                startedAt: insertionStartedAt
            )
        } catch {
            let category = failureCategory(for: error)
            do {
                try historyStore.updateOutcome(
                    id: entry.id,
                    outcome: .insertionFailed,
                    failureCategory: category
                )
            } catch {
                historyError =
                    "Could not update local history: \(error.localizedDescription)"
            }
            recordOperationalIssue(.insertion)
            recordReliability(
                category: .insertion,
                outcome: .failure,
                latencyMetric: .insertion,
                startedAt: insertionStartedAt
            )
            state = .failed(error.localizedDescription)
            onHistoryChange?()
        }
    }

    func copyPendingTranscript() {
        guard let pendingTranscript else { return }
        let insertionStartedAt = ProcessInfo.processInfo.systemUptime
        do {
            try inserter.commitVerifiedFinalText(
                pendingTranscript,
                mode: .clipboard
            )
            commitEnterTarget = nil
            commitEnterExpiresAtUptime = nil
            lastTranscript = pendingTranscript
            updateHistoryOutcome(.inserted)
            self.pendingTranscript = nil
            state = .ready
            presentCompletion("Copied to the clipboard")
            recordReliability(
                category: .insertion,
                outcome: .success,
                latencyMetric: .insertion,
                startedAt: insertionStartedAt
            )
            Task {
                await recordCoordinatorInsertionRetry(
                    outcome: .copied
                )
            }
        } catch {
            updateHistoryOutcome(
                .insertionFailed,
                failureCategory: failureCategory(for: error)
            )
            recordOperationalIssue(.insertion)
            recordReliability(
                category: .insertion,
                outcome: .failure,
                latencyMetric: .insertion,
                startedAt: insertionStartedAt
            )
            Task {
                await recordCoordinatorInsertionRetry(error: error)
            }
            state = .failed(error.localizedDescription)
        }
    }

    func discardPendingTranscript() {
        historyEntryID = nil
        pendingTranscript = nil
        insertionTarget = nil
        quickDictationTargetActive = false
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
            let currentTarget: TextInsertionTarget
            do {
                currentTarget = try captureInsertionTarget()
            } catch {
                state = .failed(error.localizedDescription)
                return
            }
            target = currentTarget
        } else {
            target = nil
        }

        state = .processing
        Task {
            do {
                let retrySnapshot = await dictationCoordinator.handle(
                    .retryRecovery
                )
                if let sessionID = retrySnapshot.sessionID {
                    coordinatorSessionID = sessionID
                }
                try await transcribeAndCommit(samples: samples, target: target)
            } catch {
                await reportCoordinatorFailure(error)
                if !FailedCaptureRecoveryPolicy.retainsAudio(after: error) {
                    discardAudioRecovery()
                }
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
        if let uid {
            preferences.audioInputDevicePriority =
                [uid]
                + preferences.audioInputDevicePriority.filter {
                    $0 != uid
                }
        } else {
            preferences.audioInputDevicePriority = []
        }
        audioHealthMonitor.reset()
        audioInputHealth = .idle
        persist()
    }

    func setAudioInputPriority(_ deviceUIDs: [String]) {
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: deviceUIDs,
            automaticHandoffEnabled:
                preferences.automaticAudioHandoffEnabled
        )
        preferences.audioInputDevicePriority = policy.rankedDeviceUIDs
        preferences.audioInputDeviceUID = policy.rankedDeviceUIDs.first
        persist()
    }

    func setAutomaticAudioHandoff(_ enabled: Bool) {
        preferences.automaticAudioHandoffEnabled = enabled
        persist()
    }

    func setRecordingHUDMode(_ mode: RecordingHUDPresentationMode) {
        preferences.recordingHUDMode = mode
        persist()
    }

    func setRecordingHUDOpacity(_ opacity: Double) {
        preferences.recordingHUDOpacity = min(max(opacity, 0.2), 1)
        persist()
    }

    func recordingHUDPlacement(
        for displayID: String
    ) -> RecordingHUDDisplayPreference {
        guard hudCustomizationEnabled else {
            return RecordingHUDDisplayPreference(
                displayID: displayID,
                anchor: .bottom,
                offset: .zero
            )
        }
        return preferences.recordingHUDPlacements.first {
            $0.displayID == displayID
        } ?? RecordingHUDDisplayPreference(
            displayID: displayID,
            anchor: .bottom,
            offset: .zero
        )
    }

    func setRecordingHUDPlacement(
        _ placement: RecordingHUDDisplayPreference
    ) {
        guard hudCustomizationEnabled else { return }
        let otherDisplays = preferences.recordingHUDPlacements.filter {
            $0.displayID != placement.displayID
        }
        let sanitized = RecordingHUDPreferences(
            mode: preferences.recordingHUDMode,
            opacity: preferences.recordingHUDOpacity,
            displays: [placement] + otherDisplays
        )
        preferences.recordingHUDPlacements = sanitized.displays
        persist()
    }

    func reportAudioInputDisconnected() {
        guard state != .recording else { return }
        let wasDisconnected = audioInputHealth == .disconnected
        audioHealthMonitor.disconnect()
        audioInputHealth = .disconnected
        if !wasDisconnected {
            recordOperationalIssue(.microphone)
        }
    }

    func reportAudioInputAvailable(name: String) {
        audioInputName = name
        guard !isTestingMicrophone, state != .recording else { return }
        audioHealthMonitor.reset()
        audioInputHealth = .idle
    }

    func handleAudioInputDevicesChanged(
        _ devices: [AudioInputDevice]
    ) {
        guard
            state == .recording,
            !audioHandoffInProgress,
            let currentAudioDeviceUID
        else { return }
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: preferences.audioInputDevicePriority,
            automaticHandoffEnabled:
                preferences.automaticAudioHandoffEnabled
        )
        switch policy.resolveHandoff(
            currentDeviceUID: currentAudioDeviceUID,
            devices: devices,
            clamshellClosed:
                clamshellStateChecker.isClamshellClosed()
        ) {
        case let .selected(selection):
            guard selection.requiresSegmentBoundary else { return }
            audioHandoffInProgress = true
            do {
                try capture.handoff(to: selection.deviceUID)
                let now = ProcessInfo.processInfo.systemUptime
                audioRouteTimeline.handoff(
                    to: selection.deviceUID,
                    at: now
                )
                self.currentAudioDeviceUID = selection.deviceUID
                audioInputName = devices.first {
                    $0.id == selection.deviceUID
                }?.name ?? "Replacement microphone"
                audioHealthMonitor.reset()
                audioInputHealth = .listening
                audioHandoffInProgress = false
                Task {
                    await updatePersistentRecoveryRouteMetadata()
                }
            } catch {
                audioHandoffInProgress = false
                failActiveAudioRoute(
                    .handoffFailed,
                    detail: error.localizedDescription
                )
            }
        case let .unavailable(failure):
            failActiveAudioRoute(
                failure,
                detail:
                    "The active microphone disappeared and no eligible replacement was available."
            )
        }
    }

    private func failActiveAudioRoute(
        _ failure: AudioRouteFailure,
        detail: String
    ) {
        guard state == .recording else { return }
        endRecordingActivity()
        stopDurationTimer()
        audioHealthMonitor.disconnect()
        audioInputHealth = .disconnected
        state = .processing
        Task {
            let injected = VoiceInjectedFailure(
                category: .audioRoute(failure)
            )
            do {
                let samples = try capture.stop()
                finishAudioRouteTimeline(as: .disconnected)
                currentAudioDeviceUID = nil
                await stopProvisionalPreview()
                retainAudioRecovery(samples)
                await completePersistentRecovery(samples)
                await reportCoordinatorFailure(injected)
                recordOperationalIssue(.microphone)
                state = .failed(
                    "Microphone handoff failed. \(detail) "
                        + "Captured audio is available for local retry."
                )
            } catch {
                capture.cancel()
                finishAudioRouteTimeline(as: .failed)
                currentAudioDeviceUID = nil
                await stopProvisionalPreview()
                await discardPersistentRecoverySpool()
                await reportCoordinatorFailure(injected)
                recordOperationalIssue(.microphone)
                state = .failed(
                    "Microphone handoff failed and no recoverable audio "
                        + "was available: \(error.localizedDescription)"
                )
            }
        }
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
                recordOperationalIssue(.microphone)
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
            shortcutRegistrationState = .unavailable
            recordOperationalIssue(.shortcut)
            state = .failed("Choose a valid shortcut with at least one modifier.")
            return false
        }
        var updatedBindings = preferences.inputBindings.filter {
            if case .keyboard = $0.trigger {
                return $0.action != .startStop
            }
            return true
        }
        updatedBindings.insert(
            InputBinding(
                action: .startStop,
                trigger: .keyboard(shortcut)
            ),
            at: 0
        )
        guard
            let inputConfiguration = try? InputConfiguration(
                bindings: updatedBindings
            )
        else {
            inputBindingError =
                "That shortcut conflicts with another Autohand Voice binding."
            return false
        }
        let status = onShortcutRegistration?(shortcut) ?? noErr
        guard status == noErr else {
            shortcutFailureActive = true
            shortcutRegistrationState = .unavailable
            recordOperationalIssue(.shortcut)
            state = .failed(
                "That shortcut is unavailable (registration error \(status))."
            )
            return false
        }
        shortcutRegistrationState = .registered
        preferences.shortcut = shortcut
        preferences.inputBindings = inputConfiguration.bindings
        if shortcutFailureActive {
            shortcutFailureActive = false
            state = .ready
        }
        persist()
        return true
    }

    @discardableResult
    func setScratchpadShortcut(_ shortcut: RegisteredShortcut) -> Bool {
        guard scratchpadEnabled, shortcut.isValid else { return false }
        guard !preferences.inputBindings.contains(where: {
            $0.trigger == .keyboard(shortcut)
        }) else {
            scratchpadShortcutError =
                "That shortcut is already assigned to dictation."
            return false
        }
        let status = onScratchpadShortcutRegistration?(shortcut) ?? noErr
        guard status == noErr else {
            scratchpadShortcutError =
                "Scratchpad shortcut is unavailable (error \(status))."
            recordOperationalIssue(.shortcut)
            onChange?()
            return false
        }
        preferences.scratchpadShortcut = shortcut
        scratchpadShortcutError = nil
        persist()
        return true
    }

    func keyboardBinding(
        for action: InputBindingAction
    ) -> RegisteredShortcut? {
        preferences.inputBindings.compactMap { binding in
            guard
                binding.action == action,
                case let .keyboard(shortcut) = binding.trigger
            else { return nil }
            return shortcut
        }.first
    }

    @discardableResult
    func setKeyboardBinding(
        _ shortcut: RegisteredShortcut?,
        for action: InputBindingAction
    ) -> Bool {
        if action == .startStop, let shortcut {
            return setShortcut(shortcut)
        }
        guard action != .startStop else { return false }
        if let shortcut,
           scratchpadEnabled,
           shortcut == preferences.scratchpadShortcut {
            inputBindingError =
                "That shortcut is already assigned to Scratchpad."
            return false
        }
        var bindings = preferences.inputBindings.filter { binding in
            guard case .keyboard = binding.trigger else { return true }
            return binding.action != action
        }
        if let shortcut {
            bindings.append(
                InputBinding(
                    action: action,
                    trigger: .keyboard(shortcut)
                )
            )
        }
        do {
            let configuration = try InputConfiguration(
                bindings: bindings
            )
            let status = onInputBindingsRegistration?(
                configuration.bindings
            ) ?? noErr
            guard status == noErr else {
                inputBindingError =
                    "That keyboard binding is unavailable "
                        + "(registration error \(status))."
                return false
            }
            preferences.inputBindings = configuration.bindings
            inputBindingReducer = InputBindingReducer()
            inputBindingError = nil
            persist()
            return true
        } catch {
            inputBindingError = error.localizedDescription
            return false
        }
    }

    func setPointerMonitoringEnabled(_ enabled: Bool) {
        guard pointerInputCapabilityEnabled else { return }
        if !enabled {
            _ = onPointerMonitoringChange?(false, false)
            preferences.pointerMonitoringEnabled = false
            pointerInputStatus = "Off"
            observedPointerButton = nil
            inputBindingReducer = InputBindingReducer()
            persist()
            return
        }
        let result = onPointerMonitoringChange?(true, true)
            ?? .unavailable
        switch result {
        case .started:
            preferences.pointerMonitoringEnabled = true
            pointerInputStatus =
                "Listening for a compatible extra mouse button"
            inputBindingError = nil
            persist()
        case .permissionDenied:
            preferences.pointerMonitoringEnabled = false
            pointerInputStatus =
                "Input Monitoring permission was denied. Keyboard shortcuts remain available."
            inputBindingError = pointerInputStatus
            recordOperationalIssue(.shortcut)
        case .unavailable:
            preferences.pointerMonitoringEnabled = false
            pointerInputStatus =
                "Pointer monitoring is unavailable. Keyboard shortcuts remain available."
            inputBindingError = pointerInputStatus
            recordOperationalIssue(.shortcut)
        }
    }

    func restorePointerMonitoringAfterLifecycleChange() {
        guard
            pointerInputCapabilityEnabled,
            preferences.pointerMonitoringEnabled
        else { return }
        let result = onPointerMonitoringChange?(true, false)
            ?? .unavailable
        if result == .started {
            pointerInputStatus =
                "Listening for a compatible extra mouse button"
            inputBindingError = nil
        } else {
            pointerInputStatus =
                "Input Monitoring permission is unavailable. Keyboard shortcuts remain available."
            inputBindingError = pointerInputStatus
            recordOperationalIssue(.shortcut)
        }
    }

    func setFunctionKeyLongPressEnabled(_ enabled: Bool) {
        if !enabled {
            _ = onFunctionKeyMonitoringChange?(false, false)
            preferences.functionKeyLongPressEnabled = false
            functionKeyLongPressStatus = "Off"
            persist()
            return
        }

        let result = onFunctionKeyMonitoringChange?(true, true)
            ?? .unavailable
        switch result {
        case .started:
            preferences.functionKeyLongPressEnabled = true
            functionKeyLongPressStatus =
                "On — hold Fn for 0.4 seconds, then release to finish"
            inputBindingError = nil
            persist()
        case .permissionDenied:
            preferences.functionKeyLongPressEnabled = false
            functionKeyLongPressStatus =
                "Accessibility or Input Monitoring permission is required for global Fn detection."
            inputBindingError = functionKeyLongPressStatus
            recordOperationalIssue(.shortcut)
        case .unavailable:
            preferences.functionKeyLongPressEnabled = false
            functionKeyLongPressStatus =
                "Long-press Fn monitoring is unavailable. The keyboard shortcut remains available."
            inputBindingError = functionKeyLongPressStatus
            recordOperationalIssue(.shortcut)
        }
    }

    func restoreFunctionKeyMonitoringAfterLifecycleChange(
        requestPermission: Bool = false
    ) {
        guard preferences.functionKeyLongPressEnabled else {
            functionKeyLongPressStatus = "Off"
            return
        }
        let result = onFunctionKeyMonitoringChange?(
            true,
            requestPermission
        )
            ?? .unavailable
        switch result {
        case .started:
            functionKeyLongPressStatus =
                "On — hold Fn for 0.4 seconds, then release to finish"
            inputBindingError = nil
        case .permissionDenied:
            functionKeyLongPressStatus =
                "Accessibility or Input Monitoring permission is unavailable. Control–Option–Space remains available."
            inputBindingError = functionKeyLongPressStatus
            recordOperationalIssue(.shortcut)
        case .unavailable:
            functionKeyLongPressStatus =
                "Long-press Fn monitoring is unavailable. Control–Option–Space remains available."
            inputBindingError = functionKeyLongPressStatus
            recordOperationalIssue(.shortcut)
        }
    }

    func observeCompatiblePointerButton(_ button: Int) {
        guard
            preferences.pointerMonitoringEnabled,
            button > 1,
            button <= InputConfiguration.maximumPointerButton
        else { return }
        observedPointerButton = button
        let bound = preferences.inputBindings.first {
            $0.trigger == .pointer(button: button)
        }
        pointerInputStatus = bound.map {
            "Mouse button \(button + 1) is bound to "
                + $0.action.displayName
        } ?? "Mouse button \(button + 1) detected. Choose an action."
    }

    func reportExtraPointerDeviceAvailability(_ available: Bool) {
        guard
            pointerInputCapabilityEnabled,
            preferences.pointerMonitoringEnabled,
            preferences.inputBindings.contains(where: {
                if case .pointer = $0.trigger {
                    return true
                }
                return false
            })
        else { return }
        pointerInputStatus = available
            ? "On"
            : "Configured pointer is disconnected; keyboard control remains available."
    }

    func bindObservedPointerButton(
        to action: InputBindingAction
    ) {
        guard let observedPointerButton else { return }
        var bindings = preferences.inputBindings.filter {
            $0.trigger != .pointer(button: observedPointerButton)
        }
        bindings.append(
            InputBinding(
                action: action,
                trigger: .pointer(button: observedPointerButton)
            )
        )
        do {
            let configuration = try InputConfiguration(
                bindings: bindings
            )
            preferences.inputBindings = configuration.bindings
            inputBindingError = nil
            pointerInputStatus =
                "Mouse button \(observedPointerButton + 1) is bound to "
                    + action.displayName
            persist()
        } catch {
            inputBindingError = error.localizedDescription
        }
    }

    func removePointerBinding(_ button: Int) {
        preferences.inputBindings.removeAll {
            $0.trigger == .pointer(button: button)
        }
        inputBindingReducer = InputBindingReducer()
        inputBindingError = nil
        pointerInputStatus =
            preferences.pointerMonitoringEnabled
                ? "Listening for a compatible extra mouse button"
                : "Off"
        persist()
    }

    func handlePointerInput(
        button: Int,
        event: InputTriggerEvent
    ) {
        guard
            pointerInputCapabilityEnabled,
            preferences.pointerMonitoringEnabled,
            let binding = preferences.inputBindings.first(where: {
                $0.trigger == .pointer(button: button)
            })
        else { return }
        let intent = inputBindingReducer.reduce(
            event,
            binding: binding
        )
        performInputIntent(intent, origin: .pointer)
    }

    func handleKeyboardInput(
        shortcut: RegisteredShortcut,
        event: InputTriggerEvent
    ) {
        guard
            let binding = preferences.inputBindings.first(where: {
                $0.trigger == .keyboard(shortcut)
                    && $0.action != .startStop
            })
        else { return }
        let intent = inputBindingReducer.reduce(
            event,
            binding: binding
        )
        performInputIntent(intent, origin: .shortcut)
    }

    /// Fn is hold-to-talk. Capture starts on press; Fn intents only act on a
    /// recording that Fn itself started. Fn+Shift asks Fantail; Command, or
    /// the Hands-Free recording mode, makes it a hands-free conversation,
    /// and pressing Fn again ends that conversation.
    func handleFunctionKeyIntent(
        _ intent: FunctionKeyIntent,
        modifiers: FunctionKeyModifiers = FunctionKeyModifiers()
    ) {
        guard preferences.functionKeyLongPressEnabled else { return }
        if intent == .start {
            functionKeyPressHandledByTalk = false
            if isTalkHandsFree {
                functionKeyPressHandledByTalk = true
                endHandsFreeTalk()
                return
            }
            if TalkTrigger.resolve(
                shift: modifiers.shift,
                command: modifiers.command,
                recordingMode: activeConfiguration.recordingMode,
                talkEnabled: isTalkAvailable
            ) == .handsFreeTalk, !isRecordingOrStarting {
                functionKeyPressHandledByTalk = true
                startHandsFreeTalk()
                return
            }
        } else if functionKeyPressHandledByTalk {
            if intent != .confirmHold {
                functionKeyPressHandledByTalk = false
            }
            return
        }
        let withShift = modifiers.shift
        switch intent {
        case .none:
            break
        case .start:
            functionKeyHoldConfirmed = false
            beginRecording(
                origin: .shortcut,
                viaFunctionKey: true,
                forTalk: withShift && isTalkAvailable
            )
        case .confirmHold:
            guard recordingStartedWithFunctionKey, isRecordingOrStarting
            else { return }
            functionKeyHoldConfirmed = true
            markTalkRecordingIfNeeded(withShift)
            if state == .recording, activeConfiguration.playSounds {
                NSSound.beep()
            }
        case .finish:
            guard recordingStartedWithFunctionKey else { return }
            markTalkRecordingIfNeeded(withShift)
            finishRecording()
        case .discard:
            guard recordingStartedWithFunctionKey else { return }
            cancelRecording(discardingAudio: true)
        case .cancel:
            guard recordingStartedWithFunctionKey else { return }
            cancelRecording()
        }
    }

    private func markTalkRecordingIfNeeded(_ withShift: Bool) {
        guard
            withShift,
            isTalkAvailable,
            !isTalkRecording,
            !quickDictationTargetActive
        else { return }
        isTalkRecording = true
        talk.beginListening()
    }

    private func endTalkRecording() {
        guard isTalkRecording else { return }
        isTalkRecording = false
        talk.cancelListening()
    }

    // MARK: - Hands-free Talk

    func startHandsFreeTalk() {
        guard isTalkAvailable, !isTalkHandsFree else { return }
        isTalkHandsFree = true
        handsFreeEmptyTurns = 0
        handsFreeAssembler.reset()
        handsFreeTranscribing = false
        handsFreeModelWaitStarted = nil
        // Measure this room afresh; a level from another time can mislead.
        handsFreeNoiseFloorDB = nil
        Self.logger.notice("Hands-free Talk started")
        talk.beginHandsFree()
        listenForNextTalkTurn()
        onChange?()
    }

    /// Ends the hands-free loop; the conversation stays on the card.
    func endHandsFreeTalk() {
        guard isTalkHandsFree else { return }
        isTalkHandsFree = false
        handsFreeAssembler.reset()
        Self.logger.notice("Hands-free Talk ended")
        handsFreeResumeTask?.cancel()
        handsFreeResumeTask = nil
        // Put the last reply back on the card first; cancelling the recording
        // would otherwise reset Talk to idle and hide Copy Conversation.
        talk.endHandsFree()
        if isRecordingOrStarting {
            cancelRecording(discardingAudio: true)
        }
        onChange?()
    }

    private func listenForNextTalkTurn() {
        guard isTalkHandsFree, state == .ready || isFailedState else {
            return
        }
        if isFailedState { state = .ready }
        // Right after launch the speech model may still be loading; wait for
        // it (up to a minute) instead of giving up.
        if !canStartRecording, modelState != .ready,
           handsFreeModelWaitStarted.map({
               ProcessInfo.processInfo.systemUptime - $0 < 60
           }) ?? true
        {
            if handsFreeModelWaitStarted == nil {
                handsFreeModelWaitStarted = ProcessInfo.processInfo.systemUptime
            }
            handsFreeResumeTask?.cancel()
            handsFreeResumeTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, self.isTalkHandsFree else {
                    return
                }
                self.handsFreeResumeTask = nil
                self.listenForNextTalkTurn()
            }
            return
        }
        handsFreeModelWaitStarted = nil
        beginRecording(origin: .shortcut, forTalk: true)
        guard isRecordingOrStarting else {
            Self.logger.error(
                "Hands-free Talk could not start: enabled \(self.isEnabled, privacy: .public), model \(String(describing: self.modelState), privacy: .public), recoverable \(self.hasRecoverableAudio, privacy: .public), checking recovery \(self.isCheckingPersistentRecovery, privacy: .public), pending recovery \(self.persistentRecoverySummaries.count, privacy: .public), file \(self.isFileTranscriptionActive, privacy: .public), testing mic \(self.isTestingMicrophone, privacy: .public)"
            )
            endHandsFreeTalk()
            if state == .ready {
                reportFailure(
                    "Talk couldn't start listening. Wait for the speech model to finish loading, then try again."
                )
            }
            return
        }
        handsFreeEndpointer = TalkEndpointer(
            noiseFloorDB: handsFreeNoiseFloorDB
        )
        handsFreeLastDecision = nil
        isTalkRecording = true
        talk.beginListening()
    }

    static func isNoSpeech(_ error: Error) -> Bool {
        switch error as? VoiceError {
        case .emptyTranscript, .silentRecording: true
        default: false
        }
    }

    private var isFailedState: Bool {
        if case .failed = state { return true }
        return false
    }

    /// The reply finished. Listen again after a short beat so the end of the
    /// voice is not picked up by the microphone.
    private func talkTurnEnded(keepListening: Bool) {
        guard isTalkHandsFree else { return }
        guard keepListening else {
            endHandsFreeTalk()
            return
        }
        handsFreeResumeTask?.cancel()
        handsFreeResumeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.isTalkHandsFree else {
                return
            }
            self.handsFreeResumeTask = nil
            self.listenForNextTalkTurn()
        }
    }

    private func observeHandsFreeLevel(_ level: Float) {
        guard isTalkHandsFree, isTalkRecording, state == .recording else {
            return
        }
        let decision = handsFreeEndpointer.observe(
            rms: level,
            at: ProcessInfo.processInfo.systemUptime
        )
        handsFreeNoiseFloorDB = handsFreeEndpointer.noiseFloorDB
        if decision != handsFreeLastDecision {
            handsFreeLastDecision = decision
            let floor = handsFreeNoiseFloorDB ?? .nan
            Self.logger.notice(
                "Hands-free turn: \(String(describing: decision), privacy: .public), room \(floor, format: .fixed(precision: 1), privacy: .public) dB"
            )
        }
        switch decision {
        case .endOfTurn:
            handsFreeTurnEnded()
        case .idleTimeout:
            endHandsFreeTalk()
        case .waiting, .speaking:
            break
        }
    }

    /// Hands a finished piece of speech to transcription while the microphone
    /// keeps listening, so nothing said in the meantime is lost. Listening
    /// stops only once there is a real question to send.
    private func handsFreeTurnEnded() {
        guard !handsFreeTranscribing, handsFreeEndpointer.hasHeardSpeech else {
            return
        }
        let samples = capture.takeSamples()
        handsFreeTranscribing = true
        handsFreeEndpointer = TalkEndpointer(noiseFloorDB: handsFreeNoiseFloorDB)
        handsFreeLastDecision = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            let text = await self.transcribeTalkPiece(samples)
            self.handsFreeTranscribing = false
            guard self.isTalkHandsFree, self.isTalkRecording,
                  self.state == .recording
            else { return }
            switch self.handsFreeAssembler.transcribed(
                text,
                stillTalking: self.handsFreeEndpointer.hasHeardSpeech
            ) {
            case .keepListening:
                Self.logger.notice("Hands-free piece kept; still listening")
            case let .send(question):
                await self.stopListeningForReply()
                self.isTalkRecording = false
                self.handsFreeEmptyTurns = 0
                self.talk.ask(question)
            }
        }
    }

    /// Transcribes one hands-free piece with the chosen dictation engine.
    /// Returns "" for silence or noise without words.
    private func transcribeTalkPiece(_ samples: [Float]) async -> String {
        guard samples.count >= Int(AudioCapture.targetSampleRate * 0.25),
              !CapturedAudioLevel.isSilent(samples)
        else { return "" }
        let language = activeConfiguration.dictationLanguageCode
        do {
            let transcript: Transcript
            if preferences.dictationModel == .qwen3,
               Qwen3SpeechRecognizer.isSupportedOnThisMac {
                transcript = try await qwenRecognizer.transcribe(
                    samples: samples,
                    sampleRate: AudioCapture.targetSampleRate,
                    languageCode: language
                )
            } else {
                try await prepareModelForUse()
                transcript = try await recognizer.transcribe(
                    samples: samples,
                    languageCode: language
                )
            }
            return (try? transcript.finalText()) ?? ""
        } catch {
            Self.logger.error(
                "Hands-free piece could not be transcribed: \(error.localizedDescription, privacy: .public)"
            )
            return ""
        }
    }

    /// Closes the microphone for the reply without ending the conversation
    /// or keeping any recovery audio.
    private func stopListeningForReply() async {
        guard state == .recording else { return }
        endRecordingActivity()
        stopDurationTimer()
        _ = capture.cancelRetainingSamples()
        finishAudioRouteTimeline(as: .cancelled)
        currentAudioDeviceUID = nil
        _ = await dictationCoordinator.handle(.cancel)
        state = .processing
        await stopProvisionalPreview()
        await discardPersistentRecoverySpool()
        recordingStartRequestedAt = nil
        insertionTarget = nil
        quickDictationTargetActive = false
        audioLevel = 0
        audioHealthMonitor.reset()
        audioInputHealth = .idle
        state = .ready
    }

    /// A hands-free turn that held no words (a cough, a door) just listens
    /// again, a few times at most.
    private func resumeHandsFreeAfterEmptyTurn() -> Bool {
        guard isTalkHandsFree, handsFreeEmptyTurns < 3 else { return false }
        handsFreeEmptyTurns += 1
        isTalkRecording = false
        state = .ready
        listenForNextTalkTurn()
        return true
    }

    /// The HUD shows the Fantail card when Talk has something to show and no
    /// dictation is in progress.
    var showsTalkCard: Bool {
        talk.showsCard && state == .ready
    }

    /// nil returns Talk to the Desktop.
    func setTalkWorkspace(_ url: URL?) {
        preferences.talkWorkspacePath = url?.standardizedFileURL.path
        persist()
    }

    func setTalkComputerUse(_ enabled: Bool) {
        preferences.talkComputerUseEnabled = enabled
        persist()
    }

    func setTalkEngine(_ value: TalkEngine) {
        guard preferences.talkEngine != value else { return }
        talk.endConversation()
        preferences.talkEngine = value
        persist()
    }

    func setDictationModel(_ value: DictationModel) {
        guard preferences.dictationModel != value else { return }
        preferences.dictationModel = value
        persist()
        if value == .qwen3 {
            prepareQwen()
        } else {
            qwenPreparationTask?.cancel()
            qwenPreparationProgress = nil
            Task { await qwenRecognizer.unload() }
        }
    }

    var qwenSupportedOnThisMac: Bool { Qwen3SpeechRecognizer.isSupportedOnThisMac }
    var qwenUnsupportedReason: String? { Qwen3SpeechRecognizer.unsupportedReason }

    /// Downloads (once) and loads Qwen3-ASR so the first dictation doesn't
    /// wait for it.
    func prepareQwen() {
        guard qwenPreparationTask == nil else { return }
        guard Qwen3SpeechRecognizer.isSupportedOnThisMac else {
            qwenStatus = Qwen3SpeechRecognizer.unsupportedReason
            return
        }
        qwenStatus = String(localized: "Preparing Qwen3-ASR…")
        qwenPreparationProgress = 0
        qwenPreparationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await qwenRecognizer.prepare { progress in
                    Task { @MainActor [weak self] in
                        self?.qwenPreparationProgress = progress.fractionCompleted
                        self?.qwenStatus = progress.phase.label
                    }
                }
                qwenStatus = String(localized: "Ready offline")
            } catch is CancellationError {
                qwenStatus = nil
            } catch {
                qwenStatus = "Qwen3-ASR couldn't load: \(error.localizedDescription)"
            }
            qwenPreparationProgress = nil
            qwenPreparationTask = nil
        }
    }

    /// Talk is switched on and this Mac can run it (Apple Silicon only).
    var isTalkAvailable: Bool {
        preferences.talkEnabled && TalkAvailability.onThisMac
    }

    func setTalkEnabled(_ value: Bool) {
        preferences.talkEnabled = value
        if !value {
            talk.endConversation()
        }
        persist()
    }

    /// Hands a final Talk transcript to Fantail instead of inserting it.
    private func handOffToTalk(_ question: String) async {
        if let coordinatorSessionID {
            _ = await dictationCoordinator.handle(
                .rawFinalProduced(coordinatorSessionID)
            )
            _ = await dictationCoordinator.handle(
                .revisionProduced(coordinatorSessionID)
            )
            _ = await dictationCoordinator.handle(
                .commitSucceeded(coordinatorSessionID, outcome: .copied)
            )
        }
        discardAudioRecovery()
        await resolvePersistentRecovery(as: .discarded)
        pendingTranscript = nil
        insertionTarget = nil
        isTalkRecording = false
        handsFreeEmptyTurns = 0
        state = .ready
        talk.ask(question)
    }

    /// Types a Talk reply at the current cursor.
    private func insertTalkReply(_ reply: String) {
        do {
            guard inserter.hasAccessibilityPermission(prompt: true) else {
                throw VoiceError.accessibilityPermissionDenied
            }
            let target = try captureInsertionTarget()
            try inserter.commitVerifiedFinalText(
                reply,
                mode: .type,
                target: target
            )
            talk.dismiss()
        } catch {
            recordOperationalIssue(.insertion)
            state = .failed(error.localizedDescription)
        }
    }

    private func performInputIntent(
        _ intent: DictationInputIntent,
        origin: DictationOrigin
    ) {
        switch intent {
        case .none:
            break
        case .toggle:
            if isRecordingOrStarting {
                finishRecording()
            } else {
                beginRecording(origin: origin)
            }
        case .start:
            beginRecording(origin: origin)
        case .finish:
            finishRecording()
        case .cancel:
            cancelRecording()
        case .commit:
            commitExplicitEnter()
        }
    }

    private func commitExplicitEnter() {
        guard
            state == .ready,
            lastTranscript != nil,
            let commitEnterTarget,
            let expiresAt = commitEnterExpiresAtUptime,
            ProcessInfo.processInfo.systemUptime <= expiresAt
        else {
            self.commitEnterTarget = nil
            commitEnterExpiresAtUptime = nil
            inputBindingError =
                "Commit or Enter is available only briefly after a successful insertion."
            return
        }
        do {
            try inserter.commitExplicitEnter(target: commitEnterTarget)
            self.commitEnterTarget = nil
            commitEnterExpiresAtUptime = nil
            inputBindingError = nil
        } catch {
            self.commitEnterTarget = nil
            commitEnterExpiresAtUptime = nil
            inputBindingError =
                "Enter was not sent: \(error.localizedDescription)"
            recordOperationalIssue(.insertion)
        }
    }

    private func armExplicitEnter(_ target: TextInsertionTarget) {
        commitEnterTarget = target
        commitEnterExpiresAtUptime =
            ProcessInfo.processInfo.systemUptime + 10
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

    func setRecordingHUDTheme(_ value: RecordingHUDTheme) {
        preferences.recordingHUDTheme = value
        persist()
    }

    func setShowRecordingHUD(_ value: Bool) {
        preferences.showRecordingHUD = value
        if !value {
            preferences.livePreviewEnabled = false
        }
        persist()
    }

    func setLivePreviewEnabled(_ value: Bool) {
        preferences.livePreviewEnabled = value
        if value {
            preferences.showRecordingHUD = true
        }
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

    func setUsageInsightsEnabled(_ value: Bool) {
        preferences.usageInsightsEnabled = value
        if !value {
            pendingUsageDay = nil
        }
        persist()
        onInsightsChange?()
    }

    func setVocabularySuggestionsEnabled(_ value: Bool) {
        preferences.vocabularySuggestionsEnabled = value
        persist()
    }

    func setSystemNotificationsEnabled(_ value: Bool) {
        guard notificationCapabilityEnabled else { return }
        if !value {
            preferences.notificationPreferences
                .systemNotificationsEnabled = false
            persist()
            return
        }
        Task {
            let granted = await onNotificationPermissionRequest?() ?? false
            preferences.notificationPreferences
                .systemNotificationsEnabled = granted
            inAppNotificationMessage = granted
                ? "System notifications are enabled."
                : "System notifications were not allowed. Operational failures will still appear in Autohand Voice."
            persist()
        }
    }

    func setNotificationCategory(
        _ category: VoiceNotificationCategory,
        muted: Bool
    ) {
        if muted {
            preferences.notificationPreferences.mutedCategories
                .insert(category)
        } else {
            preferences.notificationPreferences.mutedCategories
                .remove(category)
        }
        persist()
    }

    func acknowledgeInAppNotification() {
        inAppNotificationMessage = nil
    }

    func handleSystemNotificationAction(
        notificationID: String,
        action: VoiceNotificationAction,
        deepLink: String?
    ) {
        Task {
            guard await notificationPolicy.acknowledge(
                notificationID: notificationID,
                action: action
            ) else { return }
            switch action {
            case .copyLast:
                guard lastTranscript != nil else {
                    inAppNotificationMessage =
                        "The completed transcript has expired."
                    return
                }
                copyLastTranscript()
                inAppNotificationMessage = "Last transcript copied."
            case .recover:
                guard
                    let deepLink,
                    let idString = URL(string: deepLink)?
                        .pathComponents.last,
                    let id = UUID(uuidString: idString),
                    persistentRecoverySummaries.contains(
                        where: { $0.id == id }
                    )
                else {
                    inAppNotificationMessage =
                        "That recovery item has expired."
                    return
                }
                retryPersistentRecovery(id)
            case .openSettings:
                onOpenSettings?()
            case .openHistory:
                onOpenHistory?()
            }
        }
    }

    func handleSystemNotificationOpen(deepLink: String?) {
        guard let deepLink else {
            inAppNotificationMessage =
                "The notification has no local destination."
            return
        }
        let historyIDs = Set(
            ((try? historyStore.load(
                retentionDays: preferences.historyRetentionDays,
                maximumItems: preferences.historyMaximumItems
            )) ?? []).map(\.id)
        )
        switch VoiceDeepLinkResolver.resolve(
            deepLink,
            existingHistoryIDs: historyIDs,
            existingRecoveryIDs: Set(
                persistentRecoverySummaries.map(\.id)
            )
        ) {
        case .history:
            onOpenHistory?()
        case .recovery:
            inAppNotificationMessage =
                "Recovery is ready. Choose Recover or Discard from the menu."
        case .expired:
            inAppNotificationMessage =
                "That local notification item has expired."
        case .invalid:
            inAppNotificationMessage =
                "That notification link is invalid."
        }
    }

    func resetUsageInsights() throws {
        try usageInsightsStore.reset()
        pendingUsageDay = nil
        usageInsightsError = nil
        onInsightsChange?()
    }

    func resetAllLocalData() {
        guard !isResettingLocalData else { return }
        guard state != .processing else {
            localDataResetMessage =
                "Wait for local processing to finish, then reset again."
            return
        }
        isResettingLocalData = true
        localDataResetMessage = nil
        stopDurationTimer()
        if isRecordingOrStarting {
            capture.cancel()
            finishAudioRouteTimeline(as: .cancelled)
            currentAudioDeviceUID = nil
        }
        stopWhenStarted = false
        cancelWhenStarted = false
        modelTask?.cancel()
        modelTask = nil
        state = .processing

        Task {
            _ = await dictationCoordinator.handle(.cancel)
            await stopProvisionalPreview()
            await discardPersistentRecoverySpool()
            await onPrepareLocalDataReset?()
            try? await reliabilityLedger.reset()
            try? await recoveryVault.reset()

            let report: LocalDataResetReport
            do {
                report = try LocalDataResetter().reset()
            } catch {
                isResettingLocalData = false
                localDataResetMessage =
                    "Local reset could not start: \(error.localizedDescription)"
                state = .failed(localDataResetMessage ?? "Local reset failed.")
                return
            }

            UserDefaults.standard.removePersistentDomain(
                forName: Brand.bundleIdentifier
            )
            resetInMemoryAfterLocalDataReset()
            onLocalDataReset?()
            isResettingLocalData = false
            if report.succeeded {
                localDataResetMessage =
                    "All local user data and the recovery key were removed "
                    + "and verified. Restart to reopen optional workspaces."
                state = .ready
            } else {
                let failed = report.entries.compactMap {
                    $0.failure == nil ? nil : $0.id
                }
                let keyFailure = report.recoveryKeyFailure == nil
                    ? []
                    : ["Recovery Key"]
                localDataResetMessage =
                    "Reset was incomplete for: "
                    + (failed + keyFailure).joined(separator: ", ")
                state = .failed(
                    localDataResetMessage ?? "Local reset was incomplete."
                )
            }
        }
    }

    func setHistoryRetentionDays(_ value: Int) {
        preferences.historyRetentionDays = min(max(1, value), 365)
        persist()
        pruneHistory()
    }

    func setHistoryMaximumItems(_ value: Int) {
        preferences.historyMaximumItems = min(max(1, value), 1_000)
        persist()
        pruneHistory()
    }

    func setDictationCommandsEnabled(_ value: Bool) {
        preferences.dictationCommandsEnabled = value
        persist()
    }

    func setSmartFormattingEnabled(_ value: Bool) {
        preferences.cleanupLevel = value ? .medium : .literal
        preferences.smartFormattingEnabled = value
        persist()
    }

    func setCleanupLevel(_ level: CleanupLevel) {
        guard level != .high || localTransformsEnabled else { return }
        preferences.cleanupLevel = level
        preferences.smartFormattingEnabled = level != .literal
        persist()
    }

    func setMinimalContextEnabled(_ enabled: Bool) {
        guard minimalContextCapabilityEnabled || !enabled else { return }
        preferences.minimalContextEnabled = enabled
        persist()
    }

    func addSensitiveApp(_ bundleIdentifier: String) {
        let candidate = bundleIdentifier.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            candidate.contains("."),
            !preferences.sensitiveAppDenylist.contains(candidate)
        else { return }
        preferences.sensitiveAppDenylist = Array(
            ([candidate] + preferences.sensitiveAppDenylist).prefix(128)
        )
        persist()
    }

    func removeSensitiveApp(_ bundleIdentifier: String) {
        preferences.sensitiveAppDenylist.removeAll {
            $0 == bundleIdentifier
        }
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
            recordOperationalIssue(.storage)
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
            modelPreparationPresentation = .foreground
            await modelTask.value
            guard modelState == .ready else {
                throw VoiceError.modelUnavailable(modelState.label)
            }
            return
        }
        let operationID = UUID()
        modelOperationID = operationID
        modelPreparationPresentation = .foreground
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

    private func startModelPreparation(
        repair: Bool,
        presentation: ModelPreparationPresentation
    ) {
        modelTask?.cancel()
        let operationID = UUID()
        modelOperationID = operationID
        modelPreparationPresentation = presentation
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
                if let presentation = self?.modelPreparationPresentation {
                    let advanced = presentation.advanced(for: progress.phase)
                    if advanced != presentation {
                        self?.modelPreparationPresentation = advanced
                    }
                }
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
        try await throwInjectedFailure(at: .modelValidation)
        let isValid = try await recognizer.validate()
        guard isValid else {
            throw VoiceError.modelUnavailable("CoreML validation did not pass")
        }
        modelStorageBytes = try await recognizer.storageBytes()
        modelLastValidated = Date()
        modelProgress = 1
        modelPhase = nil
        modelFailureKind = nil
        recordReliability(
            category: .modelValidation,
            outcome: .success
        )
    }

    private func setModelFailure(_ error: Error) {
        recordReliability(
            category: .modelValidation,
            outcome: .failure
        )
        recordOperationalIssue(.model)
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
        target: TextInsertionTarget?,
        outputModeOverride: OutputMode? = nil
    ) async throws {
        let processingStartedAt = ProcessInfo.processInfo.systemUptime
        let configuration = activeConfiguration
        let outputMode = outputModeOverride ?? configuration.outputMode
        let recognizedText: String
        do {
            try await throwInjectedFailure(at: .recognition)
            let transcript: Transcript
            if preferences.dictationModel == .qwen3 {
                // Chosen explicitly; never fall back to another engine.
                if let reason = Qwen3SpeechRecognizer.unsupportedReason {
                    throw VoiceError.modelUnavailable(reason)
                }
                transcript = try await qwenRecognizer.transcribe(
                    samples: samples,
                    sampleRate: AudioCapture.targetSampleRate,
                    languageCode: configuration.dictationLanguageCode
                )
            } else {
                try await prepareModelForUse()
                transcript = try await recognizer.transcribe(
                    samples: samples,
                    languageCode: configuration.dictationLanguageCode
                )
            }
            recognizedText = try transcript.finalText()
            recordReliability(
                category: .transcription,
                outcome: .success,
                latencyMetric: .stopToFinal,
                startedAt: processingStartedAt
            )
        } catch {
            recordReliability(
                category: .transcription,
                outcome: .failure,
                latencyMetric: .stopToFinal,
                startedAt: processingStartedAt
            )
            throw error
        }
        let commandResult = DictationCommandProcessor.process(
            recognizedText,
            enabled: configuration.dictationCommandsEnabled,
            locale: Locale(
                identifier: configuration.dictationLanguageCode
            )
        )
        if commandResult.shouldCancel {
            if let coordinatorSessionID {
                _ = await dictationCoordinator.handle(
                    .dictationCommandCancelled(coordinatorSessionID)
                )
            }
            discardAudioRecovery()
            await resolvePersistentRecovery(as: .discarded)
            pendingTranscript = nil
            insertionTarget = nil
            quickDictationTargetActive = false
            state = .ready
            Self.logger.notice(
                "Dictation cancelled by explicit local voice command"
            )
            return
        }
        guard commandResult.text.contains(where: { !$0.isWhitespace }) else {
            throw VoiceError.emptyTranscript
        }
        if isTalkRecording {
            await handOffToTalk(commandResult.text)
            return
        }
        if let coordinatorSessionID {
            _ = await dictationCoordinator.handle(
                .rawFinalProduced(coordinatorSessionID)
            )
        }
        try await throwInjectedFailure(at: .revision)
        let vocabularyRules: [ReplacementRule]
        do {
            vocabularyRules = configuration.vocabularyEnabled
                ? try vocabularyStore.load()
                : []
            vocabularyError = nil
        } catch {
            vocabularyRules = []
            vocabularyError = "Replacements could not be loaded: \(error.localizedDescription)"
            Self.logger.error(
                "Vocabulary load failed; preserving recognized text: \(error.localizedDescription)"
            )
        }
        let rawFinal = try RawFinalTranscript(
            text: commandResult.text,
            languageCode: configuration.dictationLanguageCode
        )
        currentRawFinal = rawFinal
        let revisionResult = await revisionEngine.propose(
            raw: rawFinal,
            policy: RevisionPolicy(
                level: configuration.cleanupLevel,
                vocabularyRules: vocabularyRules,
                context: target?.context ?? .unknown,
                addsTerminalPunctuation:
                    configuration.automaticTerminalPunctuation,
                localeIdentifier: configuration.dictationLanguageCode,
                englishSpellingPolicy:
                    preferences.englishSpellingPolicy,
                localTransformAvailable: localTransformsEnabled
            )
        )
        if !revisionResult.matchedVocabularyRuleIDs.isEmpty {
            let updatedRules = VocabularyRanking.recordUsage(
                ruleIDs: revisionResult.matchedVocabularyRuleIDs,
                in: vocabularyRules
            )
            do {
                try vocabularyStore.save(updatedRules)
                vocabularyError = nil
            } catch {
                vocabularyError =
                    "Replacement usage could not be saved: \(error.localizedDescription)"
                Self.logger.error(
                    "Vocabulary usage save failed: \(error.localizedDescription)"
                )
            }
        }
        currentRevision = revisionResult.revision
        if revisionResult.outcome == .localTransformUnavailable {
            pendingTranscript = rawFinal.text
            lastUnformattedTranscript = nil
            discardAudioRecovery()
            recordHistory(
                text: rawFinal.text,
                outcome: .insertionFailed,
                rawFinal: rawFinal,
                revision: revisionResult.revision,
                duration: TimeInterval(samples.count)
                    / AudioCapture.targetSampleRate,
                failureCategory: .revision(.modelUnavailable)
            )
            throw RevisionError.localTransformUnavailable
        }
        let finalText = revisionResult.revision.text
        if let coordinatorSessionID {
            _ = await dictationCoordinator.handle(
                .revisionProduced(coordinatorSessionID)
            )
        }
        lastUnformattedTranscript = finalText == rawFinal.text
            ? nil
            : rawFinal.text
        pendingTranscript = finalText
        discardAudioRecovery()
        recordHistory(
            text: finalText,
            outcome: .insertionFailed,
            rawFinal: rawFinal,
            revision: revisionResult.revision,
            duration: TimeInterval(samples.count)
                / AudioCapture.targetSampleRate
        )
        if quickDictationTargetActive {
            guard let onQuickDictation else {
                quickDictationTargetActive = false
                throw LocalWorkspaceError.unavailable
            }
            try await onQuickDictation(finalText)
            let processingDuration = max(
                0,
                ProcessInfo.processInfo.systemUptime - processingStartedAt
            )
            recordUsageInsights(
                text: finalText,
                samples: samples,
                processingDuration: processingDuration,
                insertionSucceeded: true,
                cleanupChangeCount:
                    revisionResult.revision.changes.count,
                vocabularyMatchCount:
                    revisionResult.matchedVocabularyRuleIDs.count
            )
            if let coordinatorSessionID {
                _ = await dictationCoordinator.handle(
                    .commitSucceeded(
                        coordinatorSessionID,
                        outcome: .inserted
                    )
                )
            }
            lastTranscript = finalText
            updateHistoryOutcome(.inserted)
            pendingTranscript = nil
            pendingUsageDay = nil
            insertionTarget = nil
            quickDictationTargetActive = false
            await resolvePersistentRecovery(as: .recovered)
            state = .ready
            presentCompletion("Added to Scratchpad")
            emitCompletionNotification()
            if configuration.playSounds { NSSound.beep() }
            return
        }
        Self.logger.notice(
            "Final local transcript produced with \(finalText.count) characters"
        )
        let processingDuration = max(
            0,
            ProcessInfo.processInfo.systemUptime - processingStartedAt
        )
        do {
            try await throwInjectedFailure(at: .insertion)
            try inserter.commitVerifiedFinalText(
                finalText,
                mode: outputMode,
                target: target
            )
            recordReliability(
                category: .insertion,
                outcome: .success,
                latencyMetric: .insertion,
                startedAt: processingStartedAt + processingDuration
            )
            if let coordinatorSessionID {
                _ = await dictationCoordinator.handle(
                    .commitSucceeded(
                        coordinatorSessionID,
                        outcome: outputMode == .type
                            ? .inserted
                            : .copied
                    )
                )
            }
            recordUsageInsights(
                text: finalText,
                samples: samples,
                processingDuration: processingDuration,
                insertionSucceeded: true,
                cleanupChangeCount:
                    revisionResult.revision.changes.count,
                vocabularyMatchCount:
                    revisionResult.matchedVocabularyRuleIDs.count
            )
        } catch {
            updateHistoryOutcome(
                .insertionFailed,
                failureCategory: failureCategory(for: error)
            )
            recordReliability(
                category: .insertion,
                outcome: .failure,
                latencyMetric: .insertion,
                startedAt: processingStartedAt + processingDuration
            )
            pendingUsageDay = recordUsageInsights(
                text: finalText,
                samples: samples,
                processingDuration: processingDuration,
                insertionSucceeded: false,
                cleanupChangeCount:
                    revisionResult.revision.changes.count,
                vocabularyMatchCount:
                    revisionResult.matchedVocabularyRuleIDs.count
            )
            throw error
        }
        Self.logger.notice("Final transcript committed at the cursor")
        lastTranscript = finalText
        if outputMode == .type, let target {
            armExplicitEnter(target)
        } else {
            commitEnterTarget = nil
            commitEnterExpiresAtUptime = nil
        }
        updateHistoryOutcome(.inserted)
        pendingTranscript = nil
        pendingUsageDay = nil
        insertionTarget = nil
        await resolvePersistentRecovery(as: .recovered)
        state = .ready
        presentCompletion(
            outputMode == .type
                ? "Inserted at the current cursor"
                : "Copied to the clipboard"
        )
        emitCompletionNotification()
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

    private func reloadDictationStyles() {
        do {
            customDictationStyles = try dictationStyleStore.load()
            styleError = nil
        } catch {
            customDictationStyles = []
            styleError =
                "Dictation styles could not be loaded: \(error.localizedDescription)"
        }
    }

    private func expireTemporaryStyleIfNeeded() {
        guard temporaryStyleID != nil else { return }
        guard !TemporaryStylePolicy.isActive(
            expiresAtUptime: temporaryStyleExpiresAtUptime,
            nowUptime: ProcessInfo.processInfo.systemUptime
        ) else { return }
        temporaryStyleID = nil
        temporaryStyleExpiresAtUptime = nil
    }

    private func touchTemporaryStyleOverride() {
        guard temporaryStyleID != nil else { return }
        temporaryStyleExpiresAtUptime =
            ProcessInfo.processInfo.systemUptime
                + TemporaryStylePolicy.inactivityExpiration
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
        warmLocalModel()
    }

    private func retainAudioRecovery(
        _ samples: [Float],
        wasCancelled: Bool = false
    ) {
        let recoveryID = UUID()
        audioRecoveryID = recoveryID
        audioRecovery.store(
            samples,
            at: ProcessInfo.processInfo.systemUptime
        )
        recoverableAudioDuration = audioRecovery.duration
        hasRecoverableAudio = audioRecovery.sampleCount > 0
        recoverableAudioWasCancelled =
            wasCancelled && hasRecoverableAudio

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
        recoverableAudioWasCancelled = false
    }

    private func resetInMemoryAfterLocalDataReset() {
        endRecordingActivity()
        clearCompletionPresentation()
        preferences = VoicePreferences()
        appProfiles = []
        customDictationStyles = []
        activeConfiguration = AppProfileResolver.resolve(
            preferences: preferences,
            profiles: [],
            bundleIdentifier: nil
        )
        recognizer = LocalSpeechRecognizer(
            modelVersion: preferences.modelVersion
        )
        recognizerModelVersion = preferences.modelVersion
        modelState = .notChecked
        modelProgress = 0
        modelPhase = nil
        modelPreparationPresentation = .background
        modelStorageBytes = 0
        modelLastValidated = nil
        modelFailureKind = nil
        lastTranscript = nil
        lastUnformattedTranscript = nil
        currentRevision = nil
        currentRawFinal = nil
        postDictationRedoRevisionID = nil
        pendingTranscript = nil
        clearProvisionalPreview()
        recordingElapsed = 0
        durationWarning = nil
        discardAudioRecovery()
        persistentRecoveryID = nil
        persistentRecoverySummaries = []
        persistentRecoveryError = nil
        isCheckingPersistentRecovery = false
        historyEntryID = nil
        historyError = nil
        pendingUsageDay = nil
        usageInsightsError = nil
        vocabularyError = nil
        profileError = nil
        styleError = nil
        inAppNotificationMessage = nil
        temporaryStyleID = nil
        temporaryStyleExpiresAtUptime = nil
        coordinatorSessionID = nil
        insertionTarget = nil
        quickDictationTargetActive = false
        audioLevel = 0
        audioHealthMonitor.reset()
        audioInputHealth = .idle
        audioInputName = "System Default"
        _ = onPointerMonitoringChange?(false, false)
        pointerInputStatus = "Off"
        observedPointerButton = nil
        inputBindingError = nil
        inputBindingReducer = InputBindingReducer()
        commitEnterTarget = nil
        commitEnterExpiresAtUptime = nil
        _ = onShortcutRegistration?(preferences.shortcut)
        _ = onInputBindingsRegistration?(preferences.inputBindings)
        if scratchpadEnabled {
            reportScratchpadShortcutRegistration(
                onScratchpadShortcutRegistration?(
                    preferences.scratchpadShortcut
                ) ?? noErr
            )
        }
        onHistoryChange?()
        onInsightsChange?()
        onOperationalIssuesChange?()
        onReliabilityChange?()
    }

    private func recordHistory(
        text: String,
        outcome: HistoryOutcome,
        rawFinal: RawFinalTranscript? = nil,
        revision: TranscriptRevision? = nil,
        duration: TimeInterval? = nil,
        failureCategory: VoiceFailureCategory? = nil
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
                maximumItems: preferences.historyMaximumItems,
                rawFinal: rawFinal,
                revision: revision,
                duration: duration,
                failureCategory: failureCategory
            )
            historyEntryID = entry.id
            historyError = nil
            onHistoryChange?()
        } catch {
            historyEntryID = nil
            recordOperationalIssue(.storage)
            historyError = "Could not save local history: \(error.localizedDescription)"
            onChange?()
        }
    }

    private func updateHistoryOutcome(
        _ outcome: HistoryOutcome,
        failureCategory: VoiceFailureCategory? = nil
    ) {
        guard let historyEntryID else { return }
        do {
            try historyStore.updateOutcome(
                id: historyEntryID,
                outcome: outcome,
                failureCategory: failureCategory
            )
            self.historyEntryID = nil
            historyError = nil
            onHistoryChange?()
        } catch {
            recordOperationalIssue(.storage)
            historyError = "Could not update local history: \(error.localizedDescription)"
            onChange?()
        }
    }

    @discardableResult
    private func recordUsageInsights(
        text: String,
        samples: [Float],
        processingDuration: TimeInterval,
        insertionSucceeded: Bool,
        cleanupChangeCount: Int = 0,
        vocabularyMatchCount: Int = 0
    ) -> Date? {
        guard preferences.usageInsightsEnabled else { return nil }
        do {
            let day = try usageInsightsStore.record(
                UsageMetricEvent(
                    wordCount: text.split(whereSeparator: \.isWhitespace).count,
                    recordingDuration: Double(samples.count)
                        / AudioCapture.targetSampleRate,
                    processingDuration: processingDuration,
                    insertionSucceeded: insertionSucceeded,
                    cleanupChangeCount: cleanupChangeCount,
                    vocabularyMatchCount: vocabularyMatchCount,
                    appCategory:
                        UsageAppCategoryClassifier.classify(
                            bundleIdentifier:
                                NSWorkspace.shared.frontmostApplication?
                                    .bundleIdentifier
                        )
                )
            )
            usageInsightsError = nil
            onInsightsChange?()
            return day
        } catch {
            recordOperationalIssue(.storage)
            usageInsightsError =
                "Usage insights could not be saved: \(error.localizedDescription)"
            return nil
        }
    }

    private func markPendingUsageInsertionSucceeded() {
        guard
            preferences.usageInsightsEnabled,
            let pendingUsageDay
        else { return }
        do {
            try usageInsightsStore.markInsertionSucceeded(
                on: pendingUsageDay
            )
            self.pendingUsageDay = nil
            usageInsightsError = nil
            onInsightsChange?()
        } catch {
            recordOperationalIssue(.storage)
            usageInsightsError =
                "Usage insights could not be updated: \(error.localizedDescription)"
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
            recordOperationalIssue(.storage)
            historyError = "Could not prune local history: \(error.localizedDescription)"
            onChange?()
        }
    }

    private func persist() {
        do {
            try store.save(preferences)
        } catch {
            recordOperationalIssue(.settings)
            state = .failed("Could not save settings: \(error.localizedDescription)")
        }
        if !isRecordingOrStarting, state != .processing {
            refreshActiveProfile()
        }
        onChange?()
    }

    private func observeAudioLevel(_ level: Float) {
        audioInputRMS = level
        audioLevel = min(max(level * 8, 0), 1)
        observeHandsFreeLevel(level)
        audioInputHealth = audioHealthMonitor.observe(
            level: level,
            at: ProcessInfo.processInfo.systemUptime
        )
    }

    func reportShortcutRegistration(succeeded: Bool) {
        shortcutRegistrationState = succeeded ? .registered : .unavailable
    }

    func reportScratchpadShortcutRegistration(_ status: OSStatus) {
        scratchpadShortcutError = status == noErr
            ? nil
            : "Scratchpad shortcut is unavailable (error \(status))."
        if status != noErr {
            recordOperationalIssue(.shortcut)
        }
        onChange?()
    }

    private func beginRecordingActivity() {
        guard recordingActivity == nil else { return }
        recordingActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Autohand Voice is recording a bounded local dictation."
        )
    }

    private func endRecordingActivity() {
        guard let recordingActivity else { return }
        ProcessInfo.processInfo.endActivity(recordingActivity)
        self.recordingActivity = nil
    }

    private func presentCompletion(_ message: String) {
        completionTask?.cancel()
        let duration = preferences.recordingHUDTheme.completionDisplayDuration
        let deadline = ProcessInfo.processInfo.systemUptime
            + Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1e18
        completionExpiresAtUptime = deadline
        completionPresentation = message
        completionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard
                !Task.isCancelled,
                let self,
                self.completionExpiresAtUptime == deadline
            else { return }
            self.completionExpiresAtUptime = nil
            self.completionPresentation = nil
            self.completionTask = nil
        }
    }

    private func clearCompletionPresentation() {
        completionTask?.cancel()
        completionTask = nil
        completionExpiresAtUptime = nil
        completionPresentation = nil
    }

    private func startDurationTimer() {
        stopDurationTimer()
        recordingElapsed = 0
        durationWarning = nil
        let startedAt = ProcessInfo.processInfo.systemUptime
        var timer = DictationSessionTimer(
            policy: durationPolicy,
            startedAt: startedAt
        )
        durationTimerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard state == .recording else { return }
                let observation = timer.observe(
                    at: ProcessInfo.processInfo.systemUptime
                )
                recordingElapsed = observation.elapsed
                if let warning = observation.newWarnings.last {
                    durationWarning = warning
                }
                if observation.shouldFinalize {
                    _ = await dictationCoordinator.handle(
                        .durationLimitReached
                    )
                    guard state == .recording else { return }
                    finishStartedRecording()
                    return
                }
            }
        }
    }

    private func stopDurationTimer() {
        durationTimerTask?.cancel()
        durationTimerTask = nil
    }

    private func coordinatorProfile(
        for configuration: ResolvedAppProfile
    ) -> DictationSessionProfile {
        DictationSessionProfile(
            modelVersion: SpeechModelVariant(
                rawValue: configuration.modelVersion
            ) ?? .default,
            language: SupportedDictationLanguage(
                rawValue: configuration.dictationLanguageCode
            ) ?? .english,
            outputMode: configuration.outputMode,
            style: DictationStyle(
                rawValue: configuration.cleanupLevel.rawValue
            ) ?? .literal
        )
    }

    private func finishAudioRouteTimeline(
        as outcome: AudioRouteSegmentOutcome
    ) {
        audioRouteTimeline.finishCurrent(
            as: outcome,
            at: ProcessInfo.processInfo.systemUptime
        )
    }

    private func currentRecoveryMetadata() -> RecoveryMetadata {
        RecoveryMetadata(
            sessionID: coordinatorSessionID ?? UUID(),
            sampleRate: AudioCapture.targetSampleRate,
            languageCode: activeConfiguration.dictationLanguageCode,
            modelVersion: activeConfiguration.modelVersion,
            audioRouteSegments: audioRouteTimeline.segments
        )
    }

    private func updatePersistentRecoveryRouteMetadata() async {
        guard
            persistentRecoveryEnabled,
            let persistentRecoveryID,
            recoveryAudioTask != nil
        else { return }
        do {
            try await recoveryVault.updateLiveSpoolMetadata(
                persistentRecoveryID,
                metadata: currentRecoveryMetadata()
            )
        } catch {
            persistentRecoveryError =
                "Recovery route metadata could not be updated: "
                    + error.localizedDescription
            recordOperationalIssue(.storage)
        }
    }

    private func resolvedAudioInputDeviceUID() throws -> String? {
        let rankedDeviceUIDs = preferences.audioInputDevicePriority
        let policy = AudioRoutePolicy(
            rankedDeviceUIDs: rankedDeviceUIDs,
            automaticHandoffEnabled:
                preferences.automaticAudioHandoffEnabled
        )
        switch policy.resolve(
            devices: try AudioInputDevices.available(),
            clamshellClosed:
                clamshellStateChecker.isClamshellClosed()
        ) {
        case let .selected(selection):
            return selection.deviceUID
        case let .unavailable(failure):
            throw VoiceInjectedFailure(
                category: .audioRoute(failure)
            )
        }
    }

    private func captureInsertionTarget() throws -> TextInsertionTarget {
        guard let initialTarget = inserter.captureTarget() else {
            throw VoiceError.noFocusedTextField
        }
        let configuration = sensitiveContextConfiguration(
            for: initialTarget.context.targetDescriptor
        )
        let initialDecision = sensitiveContextPolicy.decision(
            for: initialTarget.context.targetDescriptor,
            configuration: configuration
        )
        switch initialDecision {
        case let .deny(reason):
            throw VoiceError.sensitiveTarget(reason)
        case .allow(contextScalarLimit: 0):
            return initialTarget
        case let .allow(contextScalarLimit):
            guard let contextualTarget = inserter.captureTarget(
                contextScalarLimit: contextScalarLimit
            ) else {
                throw VoiceError.noFocusedTextField
            }
            switch sensitiveContextPolicy.decision(
                for: contextualTarget.context.targetDescriptor,
                configuration: sensitiveContextConfiguration(
                    for: contextualTarget.context.targetDescriptor
                )
            ) {
            case let .deny(reason):
                throw VoiceError.sensitiveTarget(reason)
            case .allow:
                return contextualTarget
            }
        }
    }

    private func sensitiveContextConfiguration(
        for target: TextTargetDescriptor
    ) -> SensitiveContextConfiguration {
        let profile = target.bundleIdentifier.flatMap { identifier in
            appProfiles.first { $0.bundleIdentifier == identifier }
        }
        return SensitiveContextConfiguration(
            contextEnabled: featureFlags.isEnabled(.minimalContext)
                && preferences.minimalContextEnabled,
            localDenylist: preferences.sensitiveAppDenylist,
            profileContextAccess: profile?.contextAccess ?? .inherit,
            profileIsSensitive: profile?.isSensitive == true,
            allowsBuiltInSensitiveApp: profile?.isSensitive == false
        )
    }

    func refreshPersistentRecovery() {
        guard persistentRecoveryEnabled else {
            persistentRecoverySummaries = []
            persistentRecoveryError = nil
            isCheckingPersistentRecovery = false
            return
        }
        isCheckingPersistentRecovery = true
        Task {
            do {
                try await recoveryVault.purgeExpired()
                persistentRecoverySummaries = try await recoveryVault.list()
                persistentRecoveryError = nil
            } catch {
                persistentRecoveryError = error.localizedDescription
            }
            isCheckingPersistentRecovery = false
        }
    }

    func retryPersistentRecovery(_ id: UUID) {
        retryPersistentRecovery(id, outputModeOverride: nil)
    }

    func copyPersistentRecovery(_ id: UUID) {
        retryPersistentRecovery(id, outputModeOverride: .clipboard)
    }

    private func retryPersistentRecovery(
        _ id: UUID,
        outputModeOverride: OutputMode?
    ) {
        guard persistentRecoveryEnabled, state != .processing else { return }
        Task {
            do {
                let artifact = try await recoveryVault.open(id)
                refreshActiveProfile()
                let target: TextInsertionTarget?
                let outputMode =
                    outputModeOverride
                        ?? activeConfiguration.outputMode
                if outputMode == .type {
                    guard
                        inserter.hasAccessibilityPermission(prompt: true)
                    else {
                        throw VoiceError.accessibilityPermissionDenied
                    }
                    target = try captureInsertionTarget()
                } else {
                    target = nil
                }
                persistentRecoveryID = id
                state = .processing
                try await transcribeAndCommit(
                    samples: artifact.samples,
                    target: target,
                    outputModeOverride: outputModeOverride
                )
            } catch {
                persistentRecoveryError = error.localizedDescription
                state = .failed(error.localizedDescription)
                refreshPersistentRecovery()
            }
        }
    }

    func discardPersistentRecovery(_ id: UUID) {
        guard persistentRecoveryEnabled else { return }
        Task {
            do {
                try await recoveryVault.resolve(id, as: .discarded)
                if persistentRecoveryID == id {
                    persistentRecoveryID = nil
                }
                persistentRecoveryError = nil
            } catch {
                persistentRecoveryError = error.localizedDescription
            }
            refreshPersistentRecovery()
        }
    }

    private func startPersistentRecoverySpool(
        sessionID: UUID
    ) async {
        guard persistentRecoveryEnabled else { return }
        await discardPersistentRecoverySpool()
        do {
            let metadata = RecoveryMetadata(
                sessionID: sessionID,
                sampleRate: AudioCapture.targetSampleRate,
                languageCode: activeConfiguration.dictationLanguageCode,
                modelVersion: activeConfiguration.modelVersion,
                audioRouteSegments: audioRouteTimeline.segments
            )
            let id = try await recoveryVault.beginLiveSpool(
                metadata: metadata
            )
            let (stream, continuation) =
                AsyncStream<PreviewAudioChunk>.makeStream(
                    bufferingPolicy: .bufferingOldest(512)
                )
            persistentRecoveryID = id
            recoveryAudioContinuation = continuation
            recoveryStreamBackpressure = false
            persistentRecoveryError = nil
            let vault = recoveryVault
            recoveryAudioTask = Task {
                do {
                    var resampler: StreamingAudioResampler?
                    var pending: [Float] = []
                    let samplesPerChunk = 8_000

                    func writeCompleteChunks() async throws {
                        while pending.count >= samplesPerChunk {
                            let chunk = Array(
                                pending.prefix(samplesPerChunk)
                            )
                            pending.removeFirst(samplesPerChunk)
                            try await vault.appendLiveSpool(
                                id,
                                samples: chunk
                            )
                        }
                    }

                    for await input in stream {
                        try Task.checkCancellation()
                        if resampler?.sourceRate != input.sampleRate {
                            if var existing = resampler {
                                pending.append(
                                    contentsOf: existing.finish()
                                )
                                try await writeCompleteChunks()
                            }
                            resampler = StreamingAudioResampler(
                                sourceRate: input.sampleRate,
                                targetRate: AudioCapture.targetSampleRate
                            )
                        }
                        if var active = resampler {
                            pending.append(
                                contentsOf: active.consume(input.samples)
                            )
                            resampler = active
                            try await writeCompleteChunks()
                        }
                    }
                    if var active = resampler {
                        pending.append(contentsOf: active.finish())
                    }
                    try await writeCompleteChunks()
                    if !pending.isEmpty {
                        try await vault.appendLiveSpool(
                            id,
                            samples: pending
                        )
                    }
                    return nil
                } catch is CancellationError {
                    return "Incremental recovery was cancelled."
                } catch {
                    return error.localizedDescription
                }
            }
        } catch {
            persistentRecoveryError = error.localizedDescription
            recordOperationalIssue(.storage)
        }
    }

    private func completePersistentRecovery(_ samples: [Float]) async {
        guard persistentRecoveryEnabled else { return }
        recoveryAudioContinuation?.finish()
        recoveryAudioContinuation = nil
        let streamError = await recoveryAudioTask?.value
        recoveryAudioTask = nil
        let liveID = persistentRecoveryID
        let shouldFallback = liveID == nil
            || streamError != nil
            || recoveryStreamBackpressure
        recoveryStreamBackpressure = false

        do {
            let finalID: UUID
            if !shouldFallback, let liveID {
                do {
                    try await recoveryVault.finalizeLiveSpool(
                        liveID,
                        metadata: currentRecoveryMetadata()
                    )
                    finalID = liveID
                } catch {
                    try? await recoveryVault.discardLiveSpool(liveID)
                    finalID = try await recoveryVault.stage(
                        samples: samples,
                        metadata: currentRecoveryMetadata()
                    )
                    persistentRecoveryError =
                        "Incremental recovery could not be finalized; the "
                        + "completed capture was stored instead: "
                        + error.localizedDescription
                    recordOperationalIssue(.storage)
                }
            } else {
                if let liveID {
                    try? await recoveryVault.discardLiveSpool(liveID)
                }
                finalID = try await recoveryVault.stage(
                    samples: samples,
                    metadata: RecoveryMetadata(
                        sessionID: coordinatorSessionID ?? UUID(),
                        sampleRate: AudioCapture.targetSampleRate,
                        languageCode:
                            activeConfiguration.dictationLanguageCode,
                        modelVersion: activeConfiguration.modelVersion,
                        audioRouteSegments: audioRouteTimeline.segments
                    )
                )
                if let streamError {
                    persistentRecoveryError =
                        "Incremental recovery failed; the completed capture "
                        + "was stored instead: \(streamError)"
                } else if shouldFallback {
                    persistentRecoveryError =
                        "Incremental recovery fell behind; the completed "
                        + "capture was stored instead."
                }
            }
            persistentRecoveryID = finalID
            persistentRecoverySummaries = try await recoveryVault.list()
            emitRecoveryReadyNotification(id: finalID)
        } catch {
            persistentRecoveryError = error.localizedDescription
            recordOperationalIssue(.storage)
        }
    }

    private func discardPersistentRecoverySpool() async {
        recoveryAudioContinuation?.finish()
        recoveryAudioContinuation = nil
        recoveryAudioTask?.cancel()
        _ = await recoveryAudioTask?.value
        recoveryAudioTask = nil
        recoveryStreamBackpressure = false
        guard let id = persistentRecoveryID else { return }
        try? await recoveryVault.discardLiveSpool(id)
        persistentRecoveryID = nil
    }

    private func emitRecoveryReadyNotification(id: UUID) {
        emitNotification(
            VoiceNotificationEvent(
                category: .recovery,
                title: "Local recovery is ready",
                body:
                    "Captured audio is encrypted on this Mac and can be recovered or discarded.",
                deduplicationKey: "recovery.ready",
                deepLink:
                    "autohand-voice://recovery/\(id.uuidString)",
                actions: [.recover]
            )
        )
    }

    private func resolvePersistentRecovery(
        as resolution: RecoveryResolution
    ) async {
        guard
            persistentRecoveryEnabled,
            let id = persistentRecoveryID
        else { return }
        do {
            try await recoveryVault.resolve(id, as: resolution)
            persistentRecoveryID = nil
            persistentRecoverySummaries = try await recoveryVault.list()
            persistentRecoveryError = nil
        } catch {
            persistentRecoveryError = error.localizedDescription
            recordOperationalIssue(.storage)
        }
    }

    private func reportCoordinatorFailure(_ error: Error) async {
        guard let coordinatorSessionID else { return }
        let category: VoiceFailureCategory
        if let injected = error as? VoiceInjectedFailure {
            category = injected.category
        } else if let voiceError = error as? VoiceError {
            category = voiceError.failureCategory
        } else if state == .starting {
            category = .microphone(.startFailed)
        } else if pendingTranscript != nil {
            category = .insertion(.rejected)
        } else if case .failed = modelState {
            category = .model(.unavailable)
        } else {
            category = .recognition(.failed)
        }
        _ = await dictationCoordinator.handle(
            .fail(coordinatorSessionID, category: category)
        )
    }

    private func failureCategory(
        for error: Error
    ) -> VoiceFailureCategory {
        if let injected = error as? VoiceInjectedFailure {
            return injected.category
        }
        if let voiceError = error as? VoiceError {
            return voiceError.failureCategory
        }
        if error is RevisionError {
            return .revision(.failed)
        }
        if error is RecoveryVaultError {
            return .recovery(.corrupt)
        }
        return pendingTranscript == nil
            ? .recognition(.failed)
            : .insertion(.rejected)
    }

    private func emitCompletionNotification() {
        emitNotification(
            VoiceNotificationEvent(
                category: .completion,
                title: "Dictation complete",
                body:
                    "Your final local transcript is ready. Copy occurs only if you choose Copy Last.",
                deduplicationKey: "dictation.complete",
                actions: [.copyLast],
                requiresInAppSurface: false
            )
        )
    }

    private func emitNotification(
        _ event: VoiceNotificationEvent
    ) {
        guard notificationCapabilityEnabled else { return }
        let notificationPreferences =
            preferences.notificationPreferences
        Task {
            let disposition = await notificationPolicy.handle(
                event,
                preferences: notificationPreferences
            )
            switch disposition {
            case let .system(notification, alsoInApp):
                onSystemNotification?(notification)
                if alsoInApp {
                    inAppNotificationMessage = event.body
                }
            case .inAppOnly:
                inAppNotificationMessage = event.body
            case .muted, .duplicate:
                break
            }
        }
    }

    private func recordCoordinatorInsertionRetry(
        outcome: DictationCompletionOutcome? = nil,
        error: Error? = nil
    ) async {
        let retry = await dictationCoordinator.handle(.retryInsertion)
        guard let retrySessionID = retry.sessionID else { return }
        coordinatorSessionID = retrySessionID
        if let outcome {
            _ = await dictationCoordinator.handle(
                .commitSucceeded(retrySessionID, outcome: outcome)
            )
        } else if let error {
            await reportCoordinatorFailure(error)
        }
    }

    private func throwInjectedFailure(
        at point: VoiceFaultPoint
    ) async throws {
        guard let failure = await faultInjector.failure(at: point) else {
            return
        }
        throw VoiceInjectedFailure(category: failure)
    }

    private func recordReliability(
        category: ReliabilityEventCategory,
        outcome: ReliabilityOutcome,
        latencyMetric: ReliabilityLatencyMetric? = nil,
        startedAt: TimeInterval? = nil
    ) {
        let latency: ReliabilityLatency?
        if let latencyMetric, let startedAt {
            latency = ReliabilityLatency(
                metric: latencyMetric,
                seconds: max(
                    0,
                    ProcessInfo.processInfo.systemUptime - startedAt
                )
            )
        } else {
            latency = nil
        }
        let event = ReliabilityEvent(
            category: category,
            outcome: outcome,
            latency: latency,
            modelVersion: SpeechModelVariant(
                rawValue: activeConfiguration.modelVersion
            ),
            supported: SystemCheck().supported
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await reliabilityLedger.record(event)
                onReliabilityChange?()
            } catch {
                recordOperationalIssue(.storage)
            }
        }
    }

    private func recordOperationalIssue(_ kind: OperationalIssueKind) {
        if (try? operationalIssueStore.record(kind)) != nil {
            onOperationalIssuesChange?()
        }
    }
}
