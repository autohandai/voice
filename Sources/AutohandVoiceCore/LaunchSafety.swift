import Foundation

/// A secret kept in the Keychain and read only when first needed. Reading
/// the Keychain at launch makes macOS ask for the login password whenever
/// the app's signature changed (every ad-hoc signed update), so callers load
/// it lazily, the first time a feature that needs it is used.
public struct DeferredCredential<Value> {
    private enum State {
        case unread
        case loaded(Value?)
    }

    private let load: () throws -> Value?
    private var state = State.unread

    public init(load: @escaping () throws -> Value?) {
        self.load = load
    }

    /// The stored value, reading the Keychain once. A failed read (for
    /// example a denied prompt) is not remembered, so it can be retried.
    public mutating func value() throws -> Value? {
        if case let .loaded(value) = state { return value }
        let value = try load()
        state = .loaded(value)
        return value
    }

    public mutating func store(_ value: Value) {
        state = .loaded(value)
    }

    public mutating func clear() {
        state = .loaded(nil)
    }
}

/// Keeps "Launch at Login" true to the person's choice. Replacing the app
/// with an update can leave the system login item unregistered, so the app
/// checks at every launch.
public enum LaunchAtLoginReconciliation {
    /// Mirrors `SMAppService.Status`, which Core cannot import.
    public enum SystemStatus: Equatable, Sendable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound
    }

    public enum Action: Equatable, Sendable {
        case none
        case register
        /// Login items are switched off for the app in System Settings.
        case askForApproval
        /// Turned on outside the app; remember it as the person's choice.
        case adoptEnabled
    }

    public static func action(wanted: Bool, status: SystemStatus) -> Action {
        switch (wanted, status) {
        case (true, .notRegistered), (true, .notFound):
            .register
        case (true, .requiresApproval):
            .askForApproval
        case (false, .enabled):
            .adoptEnabled
        default:
            .none
        }
    }
}
