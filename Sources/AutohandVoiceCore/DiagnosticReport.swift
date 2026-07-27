import Foundation

public enum DiagnosticStatus: String, Codable, Sendable {
    case ready
    case attention
    case unavailable
    case informational
}

public enum DiagnosticRemediation: String, Codable, Sendable {
    case useSupportedMac
    case allowMicrophone
    case allowAccessibility
    case registerShortcut
    case refreshMicrophones
    case testMicrophone
    case prepareModel

    public var label: String {
        switch self {
        case .useSupportedMac: "Use macOS 14+ on Apple Silicon"
        case .allowMicrophone: "Open Microphone Settings"
        case .allowAccessibility: "Open Accessibility Settings"
        case .registerShortcut: "Reset Shortcut"
        case .refreshMicrophones: "Refresh Microphones"
        case .testMicrophone: "Test Microphone"
        case .prepareModel: "Prepare Local Model"
        }
    }
}

public enum DiagnosticCheckID: String, Codable, CaseIterable, Sendable {
    case platform
    case microphonePermission
    case accessibilityPermission
    case shortcut
    case microphone
    case signal
    case model
    case modelStorage
    case appVersion
    case remoteFallback
}

public struct DiagnosticCheck: Identifiable, Equatable, Sendable {
    public let id: DiagnosticCheckID
    public let title: String
    public let value: String
    public let status: DiagnosticStatus
    public let remediation: DiagnosticRemediation?

    public init(
        id: DiagnosticCheckID,
        title: String,
        value: String,
        status: DiagnosticStatus,
        remediation: DiagnosticRemediation? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.status = status
        self.remediation = remediation
    }
}

public enum DiagnosticShortcutState: String, Codable, Sendable {
    case registered
    case unavailable
    case notChecked = "not_checked"
}

public enum DiagnosticMicrophoneState: String, Codable, Sendable {
    case systemDefault = "system_default"
    case configured
    case unavailable
}

public enum DiagnosticModelState: String, Codable, Sendable {
    case ready
    case preparing
    case unavailable
    case notChecked = "not_checked"
}

public struct DiagnosticRuntime: Equatable, Sendable {
    public let shortcutState: DiagnosticShortcutState
    public let microphoneState: DiagnosticMicrophoneState
    public let microphoneDisplayName: String
    public let signal: AudioInputHealth
    public let modelState: DiagnosticModelState
    public let modelStorageBytes: Int64
    public let issues: [OperationalIssue]

    public init(
        shortcutState: DiagnosticShortcutState = .notChecked,
        microphoneState: DiagnosticMicrophoneState = .systemDefault,
        microphoneDisplayName: String = "System Default",
        signal: AudioInputHealth = .idle,
        modelState: DiagnosticModelState = .notChecked,
        modelStorageBytes: Int64 = 0,
        issues: [OperationalIssue] = []
    ) {
        self.shortcutState = shortcutState
        self.microphoneState = microphoneState
        self.microphoneDisplayName = microphoneDisplayName
        self.signal = signal
        self.modelState = modelState
        self.modelStorageBytes = max(0, modelStorageBytes)
        self.issues = issues
    }

    public static func commandLine(
        preferences: VoicePreferences,
        issues: [OperationalIssue]
    ) -> Self {
        let variant = SpeechModelVariant(
            rawValue: preferences.modelVersion
        ) ?? .default
        return Self(
            shortcutState: .notChecked,
            microphoneState: preferences.audioInputDeviceUID == nil
                ? .systemDefault
                : .configured,
            microphoneDisplayName: preferences.audioInputDeviceUID == nil
                ? "System Default"
                : "Configured microphone",
            signal: .idle,
            modelState: .notChecked,
            modelStorageBytes:
                (try? ModelCacheInspector.storageBytes(
                    at: variant.cacheDirectory
                )) ?? 0,
            issues: issues
        )
    }
}

public struct DiagnosticSnapshot: Equatable, Sendable {
    public let check: SystemCheck
    public let preferences: VoicePreferences
    public let runtime: DiagnosticRuntime

    public init(
        check: SystemCheck,
        preferences: VoicePreferences,
        runtime: DiagnosticRuntime = DiagnosticRuntime()
    ) {
        self.check = check
        self.preferences = preferences
        self.runtime = runtime
    }

    public var checks: [DiagnosticCheck] {
        [
            platformCheck,
            microphonePermissionCheck,
            accessibilityPermissionCheck,
            shortcutCheck,
            microphoneCheck,
            signalCheck,
            modelCheck,
            DiagnosticCheck(
                id: .modelStorage,
                title: "Model disk use",
                value: ByteCountFormatter.string(
                    fromByteCount: runtime.modelStorageBytes,
                    countStyle: .file
                ),
                status: .informational
            ),
            DiagnosticCheck(
                id: .appVersion,
                title: "App version",
                value: Brand.version,
                status: .informational
            ),
            DiagnosticCheck(
                id: .remoteFallback,
                title: "Remote fallback",
                value: "Disabled",
                status: .ready
            ),
        ]
    }

    public var report: DiagnosticReport {
        DiagnosticReport(
            check: check,
            preferences: preferences,
            runtime: runtime
        )
    }

    private var platformCheck: DiagnosticCheck {
        DiagnosticCheck(
            id: .platform,
            title: "Platform",
            value: check.supported
                ? "Supported"
                : "Unsupported (\(check.architecture), macOS \(check.macOSVersion))",
            status: check.supported ? .ready : .unavailable,
            remediation: check.supported ? nil : .useSupportedMac
        )
    }

    private var microphonePermissionCheck: DiagnosticCheck {
        let ready = check.microphonePermission == "authorized"
        return DiagnosticCheck(
            id: .microphonePermission,
            title: "Microphone permission",
            value: check.microphonePermission,
            status: ready ? .ready : .unavailable,
            remediation: ready ? nil : .allowMicrophone
        )
    }

    private var accessibilityPermissionCheck: DiagnosticCheck {
        DiagnosticCheck(
            id: .accessibilityPermission,
            title: "Accessibility permission",
            value: check.accessibilityPermission
                ? "Authorized"
                : "Not authorized",
            status: check.accessibilityPermission ? .ready : .unavailable,
            remediation: check.accessibilityPermission
                ? nil
                : .allowAccessibility
        )
    }

    private var shortcutCheck: DiagnosticCheck {
        DiagnosticCheck(
            id: .shortcut,
            title: "Registered shortcut",
            value: runtime.shortcutState == .registered
                ? preferences.shortcut.accessibilityName
                : runtime.shortcutState.rawValue,
            status: runtime.shortcutState == .registered
                ? .ready
                : runtime.shortcutState == .notChecked
                    ? .informational
                    : .unavailable,
            remediation: runtime.shortcutState == .unavailable
                ? .registerShortcut
                : nil
        )
    }

    private var microphoneCheck: DiagnosticCheck {
        DiagnosticCheck(
            id: .microphone,
            title: "Selected microphone",
            value: runtime.microphoneDisplayName,
            status: runtime.microphoneState == .unavailable
                ? .unavailable
                : .ready,
            remediation: runtime.microphoneState == .unavailable
                ? .refreshMicrophones
                : nil
        )
    }

    private var signalCheck: DiagnosticCheck {
        let status: DiagnosticStatus
        let remediation: DiagnosticRemediation?
        switch runtime.signal {
        case .healthy:
            status = .ready
            remediation = nil
        case .idle, .listening:
            status = .attention
            remediation = .testMicrophone
        case .noSignal, .clipping, .disconnected:
            status = .unavailable
            remediation = .testMicrophone
        }
        return DiagnosticCheck(
            id: .signal,
            title: "Live signal",
            value: runtime.signal.label,
            status: status,
            remediation: remediation
        )
    }

    private var modelCheck: DiagnosticCheck {
        let status: DiagnosticStatus
        switch runtime.modelState {
        case .ready: status = .ready
        case .preparing: status = .attention
        case .notChecked: status = .informational
        case .unavailable: status = .unavailable
        }
        return DiagnosticCheck(
            id: .model,
            title: "Local model",
            value: runtime.modelState.rawValue,
            status: status,
            remediation: runtime.modelState == .unavailable
                || runtime.modelState == .notChecked
                ? .prepareModel
                : nil
        )
    }
}

public struct DiagnosticIssueReport: Codable, Equatable, Sendable {
    public let kind: OperationalIssueKind
    public let count: Int
    public let firstSeenAt: Date
    public let lastSeenAt: Date
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public let product: String
    public let version: String
    public let supported: Bool
    public let architecture: String
    public let macOSVersion: String
    public let microphonePermission: String
    public let accessibilityPermission: Bool
    public let shortcut: String
    public let shortcutState: DiagnosticShortcutState
    public let selectedMicrophone: DiagnosticMicrophoneState
    public let signal: AudioInputHealth
    public let speechEngine: String
    public let modelVersion: String
    public let modelState: DiagnosticModelState
    public let modelStorageBytes: Int64
    public let dictationLanguageCode: String
    public let recentOperationalIssues: [DiagnosticIssueReport]
    public let remoteFallbackEnabled: Bool

    public init(
        check: SystemCheck,
        preferences: VoicePreferences,
        runtime: DiagnosticRuntime = DiagnosticRuntime()
    ) {
        product = Brand.productName
        version = Brand.version
        supported = check.supported
        architecture = check.architecture
        macOSVersion = check.macOSVersion
        microphonePermission = check.microphonePermission
        accessibilityPermission = check.accessibilityPermission
        shortcut = preferences.shortcut.accessibilityName
        shortcutState = runtime.shortcutState
        selectedMicrophone = runtime.microphoneState
        signal = runtime.signal
        speechEngine = preferences.engine.rawValue
        modelVersion = preferences.modelVersion
        modelState = runtime.modelState
        modelStorageBytes = runtime.modelStorageBytes
        dictationLanguageCode = preferences.dictationLanguageCode
        recentOperationalIssues = runtime.issues.map {
            DiagnosticIssueReport(
                kind: $0.kind,
                count: $0.count,
                firstSeenAt: $0.firstSeenAt,
                lastSeenAt: $0.lastSeenAt
            )
        }
        remoteFallbackEnabled = check.remoteFallbackEnabled
    }

    public func json() throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}
