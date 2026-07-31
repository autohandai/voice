import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = Self(rawValue: 1 << 0)
    public static let option = Self(rawValue: 1 << 1)
    public static let shift = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
}

public enum RegisteredShortcutError: LocalizedError, Equatable {
    case modifierRequired
    case unsupportedKey

    public var errorDescription: String? {
        switch self {
        case .modifierRequired:
            "Choose at least one modifier key."
        case .unsupportedKey:
            "That key cannot be used as a registered shortcut."
        }
    }
}

public struct RegisteredShortcut: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt32
    public let modifiers: ShortcutModifiers

    public static let controlOptionSpace = Self(
        keyCode: 49,
        modifiers: [.control, .option]
    )

    public static let optionS = Self(
        keyCode: 1,
        modifiers: [.option]
    )

    public init(keyCode: UInt32, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public init(
        validatingKeyCode keyCode: UInt32,
        modifiers: ShortcutModifiers
    ) throws {
        guard !modifiers.isEmpty else {
            throw RegisteredShortcutError.modifierRequired
        }
        guard Self.keyNames[keyCode] != nil else {
            throw RegisteredShortcutError.unsupportedKey
        }
        self.init(keyCode: keyCode, modifiers: modifiers)
    }

    public var displayName: String {
        modifierSymbols + (Self.keyNames[keyCode]?.symbol ?? "Key \(keyCode)")
    }

    public var accessibilityName: String {
        let modifierNames = [
            modifiers.contains(.control) ? "Control" : nil,
            modifiers.contains(.option) ? "Option" : nil,
            modifiers.contains(.shift) ? "Shift" : nil,
            modifiers.contains(.command) ? "Command" : nil,
        ].compactMap { $0 }
        return (modifierNames + [Self.keyNames[keyCode]?.name ?? "Key \(keyCode)"])
            .joined(separator: " + ")
    }

    public var isValid: Bool {
        !modifiers.isEmpty && Self.keyNames[keyCode] != nil
    }

    private var modifierSymbols: String {
        [
            modifiers.contains(.control) ? "⌃" : nil,
            modifiers.contains(.option) ? "⌥" : nil,
            modifiers.contains(.shift) ? "⇧" : nil,
            modifiers.contains(.command) ? "⌘" : nil,
        ]
        .compactMap { $0 }
        .joined()
    }

    private struct KeyName {
        let symbol: String
        let name: String
    }

    private static let keyNames: [UInt32: KeyName] = [
        0: .init(symbol: "A", name: "A"),
        1: .init(symbol: "S", name: "S"),
        2: .init(symbol: "D", name: "D"),
        3: .init(symbol: "F", name: "F"),
        4: .init(symbol: "H", name: "H"),
        5: .init(symbol: "G", name: "G"),
        6: .init(symbol: "Z", name: "Z"),
        7: .init(symbol: "X", name: "X"),
        8: .init(symbol: "C", name: "C"),
        9: .init(symbol: "V", name: "V"),
        11: .init(symbol: "B", name: "B"),
        12: .init(symbol: "Q", name: "Q"),
        13: .init(symbol: "W", name: "W"),
        14: .init(symbol: "E", name: "E"),
        15: .init(symbol: "R", name: "R"),
        16: .init(symbol: "Y", name: "Y"),
        17: .init(symbol: "T", name: "T"),
        18: .init(symbol: "1", name: "1"),
        19: .init(symbol: "2", name: "2"),
        20: .init(symbol: "3", name: "3"),
        21: .init(symbol: "4", name: "4"),
        22: .init(symbol: "6", name: "6"),
        23: .init(symbol: "5", name: "5"),
        24: .init(symbol: "=", name: "Equals"),
        25: .init(symbol: "9", name: "9"),
        26: .init(symbol: "7", name: "7"),
        27: .init(symbol: "−", name: "Minus"),
        28: .init(symbol: "8", name: "8"),
        29: .init(symbol: "0", name: "0"),
        30: .init(symbol: "]", name: "Right Bracket"),
        31: .init(symbol: "O", name: "O"),
        32: .init(symbol: "U", name: "U"),
        33: .init(symbol: "[", name: "Left Bracket"),
        34: .init(symbol: "I", name: "I"),
        35: .init(symbol: "P", name: "P"),
        36: .init(symbol: "↩", name: "Return"),
        37: .init(symbol: "L", name: "L"),
        38: .init(symbol: "J", name: "J"),
        39: .init(symbol: "'", name: "Apostrophe"),
        40: .init(symbol: "K", name: "K"),
        41: .init(symbol: ";", name: "Semicolon"),
        42: .init(symbol: "\\", name: "Backslash"),
        43: .init(symbol: ",", name: "Comma"),
        44: .init(symbol: "/", name: "Slash"),
        45: .init(symbol: "N", name: "N"),
        46: .init(symbol: "M", name: "M"),
        47: .init(symbol: ".", name: "Period"),
        48: .init(symbol: "⇥", name: "Tab"),
        49: .init(symbol: "Space", name: "Space"),
        50: .init(symbol: "`", name: "Grave Accent"),
        51: .init(symbol: "⌫", name: "Delete"),
        96: .init(symbol: "F5", name: "F5"),
        97: .init(symbol: "F6", name: "F6"),
        98: .init(symbol: "F7", name: "F7"),
        99: .init(symbol: "F3", name: "F3"),
        100: .init(symbol: "F8", name: "F8"),
        101: .init(symbol: "F9", name: "F9"),
        109: .init(symbol: "F10", name: "F10"),
        111: .init(symbol: "F12", name: "F12"),
        118: .init(symbol: "F4", name: "F4"),
        120: .init(symbol: "F2", name: "F2"),
        122: .init(symbol: "F1", name: "F1"),
        123: .init(symbol: "←", name: "Left Arrow"),
        124: .init(symbol: "→", name: "Right Arrow"),
        125: .init(symbol: "↓", name: "Down Arrow"),
        126: .init(symbol: "↑", name: "Up Arrow"),
    ]
}

public enum RecordingMode: String, Codable, CaseIterable, Sendable {
    case pressAndHold = "press_and_hold"
    case toggle
    case handsFree = "hands_free"

    public var displayName: String {
        switch self {
        case .pressAndHold: "Press and Hold"
        case .toggle: "Toggle"
        case .handsFree: "Hands-Free"
        }
    }

    public func action(
        for event: ShortcutEvent,
        isRecording: Bool
    ) -> ShortcutAction {
        switch (self, event, isRecording) {
        case (_, .cancel, true) where self == .handsFree:
            .cancel
        case (.pressAndHold, .pressed, false):
            .start
        case (.pressAndHold, .released, true):
            .finish
        case (.toggle, .pressed, false),
             (.handsFree, .pressed, false):
            .start
        case (.toggle, .pressed, true),
             (.handsFree, .pressed, true):
            .finish
        default:
            .none
        }
    }
}

public enum ShortcutEvent: Sendable {
    case pressed
    case released
    case cancel
}

public enum ShortcutAction: Equatable, Sendable {
    case none
    case start
    case finish
    case cancel
}
