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

public enum FunctionKeyIntent: Equatable, Sendable {
    case none
    /// Fn went down: begin capturing now so the first words are kept.
    case start
    /// Fn stayed down past the hold threshold: this is a real dictation.
    case confirmHold
    /// Fn was released after a hold: stop and transcribe.
    case finish
    /// Fn was released before the threshold: a normal Fn tap, drop the audio.
    case discard
    /// Monitoring stopped during a hold.
    case cancel
}

/// Keeps modifier-only Fn handling deterministic and independent from AppKit.
/// Fn is always hold-to-talk. Capture starts on press so nothing is clipped;
/// a press shorter than the hold threshold is treated as a normal Fn tap and
/// its audio is discarded, so macOS keeps its Globe/Fn behavior.
public struct FunctionKeyLongPressReducer: Sendable {
    private enum State: Sendable {
        case idle
        case pending
        case holding
    }

    private var state: State = .idle

    public init() {}

    public mutating func reduce(
        _ event: FunctionKeyLongPressEvent
    ) -> FunctionKeyIntent {
        switch (state, event) {
        case (.idle, .pressed):
            state = .pending
            return .start
        case (.pending, .thresholdReached):
            state = .holding
            return .confirmHold
        case (.pending, .released), (.pending, .cancelled):
            state = .idle
            return .discard
        case (.holding, .released):
            state = .idle
            return .finish
        case (.holding, .cancelled):
            state = .idle
            return .cancel
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
