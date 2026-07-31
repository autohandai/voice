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
/// its normal Globe/Fn behavior.
public struct FunctionKeyLongPressReducer: Sendable {
    private enum State: Sendable {
        case idle
        case pending
        case active
    }

    private var state: State = .idle

    public init() {}

    public mutating func reduce(
        _ event: FunctionKeyLongPressEvent
    ) -> DictationInputIntent {
        switch (state, event) {
        case (.idle, .pressed):
            state = .pending
            return .none
        case (.pending, .thresholdReached):
            state = .active
            return .start
        case (.pending, .released), (.pending, .cancelled):
            state = .idle
            return .none
        case (.active, .released):
            state = .idle
            return .finish
        case (.active, .cancelled):
            state = .idle
            return .cancel
        default:
            return .none
        }
    }
}
