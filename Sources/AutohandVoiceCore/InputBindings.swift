import Foundation

public enum InputBindingAction: String, Codable, CaseIterable, Sendable {
    case startStop
    case holdToTalk
    case cancel
    case commit

    public var displayName: String {
        switch self {
        case .startStop: "Start or Stop"
        case .holdToTalk: "Hold to Talk"
        case .cancel: "Cancel"
        case .commit: "Commit or Enter"
        }
    }
}

public enum InputTrigger: Codable, Equatable, Hashable, Sendable {
    case keyboard(RegisteredShortcut)
    case pointer(button: Int)

    public var pointerButton: Int? {
        guard case let .pointer(button) = self else { return nil }
        return button
    }
}

public struct InputBinding: Codable, Equatable, Hashable, Sendable {
    public let action: InputBindingAction
    public let trigger: InputTrigger

    public init(action: InputBindingAction, trigger: InputTrigger) {
        self.action = action
        self.trigger = trigger
    }
}

public enum InputConfigurationError:
    Error,
    Equatable,
    LocalizedError,
    Sendable
{
    case tooManyBindings
    case conflictingTrigger
    case reservedPointerButton
    case unsupportedPointerButton
    case invalidKeyboardShortcut

    public var errorDescription: String? {
        switch self {
        case .tooManyBindings:
            "Use no more than four active input bindings."
        case .conflictingTrigger:
            "That trigger is already assigned to another action."
        case .reservedPointerButton:
            "Primary and secondary click cannot control dictation."
        case .unsupportedPointerButton:
            "Choose a discoverable mouse button between 3 and 32."
        case .invalidKeyboardShortcut:
            "Choose a supported keyboard shortcut with a modifier."
        }
    }
}

public struct InputConfiguration: Codable, Equatable, Sendable {
    public static let maximumBindings = 4
    public static let maximumPointerButton = 31

    public private(set) var bindings: [InputBinding]

    public init(bindings: [InputBinding] = []) throws {
        guard bindings.count <= Self.maximumBindings else {
            throw InputConfigurationError.tooManyBindings
        }
        var triggers = Set<InputTrigger>()
        for binding in bindings {
            guard triggers.insert(binding.trigger).inserted else {
                throw InputConfigurationError.conflictingTrigger
            }
            switch binding.trigger {
            case let .keyboard(shortcut):
                guard shortcut.isValid else {
                    throw InputConfigurationError.invalidKeyboardShortcut
                }
            case let .pointer(button):
                guard button > 1 else {
                    throw InputConfigurationError.reservedPointerButton
                }
                guard button <= Self.maximumPointerButton else {
                    throw InputConfigurationError.unsupportedPointerButton
                }
            }
        }
        self.bindings = bindings
    }

    public mutating func replaceBindings(
        _ bindings: [InputBinding]
    ) throws {
        let replacement = try Self(bindings: bindings)
        self = replacement
    }
}

public enum InputTriggerEvent: Sendable {
    case pressed
    case released
}

public enum DictationInputIntent: Equatable, Sendable {
    case none
    case toggle
    case start
    case finish
    case cancel
    case commit
}

public struct InputBindingReducer: Sendable {
    private var pressedTriggers = Set<InputTrigger>()

    public init() {}

    public mutating func reduce(
        _ event: InputTriggerEvent,
        binding: InputBinding
    ) -> DictationInputIntent {
        switch event {
        case .pressed:
            guard pressedTriggers.insert(binding.trigger).inserted else {
                return .none
            }
            switch binding.action {
            case .startStop:
                return .toggle
            case .holdToTalk:
                return .start
            case .cancel:
                return .cancel
            case .commit:
                return .commit
            }
        case .released:
            guard pressedTriggers.remove(binding.trigger) != nil else {
                return .none
            }
            return binding.action == .holdToTalk ? .finish : .none
        }
    }
}
