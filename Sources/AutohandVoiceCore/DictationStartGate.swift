import Foundation

/// Decides whether a new recording may start. A previous failure is only
/// reported; it never blocks the next attempt unless audio is still held for
/// recovery.
public struct DictationStartGate: Equatable, Sendable {
    public enum Activity: Equatable, Sendable {
        case ready
        case failed
        case busy
    }

    public var isEnabled = true
    public var activity: Activity = .ready
    public var modelReady = true
    public var isTestingMicrophone = false
    public var hasRecoverableAudio = false
    public var isCheckingPersistentRecovery = false
    public var hasPendingPersistentRecovery = false
    public var isFileTranscriptionActive = false

    public init() {}

    public var canStart: Bool {
        isEnabled
            && activity != .busy
            && modelReady
            && !isTestingMicrophone
            && !hasRecoverableAudio
            && !isCheckingPersistentRecovery
            && !hasPendingPersistentRecovery
            && !isFileTranscriptionActive
    }
}

public enum FailedCaptureRecoveryPolicy {
    /// Audio that produced no words, or too little audio to transcribe, cannot
    /// succeed on retry, so it is erased instead of held for recovery.
    public static func retainsAudio(after error: Error) -> Bool {
        if error as? RevisionError == .emptyText {
            return false
        }
        switch error as? VoiceError {
        case .emptyTranscript?, .recordingTooShort?:
            return false
        default:
            return true
        }
    }
}
