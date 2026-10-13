import Foundation

public enum VoiceError: LocalizedError, Equatable {
    case unsupportedPlatform
    case microphonePermissionDenied
    case microphoneUnavailable(String)
    case accessibilityPermissionDenied
    case noFocusedTextField
    case sensitiveTarget(SensitiveContextDenial)
    case insertionTargetChanged
    case textInsertionFailed
    case transcriptIsNotFinal
    case emptyTranscript
    case recordingTooShort
    case modelUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Autohand Voice requires macOS 14 or later on Apple Silicon."
        case .microphonePermissionDenied:
            return "Microphone access is denied. Enable Autohand Voice in System Settings → Privacy & Security → Microphone."
        case let .microphoneUnavailable(reason):
            return "The microphone could not be started: \(reason)"
        case .accessibilityPermissionDenied:
            return "Accessibility access is required to insert text. Enable Autohand Voice in System Settings → Privacy & Security → Accessibility."
        case .noFocusedTextField:
            return "No editable text field is focused. Your transcript was not inserted."
        case let .sensitiveTarget(reason):
            switch reason {
            case .secureField:
                return "Dictation is unavailable in password and secure text fields."
            case .builtInSensitiveApp:
                return "Dictation is paused because this app is classified as sensitive."
            case .localDenylist:
                return "Dictation is paused for this app by your local privacy settings."
            case .profileSensitive:
                return "Dictation is paused because this app profile is marked sensitive."
            }
        case .insertionTargetChanged:
            return "Focus moved after recording started. Your transcript was not inserted and can be retried."
        case .textInsertionFailed:
            return "The focused control rejected text insertion. Your transcript can be copied or retried."
        case .transcriptIsNotFinal:
            return "A provisional transcript cannot be inserted."
        case .emptyTranscript:
            return "No speech was recognized. Check the selected microphone, then try again."
        case .recordingTooShort:
            return "The recording was too short to transcribe."
        case let .modelUnavailable(reason):
            return "The local speech model is unavailable: \(reason)"
        }
    }
}
