import AppKit
import AutohandVoiceCore
import Observation
import ServiceManagement

@MainActor
@Observable
final class AppSettingsModel {
    let session: VoiceSession
    private(set) var systemCheck: SystemCheck
    private(set) var launchAtLoginEnabled = false
    private(set) var launchAtLoginAvailable = true
    private(set) var launchAtLoginStatus = "Not registered"
    private(set) var actionMessage: String?
    private(set) var audioInputDevices: [AudioInputDevice] = []
    private(set) var audioInputStatus = "Checking microphones…"
    @ObservationIgnored private var audioInputDeviceMonitor: AudioInputDeviceMonitor?

    init(session: VoiceSession) {
        self.session = session
        systemCheck = SystemCheck()
        refresh()
        audioInputDeviceMonitor = AudioInputDeviceMonitor { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshAudioInputDevices()
            }
        }
    }

    func refresh() {
        systemCheck = SystemCheck()
        let service = SMAppService.mainApp
        switch service.status {
        case .enabled:
            launchAtLoginAvailable = true
            launchAtLoginEnabled = true
            launchAtLoginStatus = "Enabled"
        case .requiresApproval:
            launchAtLoginAvailable = true
            launchAtLoginEnabled = false
            launchAtLoginStatus = "Approval required in System Settings"
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
    }

    func refreshAudioInputDevices() {
        do {
            audioInputDevices = try AudioInputDevices.available()
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

    func setAudioInputDevice(_ uid: String?) {
        session.stopMicrophoneTest()
        session.setAudioInputDevice(uid)
        refreshAudioInputDevices()
        actionMessage = selectedAudioInputDevice.map {
            "Microphone set to \($0.name)."
        } ?? "No input device is available."
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
                "Could not update launch at login: \(error.localizedDescription)"
            )
        }
        refresh()
    }

    func copyDiagnosticReport() {
        do {
            let report = DiagnosticReport(
                check: systemCheck,
                preferences: session.preferences
            )
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(try report.json(), forType: .string) else {
                actionMessage = "The diagnostic report could not be copied."
                return
            }
            actionMessage = "Redacted diagnostic report copied."
        } catch {
            actionMessage = "The diagnostic report could not be created."
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
}
