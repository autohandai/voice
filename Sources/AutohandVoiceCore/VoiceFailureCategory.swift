import Foundation

public enum PermissionKind: String, Codable, CaseIterable, Sendable {
    case microphone
    case accessibility
    case inputMonitoring = "input_monitoring"
    case notifications
}

public enum PermissionState: String, Codable, CaseIterable, Sendable {
    case denied
    case restricted
    case notDetermined = "not_determined"
    case revoked
}

public enum ShortcutFailure: String, Codable, CaseIterable, Sendable {
    case conflict
    case invalidBinding = "invalid_binding"
    case registrationFailed = "registration_failed"
}

public enum PointerFailure: String, Codable, CaseIterable, Sendable {
    case permissionDenied = "permission_denied"
    case eventTapUnavailable = "event_tap_unavailable"
    case bindingConflict = "binding_conflict"
    case targetLost = "target_lost"
}

public enum MicrophoneFailure: String, Codable, CaseIterable, Sendable {
    case unavailable
    case disconnected
    case muted
    case noSignal = "no_signal"
    case clipped
    case unsupportedFormat = "unsupported_format"
    case startFailed = "start_failed"
}

public enum AudioRouteFailure: String, Codable, CaseIterable, Sendable {
    case selectionFailed = "selection_failed"
    case routeChanged = "route_changed"
    case clamshellNoInput = "clamshell_no_input"
    case handoffFailed = "handoff_failed"
    case deviceBusy = "device_busy"
}

public enum CaptureFailure: String, Codable, CaseIterable, Sendable {
    case startFailed = "start_failed"
    case interrupted
    case bufferOverflow = "buffer_overflow"
    case tooShort = "too_short"
    case durationLimit = "duration_limit"
}

public enum ModelFailure: String, Codable, CaseIterable, Sendable {
    case unavailable
    case missing
    case invalid
    case compilationFailed = "compilation_failed"
    case loadFailed = "load_failed"
    case unsupportedLanguage = "unsupported_language"
}

public enum RecognitionFailure: String, Codable, CaseIterable, Sendable {
    case failed
    case emptyFinal = "empty_final"
    case timedOut = "timed_out"
    case provisionalNotFinal = "provisional_not_final"
}

public enum RevisionFailure: String, Codable, CaseIterable, Sendable {
    case failed
    case invalidOutput = "invalid_output"
    case modelUnavailable = "model_unavailable"
}

public enum TargetFailure: String, Codable, CaseIterable, Sendable {
    case noneFocused = "none_focused"
    case changed
    case secureField = "secure_field"
    case sensitiveApp = "sensitive_app"
    case unsupportedControl = "unsupported_control"
}

public enum InsertionFailure: String, Codable, CaseIterable, Sendable {
    case accessibilityDenied = "accessibility_denied"
    case rejected
    case clipboardRestoreFailed = "clipboard_restore_failed"
    case verificationFailed = "verification_failed"
}

public enum RecoveryFailure: String, Codable, CaseIterable, Sendable {
    case audioMissing = "audio_missing"
    case corrupt
    case expired
    case decryptFailed = "decrypt_failed"
}

public enum StorageFailure: String, Codable, CaseIterable, Sendable {
    case unavailable
    case corrupt
    case quotaExceeded = "quota_exceeded"
    case permissionDenied = "permission_denied"
}

public enum NotificationFailure: String, Codable, CaseIterable, Sendable {
    case permissionDenied = "permission_denied"
    case deliveryFailed = "delivery_failed"
    case actionUnavailable = "action_unavailable"
}

public enum SyncFailure: String, Codable, CaseIterable, Sendable {
    case unavailable
    case authenticationRequired = "authentication_required"
    case conflict
    case decryptFailed = "decrypt_failed"
}

public enum AccountFailure: String, Codable, CaseIterable, Sendable {
    case signedOut = "signed_out"
    case entitlementUnavailable = "entitlement_unavailable"
    case revoked
}

public enum VoiceFailureCategory: Codable, Equatable, Sendable {
    case unsupportedPlatform
    case permission(PermissionKind, PermissionState)
    case shortcut(ShortcutFailure)
    case pointer(PointerFailure)
    case microphone(MicrophoneFailure)
    case audioRoute(AudioRouteFailure)
    case capture(CaptureFailure)
    case model(ModelFailure)
    case recognition(RecognitionFailure)
    case revision(RevisionFailure)
    case target(TargetFailure)
    case insertion(InsertionFailure)
    case recovery(RecoveryFailure)
    case storage(StorageFailure)
    case notification(NotificationFailure)
    case sync(SyncFailure)
    case account(AccountFailure)

    public var code: String {
        switch self {
        case .unsupportedPlatform:
            "unsupported_platform"
        case let .permission(kind, state):
            "permission.\(kind.rawValue).\(state.rawValue)"
        case let .shortcut(failure):
            "shortcut.\(failure.rawValue)"
        case let .pointer(failure):
            "pointer.\(failure.rawValue)"
        case let .microphone(failure):
            "microphone.\(failure.rawValue)"
        case let .audioRoute(failure):
            "audio_route.\(failure.rawValue)"
        case let .capture(failure):
            "capture.\(failure.rawValue)"
        case let .model(failure):
            "model.\(failure.rawValue)"
        case let .recognition(failure):
            "recognition.\(failure.rawValue)"
        case let .revision(failure):
            "revision.\(failure.rawValue)"
        case let .target(failure):
            "target.\(failure.rawValue)"
        case let .insertion(failure):
            "insertion.\(failure.rawValue)"
        case let .recovery(failure):
            "recovery.\(failure.rawValue)"
        case let .storage(failure):
            "storage.\(failure.rawValue)"
        case let .notification(failure):
            "notification.\(failure.rawValue)"
        case let .sync(failure):
            "sync.\(failure.rawValue)"
        case let .account(failure):
            "account.\(failure.rawValue)"
        }
    }

    public var policy: VoiceFailurePolicy {
        switch self {
        case .unsupportedPlatform:
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: .useSupportedMac,
                retryIsIdempotent: false,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case let .permission(kind, _):
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: kind.remediation,
                retryIsIdempotent: false,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true,
                safeDiagnosticFields: [
                    .categoryCode,
                    .permissionKind,
                    .permissionState,
                ]
            )
        case .shortcut:
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: .resetShortcut,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case .pointer:
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: .openInputMonitoringSettings,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case .microphone:
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: .refreshMicrophones,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case .audioRoute:
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: .selectMicrophone,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case let .capture(failure):
            return VoiceFailurePolicy(
                recoverableArtifact: failure == .startFailed
                    ? .none
                    : .capturedAudio,
                primaryRemediation: .retryCapture,
                retryIsIdempotent: failure != .durationLimit,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case .model:
            return VoiceFailurePolicy(
                recoverableArtifact: .capturedAudio,
                primaryRemediation: .prepareLocalModel,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case let .recognition(failure):
            return VoiceFailurePolicy(
                recoverableArtifact: .capturedAudio,
                primaryRemediation: failure == .provisionalNotFinal
                    ? .waitForFinalTranscript
                    : .retryLocalRecognition,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case .revision:
            return VoiceFailurePolicy(
                recoverableArtifact: .finalTranscript,
                primaryRemediation: .useLiteralTranscript,
                retryIsIdempotent: true,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: true
            )
        case let .target(failure):
            let remediation: VoiceFailureRemediation
            switch failure {
            case .secureField:
                remediation = .chooseNonSecureField
            case .sensitiveApp:
                remediation = .reviewSensitiveAppPolicy
            case .noneFocused, .changed, .unsupportedControl:
                remediation = .refocusAndRetryInsertion
            }
            return VoiceFailurePolicy(
                recoverableArtifact: .finalTranscript,
                primaryRemediation: remediation,
                retryIsIdempotent: true,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: true
            )
        case .insertion:
            return VoiceFailurePolicy(
                recoverableArtifact: .finalTranscript,
                primaryRemediation: .copyFinalTranscript,
                retryIsIdempotent: true,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: true
            )
        case .recovery:
            return VoiceFailurePolicy(
                recoverableArtifact: .capturedAudio,
                primaryRemediation: .retryRecovery,
                retryIsIdempotent: true,
                canContinueWithLiteral: false,
                recordsReliabilityEvent: true
            )
        case .storage:
            return VoiceFailurePolicy(
                recoverableArtifact: .localData,
                primaryRemediation: .freeStorage,
                retryIsIdempotent: true,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: true
            )
        case let .notification(failure):
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: failure == .permissionDenied
                    ? .openNotificationSettings
                    : .retryNotification,
                retryIsIdempotent: true,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: true
            )
        case .sync:
            return VoiceFailurePolicy(
                recoverableArtifact: .localData,
                primaryRemediation: .continueOffline,
                retryIsIdempotent: true,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: false
            )
        case .account:
            return VoiceFailurePolicy(
                recoverableArtifact: .none,
                primaryRemediation: .signIn,
                retryIsIdempotent: false,
                canContinueWithLiteral: true,
                recordsReliabilityEvent: false
            )
        }
    }
}

public enum RecoverableVoiceArtifact: String, Codable, CaseIterable, Sendable {
    case none
    case capturedAudio = "captured_audio"
    case finalTranscript = "final_transcript"
    case localData = "local_data"
}

public enum VoiceFailureRemediation: String, Codable, CaseIterable, Sendable {
    case useSupportedMac = "use_supported_mac"
    case openMicrophoneSettings = "open_microphone_settings"
    case openAccessibilitySettings = "open_accessibility_settings"
    case openInputMonitoringSettings = "open_input_monitoring_settings"
    case openNotificationSettings = "open_notification_settings"
    case resetShortcut = "reset_shortcut"
    case refreshMicrophones = "refresh_microphones"
    case selectMicrophone = "select_microphone"
    case retryCapture = "retry_capture"
    case prepareLocalModel = "prepare_local_model"
    case retryLocalRecognition = "retry_local_recognition"
    case waitForFinalTranscript = "wait_for_final_transcript"
    case useLiteralTranscript = "use_literal_transcript"
    case refocusAndRetryInsertion = "refocus_and_retry_insertion"
    case chooseNonSecureField = "choose_non_secure_field"
    case reviewSensitiveAppPolicy = "review_sensitive_app_policy"
    case copyFinalTranscript = "copy_final_transcript"
    case retryRecovery = "retry_recovery"
    case freeStorage = "free_storage"
    case retryNotification = "retry_notification"
    case continueOffline = "continue_offline"
    case signIn = "sign_in"

    public var label: LocalizedStringResource {
        switch self {
        case .useSupportedMac: "Use a supported Mac"
        case .openMicrophoneSettings: "Open Microphone Settings"
        case .openAccessibilitySettings: "Open Accessibility Settings"
        case .openInputMonitoringSettings: "Open Input Monitoring Settings"
        case .openNotificationSettings: "Open Notification Settings"
        case .resetShortcut: "Reset Shortcut"
        case .refreshMicrophones: "Refresh Microphones"
        case .selectMicrophone: "Select a Microphone"
        case .retryCapture: "Try Recording Again"
        case .prepareLocalModel: "Prepare Local Model"
        case .retryLocalRecognition: "Retry Local Transcription"
        case .waitForFinalTranscript: "Wait for Final Transcript"
        case .useLiteralTranscript: "Use Literal Transcript"
        case .refocusAndRetryInsertion: "Refocus and Retry"
        case .chooseNonSecureField: "Choose a Non-Secure Field"
        case .reviewSensitiveAppPolicy: "Review Sensitive App Policy"
        case .copyFinalTranscript: "Copy Final Transcript"
        case .retryRecovery: "Retry Recovery"
        case .freeStorage: "Free Storage"
        case .retryNotification: "Retry Notification"
        case .continueOffline: "Continue Offline"
        case .signIn: "Sign In"
        }
    }
}

public enum VoiceFailureDiagnosticField: String, Codable, CaseIterable, Sendable {
    case categoryCode = "category_code"
    case permissionKind = "permission_kind"
    case permissionState = "permission_state"
}

public struct VoiceFailurePolicy: Codable, Equatable, Sendable {
    public let recoverableArtifact: RecoverableVoiceArtifact
    public let primaryRemediation: VoiceFailureRemediation
    public let retryIsIdempotent: Bool
    public let canContinueWithLiteral: Bool
    public let recordsReliabilityEvent: Bool
    public let safeDiagnosticFields: Set<VoiceFailureDiagnosticField>

    public init(
        recoverableArtifact: RecoverableVoiceArtifact,
        primaryRemediation: VoiceFailureRemediation,
        retryIsIdempotent: Bool,
        canContinueWithLiteral: Bool,
        recordsReliabilityEvent: Bool,
        safeDiagnosticFields: Set<VoiceFailureDiagnosticField> = [.categoryCode]
    ) {
        self.recoverableArtifact = recoverableArtifact
        self.primaryRemediation = primaryRemediation
        self.retryIsIdempotent = retryIsIdempotent
        self.canContinueWithLiteral = canContinueWithLiteral
        self.recordsReliabilityEvent = recordsReliabilityEvent
        self.safeDiagnosticFields = safeDiagnosticFields
    }
}

private extension PermissionKind {
    var remediation: VoiceFailureRemediation {
        switch self {
        case .microphone:
            .openMicrophoneSettings
        case .accessibility:
            .openAccessibilitySettings
        case .inputMonitoring:
            .openInputMonitoringSettings
        case .notifications:
            .openNotificationSettings
        }
    }
}

public extension VoiceError {
    var failureCategory: VoiceFailureCategory {
        switch self {
        case .unsupportedPlatform:
            .unsupportedPlatform
        case .microphonePermissionDenied:
            .permission(.microphone, .denied)
        case .microphoneUnavailable:
            .microphone(.startFailed)
        case .accessibilityPermissionDenied:
            .permission(.accessibility, .denied)
        case .noFocusedTextField:
            .target(.noneFocused)
        case let .sensitiveTarget(reason):
            reason == .secureField
                ? .target(.secureField)
                : .target(.sensitiveApp)
        case .insertionTargetChanged:
            .target(.changed)
        case .textInsertionFailed:
            .insertion(.rejected)
        case .transcriptIsNotFinal:
            .recognition(.provisionalNotFinal)
        case .emptyTranscript:
            .recognition(.emptyFinal)
        case .recordingTooShort:
            .capture(.tooShort)
        case .silentRecording:
            .microphone(.noSignal)
        case .modelUnavailable:
            .model(.unavailable)
        }
    }
}
