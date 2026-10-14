import Foundation

public enum VoiceActivationMethod: Equatable, Sendable {
    case functionKeyLongPress
    case keyboard(RegisteredShortcut)
}

public enum FunctionKeyLongPressEvent: Sendable {
    case pressed
    case thresholdReached
    case released
    case cancelled
}

/// Keeps modifier-only Fn handling deterministic and independent from AppKit.
/// A short press intentionally produces no dictation intent so macOS retains
/// its normal Globe/Fn behavior. Fn follows the recording mode: Press and Hold
/// finishes on release; Toggle and Hands-Free keep recording after release and
/// finish on the next Fn press.
public struct FunctionKeyLongPressReducer: Sendable {
    private enum State: Sendable {
        case idle
        case pending
        case holding
        case latched
        case finishing
    }

    private var state: State = .idle

    public init() {}

    public mutating func reduce(
        _ event: FunctionKeyLongPressEvent,
        mode: RecordingMode = .pressAndHold,
        isRecording: Bool = false
    ) -> DictationInputIntent {
        switch (state, event) {
        case (.idle, .pressed):
            if isRecording, mode != .pressAndHold {
                state = .finishing
                return .finish
            }
            state = .pending
            return .none
        case (.pending, .thresholdReached):
            state = mode == .pressAndHold ? .holding : .latched
            return .start
        case (.pending, .released), (.pending, .cancelled):
            state = .idle
            return .none
        case (.holding, .released):
            state = .idle
            return .finish
        case (.holding, .cancelled), (.latched, .cancelled):
            state = .idle
            return .cancel
        case (.latched, .released),
             (.finishing, .released),
             (.finishing, .cancelled):
            state = .idle
            return .none
        default:
            return .none
        }
    }
}

/// macOS Dictation can start on a double Fn press, which collides with Fn
/// activation. The shortcut itself is not stored while it is the default, so
/// Dictation being enabled is the reliable signal.
public enum MacOSDictationConflict {
    public static func isLikely(
        functionKeyEnabled: Bool,
        macOSDictationEnabled: Bool
    ) -> Bool {
        functionKeyEnabled && macOSDictationEnabled
    }

    public static func macOSDictationEnabled(
        readPreference: (_ key: String, _ domain: String) -> Any?
    ) -> Bool {
        let value = readPreference(
            "Dictation Enabled",
            "com.apple.assistant.support"
        )
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    public static func macOSDictationEnabled() -> Bool {
        macOSDictationEnabled { key, domain in
            CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        }
    }
}
