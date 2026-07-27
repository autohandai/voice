import AppKit
import ApplicationServices
import AutohandVoiceCore
import Carbon
import Foundation

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.squareLength
    )
    private let session = VoiceSession()
    private var hotKeyMonitor: HotKeyMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var recordingHUDController: RecordingHUDController?
    private var workspaceObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        session.onChange = { [weak self] in
            self?.rebuildMenu()
            self?.recordingHUDController?.update()
            self?.hotKeyMonitor?.synchronizeCancellationHotKey()
        }
        settingsWindowController = SettingsWindowController(session: session)
        recordingHUDController = RecordingHUDController(session: session)
        hotKeyMonitor = HotKeyMonitor(session: session)
        session.onShortcutRegistration = { [weak self] shortcut in
            self?.hotKeyMonitor?.updateShortcut(shortcut)
                ?? OSStatus(eventNotHandledErr)
        }
        let hotKeyStatus = hotKeyMonitor?.start() ?? OSStatus(eventNotHandledErr)
        if hotKeyStatus != noErr {
            session.reportFailure(
                "\(session.preferences.shortcut.accessibilityName) "
                    + "could not be registered (\(hotKeyStatus))."
            )
        }
        observeWorkspaceLifecycle()
        rebuildMenu()
        recordingHUDController?.update()
        session.prepareLocalModel()
        if !session.preferences.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController?.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    private func rebuildMenu() {
        statusItem.button?.image = NSImage(
            systemSymbolName: session.statusSymbol,
            accessibilityDescription: session.statusLabel
        )
        statusItem.button?.toolTip = "Autohand Voice — \(session.statusLabel)"

        let menu = NSMenu()
        let status = NSMenuItem(
            title: session.statusLabel,
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if session.state == .recording || session.state == .starting {
            menu.addItem(
                item("Stop Recording", action: #selector(stopRecording))
            )
            if session.preferences.recordingMode == .handsFree {
                menu.addItem(
                    item(
                        "Cancel Recording",
                        action: #selector(cancelRecording)
                    )
                )
            }
        } else {
            let record = item(
                "Start Recording",
                action: #selector(startRecording)
            )
            record.isEnabled = session.canStartRecording
            menu.addItem(record)
        }

        if session.lastTranscript != nil {
            menu.addItem(
                item(
                    "Copy Last Transcript",
                    action: #selector(copyLastTranscript)
                )
            )
        }

        if session.pendingTranscript != nil {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    "Retry at Current Cursor",
                    action: #selector(retryPendingTranscript)
                )
            )
            menu.addItem(
                item(
                    "Copy Failed Dictation",
                    action: #selector(copyPendingTranscript)
                )
            )
            menu.addItem(
                item(
                    "Discard Failed Dictation",
                    action: #selector(discardPendingTranscript)
                )
            )
        }

        menu.addItem(.separator())
        addPermissionItems(to: menu)
        menu.addItem(outputMenu())
        menu.addItem(shortcutMenu())
        menu.addItem(recordingModeMenu())

        let sounds = item("Sound Feedback", action: #selector(toggleSounds))
        sounds.state = session.preferences.playSounds ? .on : .off
        menu.addItem(sounds)

        let enabled = item(
            session.isEnabled ? "Pause Dictation" : "Resume Dictation",
            action: #selector(toggleEnabled)
        )
        menu.addItem(enabled)

        if case .failed = session.state {
            menu.addItem(item("Dismiss Error", action: #selector(dismissError)))
        }

        menu.addItem(.separator())
        menu.addItem(
            item("Settings…", action: #selector(showSettings), key: ",")
        )
        menu.addItem(
            item("Quit Autohand Voice", action: #selector(quit), key: "q")
        )
        statusItem.menu = menu
    }

    private func addPermissionItems(to menu: NSMenu) {
        let check = SystemCheck()
        if check.microphonePermission != "authorized" {
            menu.addItem(
                item(
                    "Open Microphone Settings…",
                    action: #selector(openMicrophoneSettings)
                )
            )
        }
        if !check.accessibilityPermission {
            menu.addItem(
                item(
                    "Open Accessibility Settings…",
                    action: #selector(openAccessibilitySettings)
                )
            )
        }
        if check.microphonePermission != "authorized"
            || !check.accessibilityPermission {
            menu.addItem(.separator())
        }
    }

    private func outputMenu() -> NSMenuItem {
        let parent = NSMenuItem(title: "Output", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        for mode in OutputMode.allCases {
            let title = mode == .type ? "Insert at Cursor" : "Copy to Clipboard"
            let child = item(title, action: #selector(selectOutputMode))
            child.representedObject = mode.rawValue
            child.state = session.preferences.outputMode == mode ? .on : .off
            menu.addItem(child)
        }
        parent.submenu = menu
        return parent
    }

    private func shortcutMenu() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "Shortcut",
            action: nil,
            keyEquivalent: ""
        )
        let menu = NSMenu()
        let current = NSMenuItem(
            title: session.preferences.shortcut.accessibilityName,
            action: nil,
            keyEquivalent: ""
        )
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(
            item("Change in Settings…", action: #selector(showSettings))
        )
        parent.submenu = menu
        return parent
    }

    private func recordingModeMenu() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "Recording Mode",
            action: nil,
            keyEquivalent: ""
        )
        let menu = NSMenu()
        for mode in RecordingMode.allCases {
            let child = item(
                mode.displayName,
                action: #selector(selectRecordingMode)
            )
            child.representedObject = mode.rawValue
            child.state = session.preferences.recordingMode == mode ? .on : .off
            menu.addItem(child)
        }
        parent.submenu = menu
        return parent
    }

    private func item(
        _ title: String,
        action: Selector,
        key: String = ""
    ) -> NSMenuItem {
        let value = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: key
        )
        value.target = self
        return value
    }

    @objc private func startRecording() { session.beginRecording() }
    @objc private func stopRecording() { session.finishRecording() }
    @objc private func cancelRecording() { session.cancelRecording() }
    @objc private func copyLastTranscript() { session.copyLastTranscript() }
    @objc private func retryPendingTranscript() {
        session.retryPendingTranscriptHere()
    }
    @objc private func copyPendingTranscript() {
        session.copyPendingTranscript()
    }
    @objc private func discardPendingTranscript() {
        session.discardPendingTranscript()
    }
    @objc private func toggleEnabled() { session.setEnabled(!session.isEnabled) }
    @objc private func toggleSounds() {
        session.setPlaySounds(!session.preferences.playSounds)
    }
    @objc private func dismissError() { session.recover() }
    @objc private func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }
    @objc private func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }
    @objc private func showSettings() {
        settingsWindowController?.show()
    }

    @objc private func selectOutputMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = OutputMode(rawValue: raw)
        else { return }
        session.setOutputMode(mode)
    }

    @objc private func selectRecordingMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = RecordingMode(rawValue: raw)
        else { return }
        session.setRecordingMode(mode)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func observeWorkspaceLifecycle() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ] {
            workspaceObservers.append(
                center.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.hotKeyMonitor?.reregisterAfterLifecycleChange()
                    }
                }
            )
        }
    }
}
