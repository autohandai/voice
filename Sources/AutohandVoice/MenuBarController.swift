import AppKit
import AutohandVoiceCore
import CoreGraphics
import Foundation

@MainActor
final class MenuBarController: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(
        withLength: NSStatusItem.squareLength
    )
    private let session = VoiceSession()
    private var hotKeyMonitor: HotKeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        session.onChange = { [weak self] in self?.rebuildMenu() }
        hotKeyMonitor = HotKeyMonitor(session: session)
        hotKeyMonitor?.start()
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            session.reportFailure(
                "Input Monitoring is required for push-to-talk. Grant access in System Settings, then relaunch."
            )
        }
        rebuildMenu()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyMonitor?.stop()
    }

    private func rebuildMenu() {
        statusItem.button?.image = NSImage(
            systemSymbolName: session.state.symbol,
            accessibilityDescription: session.state.label
        )
        statusItem.button?.toolTip = "Autohand Voice — \(session.state.label)"

        let menu = NSMenu()
        let status = NSMenuItem(title: session.state.label, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        if session.state == .recording {
            menu.addItem(
                item("Stop Recording", action: #selector(stopRecording))
            )
        } else {
            let record = item(
                "Start Recording",
                action: #selector(startRecording)
            )
            record.isEnabled = session.isEnabled && session.state == .ready
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

        menu.addItem(.separator())
        menu.addItem(outputMenu())
        menu.addItem(pushToTalkMenu())

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
            item("Quit Autohand Voice", action: #selector(quit), key: "q")
        )
        statusItem.menu = menu
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

    private func pushToTalkMenu() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "Push-to-Talk Key",
            action: nil,
            keyEquivalent: ""
        )
        let menu = NSMenu()
        for key in PushToTalkKey.allCases {
            let child = item(key.displayName, action: #selector(selectHotKey))
            child.representedObject = key.rawValue
            child.state = session.preferences.pushToTalkKey == key ? .on : .off
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
    @objc private func copyLastTranscript() { session.copyLastTranscript() }
    @objc private func toggleEnabled() { session.setEnabled(!session.isEnabled) }
    @objc private func toggleSounds() {
        session.setPlaySounds(!session.preferences.playSounds)
    }
    @objc private func dismissError() { session.recover() }

    @objc private func selectOutputMode(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let mode = OutputMode(rawValue: raw)
        else { return }
        session.setOutputMode(mode)
    }

    @objc private func selectHotKey(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let key = PushToTalkKey(rawValue: raw)
        else { return }
        session.setPushToTalkKey(key)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
