import AppKit
import AutohandVoiceCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppSettingsModel {
    let session: VoiceSession
    let vocabulary: VocabularySettingsModel
    let appProfiles: AppProfileSettingsModel
    private(set) var systemCheck: SystemCheck
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginAvailable = true
    private(set) var launchAtLoginStatus = "Not registered"
    private(set) var actionMessage: String?
    private(set) var audioInputDevices: [AudioInputDevice] = []
    private(set) var audioInputStatus = "Checking microphones…"
    private(set) var operationalIssues: [OperationalIssue] = []
    private(set) var reliabilityStatus = "Loading local aggregates…"
    @ObservationIgnored private var audioInputDeviceMonitor: AudioInputDeviceMonitor?
    @ObservationIgnored private let operationalIssueStore =
        OperationalIssueStore()
    @ObservationIgnored private let reliabilityLedger = ReliabilityLedger()

    init(session: VoiceSession) {
        self.session = session
        vocabulary = VocabularySettingsModel(session: session)
        appProfiles = AppProfileSettingsModel(session: session)
        systemCheck = SystemCheck()
        session.onOperationalIssuesChange = { [weak self] in
            self?.refreshOperationalIssues()
        }
        session.onReliabilityChange = { [weak self] in
            self?.refreshReliability()
        }
        session.onLocalDataReset = { [weak self] in
            self?.vocabulary.reload()
            self?.appProfiles.reload()
            self?.refresh()
        }
        refresh()
        installAudioInputDeviceMonitor()
    }

    private func installAudioInputDeviceMonitor() {
        audioInputDeviceMonitor = AudioInputDeviceMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAudioInputDevices()
            }
        }
    }

    func restoreAfterLifecycleChange() {
        audioInputDeviceMonitor = nil
        installAudioInputDeviceMonitor()
        refresh()
    }

    func refresh() {
        systemCheck = SystemCheck()
        vocabulary.reload()
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            launchAtLoginAvailable = true
            launchAtLoginEnabled = true
            launchAtLoginStatus = "Enabled"
        case .requiresApproval:
            launchAtLoginAvailable = true
            launchAtLoginEnabled = false
            launchAtLoginStatus =
                "Approval required or disabled in System Settings"
        case .notRegistered:
            launchAtLoginAvailable = true
            launchAtLoginEnabled = false
            launchAtLoginStatus = "Not registered"
        case .notFound:
            launchAtLoginAvailable = false
            launchAtLoginEnabled = false
            launchAtLoginStatus = "Unavailable for this build"
        @unknown default:
            launchAtLoginAvailable = false
            launchAtLoginEnabled = false
            launchAtLoginStatus = "Unknown"
        }
        refreshAudioInputDevices()
        refreshOperationalIssues()
        refreshReliability()
    }

    func recheckPermissions() {
        session.restoreFunctionKeyMonitoringAfterLifecycleChange()
        session.restorePointerMonitoringAfterLifecycleChange()
        refresh()
    }

    func refreshAudioInputDevices() {
        do {
            audioInputDevices = try AudioInputDevices.available()
            session.handleAudioInputDevicesChanged(audioInputDevices)
            if let selectedUID = session.preferences.audioInputDeviceUID,
               !audioInputDevices.contains(where: { $0.id == selectedUID }) {
                audioInputStatus = "Selected microphone is disconnected."
                session.reportAudioInputDisconnected()
            } else {
                let selected = selectedAudioInputDevice
                audioInputStatus = selected.map {
                    $0.isSystemDefault
                        ? "\($0.name) · system default"
                        : $0.name
                } ?? "No input device is available."
                session.reportAudioInputAvailable(
                    name: selected?.name ?? "System Default"
                )
            }
        } catch {
            audioInputDevices = []
            audioInputStatus = error.localizedDescription
            session.reportAudioInputDisconnected()
        }
    }

    var selectedAudioInputDevice: AudioInputDevice? {
        if let selectedUID = session.preferences.audioInputDeviceUID {
            return audioInputDevices.first { $0.id == selectedUID }
        }
        return audioInputDevices.first { $0.isSystemDefault }
    }

    var audioInputPriority: [String] {
        let available = [
            AudioRoutePolicy.systemDefaultSentinel,
        ] + audioInputDevices.map(\.id)
        let configured = session.preferences.audioInputDevicePriority
        var seen = Set<String>()
        return (configured + available).filter {
            seen.insert($0).inserted
        }
        .prefix(AudioRoutePolicy.maximumRankedDevices)
        .map { $0 }
    }

    func audioInputPriorityLabel(_ identifier: String) -> String {
        if identifier == AudioRoutePolicy.systemDefaultSentinel {
            return "System Default"
        }
        return audioInputDevices.first {
            $0.id == identifier
        }?.name ?? "Unavailable microphone"
    }

    func moveAudioInputPriority(
        _ identifier: String,
        offset: Int
    ) {
        var values = audioInputPriority
        guard let index = values.firstIndex(of: identifier) else {
            return
        }
        let destination = min(
            max(0, index + offset),
            values.count - 1
        )
        guard destination != index else { return }
        values.remove(at: index)
        values.insert(identifier, at: destination)
        session.setAudioInputPriority(values)
        session.handleAudioInputDevicesChanged(audioInputDevices)
    }

    func setAudioInputDevice(_ uid: String?) {
        session.stopMicrophoneTest()
        session.setAudioInputDevice(uid)
        refreshAudioInputDevices()
        actionMessage = selectedAudioInputDevice.map {
            "Microphone set to \($0.name)."
        } ?? "No input device is available."
    }

    func setShortcut(_ shortcut: RegisteredShortcut) {
        if session.setShortcut(shortcut) {
            actionMessage = "Shortcut set to \(shortcut.accessibilityName)."
        } else {
            actionMessage = "That shortcut is already used by another app."
        }
    }

    func setScratchpadShortcut(_ shortcut: RegisteredShortcut) {
        actionMessage = session.setScratchpadShortcut(shortcut)
            ? "Scratchpad shortcut set to \(shortcut.accessibilityName)."
            : session.scratchpadShortcutError
    }

    func reportShortcutError(_ error: Error) {
        actionMessage = error.localizedDescription
    }

    var selectedModelVariant: SpeechModelVariant {
        SpeechModelVariant(
            rawValue: session.preferences.modelVersion
        ) ?? .default
    }

    var selectedDictationLanguage: SupportedDictationLanguage {
        SupportedDictationLanguage(
            rawValue: session.preferences.dictationLanguageCode
        ) ?? .english
    }

    var supportedLanguages: [SupportedDictationLanguage] {
        selectedModelVariant.supportedLanguages
    }

    var modelStorageLabel: String {
        guard session.modelStorageBytes > 0 else { return "Not measured" }
        return ByteCountFormatter.string(
            fromByteCount: session.modelStorageBytes,
            countStyle: .file
        )
    }

    var modelLastValidatedLabel: String {
        session.modelLastValidated?.formatted(
            date: .abbreviated,
            time: .shortened
        ) ?? "Not validated"
    }

    func requestMicrophonePermission() async {
        let granted = await session.requestMicrophonePermissionResult()
        actionMessage = granted
            ? "Microphone access is ready."
            : "Microphone access was not granted."
        refresh()
    }

    func requestAccessibilityPermission() {
        let granted = TextInserter().hasAccessibilityPermission(prompt: true)
        actionMessage = granted
            ? "Accessibility access is ready."
            : "Approve Accessibility access in System Settings, then check again."
        refresh()
    }

    func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard launchAtLoginAvailable else {
            actionMessage = "Launch at login is unavailable for this build."
            return
        }
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            session.setLaunchAtLogin(enabled)
            actionMessage = enabled
                ? "Autohand Voice will launch when you log in."
                : "Launch at login is disabled."
        } catch {
            actionMessage = "Could not update launch at login: \(error.localizedDescription)"
            session.reportFailure(
                "Could not update launch at login: \(error.localizedDescription)",
                kind: .settings
            )
        }
        refresh()
    }

    func copyDiagnosticReport() {
        do {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(
                try diagnosticSnapshot.report.json(),
                forType: .string
            ) else {
                actionMessage = "The diagnostic report could not be copied."
                return
            }
            actionMessage = "Redacted diagnostic report copied."
        } catch {
            actionMessage = "The diagnostic report could not be created."
        }
    }

    var diagnosticSnapshot: DiagnosticSnapshot {
        DiagnosticSnapshot(
            check: systemCheck,
            preferences: session.preferences,
            runtime: DiagnosticRuntime(
                shortcutState: session.shortcutRegistrationState,
                microphoneState: microphoneDiagnosticState,
                microphoneDisplayName: selectedAudioInputDevice?.name
                    ?? session.audioInputName,
                signal: session.audioInputHealth,
                modelState: modelDiagnosticState,
                modelStorageBytes: session.modelStorageBytes,
                issues: operationalIssues
            )
        )
    }

    func performDiagnosticRemediation(
        _ remediation: DiagnosticRemediation
    ) {
        switch remediation {
        case .useSupportedMac:
            actionMessage =
                "Autohand Voice requires macOS 14 or later."
        case .allowMicrophone:
            openMicrophoneSettings()
        case .allowAccessibility:
            openAccessibilitySettings()
        case .registerShortcut:
            _ = session.setShortcut(.controlOptionSpace)
        case .refreshMicrophones:
            refreshAudioInputDevices()
        case .testMicrophone:
            session.startMicrophoneTest()
        case .prepareModel:
            session.prepareLocalModel()
        }
        refresh()
    }

    func clearOperationalIssues() {
        do {
            try operationalIssueStore.reset()
            operationalIssues = []
            actionMessage = "Recent operational issues cleared."
        } catch {
            actionMessage = "Recent operational issues could not be cleared."
        }
    }

    func copyReliabilityReport() {
        Task {
            do {
                let data = try await reliabilityLedger.exportRedacted()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                guard pasteboard.setString(
                    String(decoding: data, as: UTF8.self),
                    forType: .string
                ) else {
                    actionMessage =
                        "The reliability report could not be copied."
                    return
                }
                actionMessage = "Redacted reliability report copied."
            } catch {
                actionMessage =
                    "The reliability report could not be created."
            }
        }
    }

    func clearReliabilityAggregates() {
        Task {
            do {
                try await reliabilityLedger.reset()
                reliabilityStatus = "No reliability events recorded"
                actionMessage = "Reliability aggregates cleared."
            } catch {
                actionMessage =
                    "Reliability aggregates could not be cleared."
            }
        }
    }

    private func refreshOperationalIssues() {
        do {
            operationalIssues = try operationalIssueStore.load()
        } catch {
            operationalIssues = []
            actionMessage = "Recent operational issues could not be loaded."
        }
    }

    private func refreshReliability() {
        Task {
            do {
                let now = Date()
                let snapshot = try await reliabilityLedger.snapshot(
                    DateInterval(
                        start: now.addingTimeInterval(
                            -ReliabilityLedger.maximumAge
                        ),
                        end: now
                    ),
                    now: now
                )
                let eventCount = snapshot.rows.reduce(0) { total, row in
                    total + row.counters.reduce(0) {
                        $0 + $1.count
                    }
                }
                reliabilityStatus = eventCount == 0
                    ? "No reliability events recorded"
                    : "\(eventCount.formatted()) events across "
                        + "\(snapshot.rows.count.formatted()) daily rows"
            } catch {
                reliabilityStatus =
                    "Reliability aggregates could not be loaded"
            }
        }
    }

    func completeOnboarding() {
        session.completeOnboarding()
        actionMessage = "Setup complete. Autohand Voice is ready."
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private var microphoneDiagnosticState: DiagnosticMicrophoneState {
        guard selectedAudioInputDevice != nil else { return .unavailable }
        return session.preferences.audioInputDeviceUID == nil
            ? .systemDefault
            : .configured
    }

    private var modelDiagnosticState: DiagnosticModelState {
        switch session.modelState {
        case .notChecked: .notChecked
        case .preparing: .preparing
        case .ready: .ready
        case .failed: .unavailable
        }
    }
}
