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
    private var functionKeyLongPressMonitor: FunctionKeyLongPressMonitor?
    private var pointerInputMonitor: PointerInputMonitor?
    private var settingsWindowController: SettingsWindowController?
    private var recordingHUDController: RecordingHUDController?
    private var historyWindowController: HistoryWindowController?
    private var fileTranscriptionWindowController:
        FileTranscriptionWindowController?
    private var usageInsightsWindowController:
        UsageInsightsWindowController?
    private var aboutWindowController: AboutWindowController?
    private var scratchpadWindowController: ScratchpadWindowController?
    private var scratchpadStartupError: String?
    private var systemNotificationBridge: SystemNotificationBridge?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastRuntimeRestoreAt: TimeInterval = 0
    private var statusAnimationTask: Task<Void, Never>?
    private var statusAnimationFrame = 0
    private var statusAnimationIsLive = false
    private var statusAnimationStartedAt: TimeInterval?
    private lazy var statusAnimationImages =
        StatusBarWaveformRenderer.frames()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        session.onChange = { [weak self] in
            self?.rebuildMenu()
            self?.recordingHUDController?.update()
            self?.hotKeyMonitor?.synchronizeCancellationHotKey()
        }
        session.talk.onChange = { [weak self] in
            self?.recordingHUDController?.update()
            self?.hotKeyMonitor?.synchronizeCancellationHotKey()
        }
        settingsWindowController = SettingsWindowController(session: session)
        historyWindowController = HistoryWindowController(session: session)
        fileTranscriptionWindowController =
            FileTranscriptionWindowController(session: session)
        usageInsightsWindowController =
            UsageInsightsWindowController(session: session)
        aboutWindowController = AboutWindowController()
        session.onOpenSettings = { [weak self] in
            self?.settingsWindowController?.show()
        }
        session.onOpenHistory = { [weak self] in
            self?.historyWindowController?.show()
        }
        session.onPrepareLocalDataReset = { [weak self] in
            guard let self else { return }
            fileTranscriptionWindowController?.cancel()
            historyWindowController?.close()
            usageInsightsWindowController?.close()
            if let scratchpadWindowController {
                await scratchpadWindowController
                    .prepareForLocalDataReset()
                self.scratchpadWindowController = nil
            }
            session.onOpenScratchpad = nil
            session.onQuickDictation = nil
        }
        if session.notificationCapabilityEnabled {
            let bridge = SystemNotificationBridge()
            bridge.onAction = { [weak session] id, action, deepLink in
                session?.handleSystemNotificationAction(
                    notificationID: id,
                    action: action,
                    deepLink: deepLink
                )
            }
            bridge.onOpen = { [weak session] deepLink in
                session?.handleSystemNotificationOpen(
                    deepLink: deepLink
                )
            }
            systemNotificationBridge = bridge
            session.onSystemNotification = { [weak bridge] notification in
                bridge?.deliver(notification)
            }
            session.onNotificationPermissionRequest = { [weak bridge] in
                await bridge?.requestAuthorization() ?? false
            }
        }
        if session.scratchpadEnabled {
            do {
                let workspace = try LocalWorkspace()
                let controller = ScratchpadWindowController(
                    workspace: workspace
                ) { [weak session] in
                    session?.beginQuickDictationToScratchpad()
                }
                scratchpadWindowController = controller
                session.onOpenScratchpad = { [weak controller] in
                    controller?.show()
                }
                session.onQuickDictation = {
                    [weak model = controller.model] text in
                    guard let model else {
                        throw LocalWorkspaceError.unavailable
                    }
                    try await model.appendDictation(text)
                }
            } catch {
                scratchpadStartupError = error.localizedDescription
            }
        }
        recordingHUDController = RecordingHUDController(session: session)
        hotKeyMonitor = HotKeyMonitor(session: session)
        let functionKeyMonitor = FunctionKeyLongPressMonitor()
        functionKeyMonitor.onIntent = { [weak session] intent, withShift in
            session?.handleFunctionKeyIntent(intent, withShift: withShift)
        }
        functionKeyLongPressMonitor = functionKeyMonitor
        session.onFunctionKeyMonitoringChange = {
            [weak functionKeyMonitor] enabled, requestPermission in
            guard let functionKeyMonitor else { return .unavailable }
            if enabled {
                return functionKeyMonitor.start(
                    requestPermission: requestPermission
                )
            }
            functionKeyMonitor.stop()
            return .started
        }
        if session.pointerInputCapabilityEnabled {
            let pointerMonitor = PointerInputMonitor()
            pointerMonitor.onObservedCompatibleButton = {
                [weak session] button in
                session?.observeCompatiblePointerButton(button)
            }
            pointerMonitor.onEvent = {
                [weak session] button, event in
                session?.handlePointerInput(
                    button: button,
                    event: event
                )
            }
            pointerMonitor.onDeviceAvailability = {
                [weak session] available in
                session?.reportExtraPointerDeviceAvailability(
                    available
                )
            }
            pointerInputMonitor = pointerMonitor
            session.onPointerMonitoringChange = {
                [weak pointerMonitor] enabled, requestPermission in
                guard let pointerMonitor else { return .unavailable }
                if enabled {
                    return pointerMonitor.start(
                        requestPermission: requestPermission
                    )
                }
                pointerMonitor.stop()
                return .started
            }
        }
        session.onShortcutRegistration = { [weak self] shortcut in
            self?.hotKeyMonitor?.updateShortcut(shortcut)
                ?? OSStatus(eventNotHandledErr)
        }
        session.onScratchpadShortcutRegistration = {
            [weak self] shortcut in
            self?.hotKeyMonitor?.updateScratchpadShortcut(shortcut)
                ?? OSStatus(eventNotHandledErr)
        }
        session.onInputBindingsRegistration = {
            [weak self] bindings in
            self?.hotKeyMonitor?.updateInputBindings(bindings)
                ?? OSStatus(eventNotHandledErr)
        }
        let hotKeyStatus = hotKeyMonitor?.start() ?? OSStatus(eventNotHandledErr)
        session.reportShortcutRegistration(succeeded: hotKeyStatus == noErr)
        session.restoreFunctionKeyMonitoringAfterLifecycleChange(
            requestPermission: true
        )
        session.restorePointerMonitoringAfterLifecycleChange()
        if hotKeyStatus != noErr {
            session.reportFailure(
                "\(session.preferences.shortcut.accessibilityName) "
                    + "could not be registered (\(hotKeyStatus)).",
                kind: .shortcut
            )
        }
        observeWorkspaceLifecycle()
        rebuildMenu()
        recordingHUDController?.update()
        session.refreshPersistentRecovery()
        session.warmLocalModel()
        if !session.preferences.hasCompletedOnboarding {
            DispatchQueue.main.async { [weak self] in
                self?.settingsWindowController?.show()
            }
        }
    }

    /// Opening the app again from Finder, Spotlight, or Launchpad while it is
    /// already running brings up its window instead of doing nothing, which
    /// also keeps it reachable when the menu bar item is hidden.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        settingsWindowController?.show()
        return false
    }

    /// Menu bar apps have no main menu by default, so standard editing key
    /// equivalents such as Command-V never reach their own text fields.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu(title: Brand.productName)
        appMenu.addItem(
            withTitle: "Quit \(Brand.productName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(
            withTitle: "Undo",
            action: Selector(("undo:")),
            keyEquivalent: "z"
        )
        let redo = editMenu.addItem(
            withTitle: "Redo",
            action: Selector(("redo:")),
            keyEquivalent: "z"
        )
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut",
            action: #selector(NSText.cut(_:)),
            keyEquivalent: "x"
        )
        editMenu.addItem(
            withTitle: "Copy",
            action: #selector(NSText.copy(_:)),
            keyEquivalent: "c"
        )
        editMenu.addItem(
            withTitle: "Paste",
            action: #selector(NSText.paste(_:)),
            keyEquivalent: "v"
        )
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Close",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopStatusAnimation()
        session.prepareForConfirmedTermination()
        hotKeyMonitor?.stop()
        functionKeyLongPressMonitor?.stop()
        pointerInputMonitor?.stop()
        fileTranscriptionWindowController?.cancel()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard session.requiresTerminationConfirmation else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Quit during an active recording?"
        alert.informativeText =
            "The current recording will be discarded and no transcript will be inserted."
        alert.addButton(withTitle: "Keep Recording")
        alert.addButton(withTitle: "Quit and Discard")
        guard alert.runModal() == .alertSecondButtonReturn else {
            return .terminateCancel
        }
        session.prepareForConfirmedTermination()
        return .terminateNow
    }

    private func rebuildMenu() {
        updateStatusItemAppearance()

        let menu = NSMenu()
        let status = NSMenuItem(
            title: session.statusLabel,
            action: nil,
            keyEquivalent: ""
        )
        status.isEnabled = false
        menu.addItem(status)
        let profile = NSMenuItem(
            title: "Profile: \(session.activeProfileLabel)",
            action: nil,
            keyEquivalent: ""
        )
        profile.isEnabled = false
        menu.addItem(profile)
        if let vocabularyError = session.vocabularyError {
            let warning = NSMenuItem(
                title: vocabularyError,
                action: nil,
                keyEquivalent: ""
            )
            warning.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "Vocabulary warning"
            )
            warning.isEnabled = false
            menu.addItem(warning)
        }
        if let profileError = session.profileError {
            let warning = NSMenuItem(
                title: profileError,
                action: nil,
                keyEquivalent: ""
            )
            warning.image = NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: "App profile warning"
            )
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(.separator())

        if session.state == .recording || session.state == .starting {
            menu.addItem(
                item("Stop Recording", action: #selector(stopRecording))
            )
            if session.effectiveRecordingMode == .handsFree {
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
        if session.lastUnformattedTranscript != nil {
            menu.addItem(
                item(
                    "Copy Last Before Formatting",
                    action: #selector(copyLastUnformattedTranscript)
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

        if session.hasRecoverableAudio {
            menu.addItem(.separator())
            menu.addItem(
                item(
                    (session.recoverableAudioWasCancelled
                        ? "Undo Cancel and Retry Locally "
                        : "Retry Local Transcription ")
                        + "(\(Int(ceil(session.recoverableAudioDuration)))s audio)",
                    action: #selector(retryRecoverableAudio)
                )
            )
            menu.addItem(
                item(
                    "Discard Recovery Audio",
                    action: #selector(discardRecoverableAudio)
                )
            )
        }

        if session.persistentRecoveryEnabled,
           !session.persistentRecoverySummaries.isEmpty
        {
            menu.addItem(.separator())
            let parent = NSMenuItem(
                title: "Encrypted Recovery",
                action: nil,
                keyEquivalent: ""
            )
            let recoveryMenu = NSMenu()
            for summary in session.persistentRecoverySummaries {
                let title: String
                switch summary.state {
                case .ready:
                    title = "Recover \(summary.createdAt.formatted(date: .abbreviated, time: .shortened))"
                case .corrupt:
                    title = "Corrupt recovery artifact"
                case .keyUnavailable:
                    title = "Recovery key unavailable"
                }
                let recover = item(
                    title,
                    action: #selector(retryPersistentRecovery)
                )
                recover.representedObject = summary.id.uuidString
                recover.isEnabled = summary.state == .ready
                recoveryMenu.addItem(recover)

                let copy = item(
                    "Recover to Clipboard",
                    action: #selector(copyPersistentRecovery)
                )
                copy.representedObject = summary.id.uuidString
                copy.isEnabled = summary.state == .ready
                recoveryMenu.addItem(copy)

                let discard = item(
                    "Discard \(summary.createdAt.formatted(date: .abbreviated, time: .shortened))",
                    action: #selector(discardPersistentRecovery)
                )
                discard.representedObject = summary.id.uuidString
                recoveryMenu.addItem(discard)
            }
            parent.submenu = recoveryMenu
            menu.addItem(parent)
        }

        if let recoveryError = session.persistentRecoveryError {
            let warning = NSMenuItem(
                title: "Recovery: \(recoveryError)",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
        }

        if let notification = session.inAppNotificationMessage {
            menu.addItem(.separator())
            let message = NSMenuItem(
                title: notification,
                action: nil,
                keyEquivalent: ""
            )
            message.isEnabled = false
            menu.addItem(message)
            menu.addItem(
                item(
                    "Acknowledge",
                    action: #selector(dismissInAppNotification)
                )
            )
        }

        menu.addItem(.separator())
        addPermissionItems(to: menu)
        menu.addItem(outputMenu())
        menu.addItem(activationMenu())
        menu.addItem(recordingModeMenu())

        let sounds = item("Sound Feedback", action: #selector(toggleSounds))
        sounds.state = session.effectivePlaySounds ? .on : .off
        sounds.isEnabled = session.activeAppProfile?.playSounds == nil
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
            item("Dictation History…", action: #selector(showHistory))
        )
        if session.scratchpadEnabled {
            menu.addItem(
                item(
                    "Scratchpad…",
                    action: #selector(showScratchpad)
                )
            )
            let quick = item(
                "Quick Dictation to Scratchpad",
                action: #selector(quickDictationToScratchpad)
            )
            quick.isEnabled = scratchpadWindowController != nil
                && session.canStartRecording
            menu.addItem(quick)
        }
        if let scratchpadStartupError {
            let warning = NSMenuItem(
                title: "Scratchpad: \(scratchpadStartupError)",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(
            item(
                "Transcribe Audio File…",
                action: #selector(showFileTranscription)
            )
        )
        menu.addItem(
            item("Private Usage Insights…", action: #selector(showInsights))
        )
        menu.addItem(.separator())
        menu.addItem(
            item(
                "About Autohand Voice",
                action: #selector(showAbout)
            )
        )
        menu.addItem(
            item("Quit Autohand Voice", action: #selector(quit), key: "q")
        )
        statusItem.menu = menu
    }

    private var shouldAnimateStatusItem: Bool {
        guard
            session.state == .ready,
            !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        else { return false }
        return StatusBarWaveformAnimation.shouldRemainVisible(
            isPreparing: session.modelState == .preparing,
            startedAtUptime: statusAnimationStartedAt,
            nowUptime: ProcessInfo.processInfo.systemUptime
        )
    }

    /// While recording, the menu bar icon becomes a waveform that follows the
    /// microphone level.
    private var shouldShowLiveWaveform: Bool {
        session.state == .recording
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateStatusItemAppearance() {
        guard let button = statusItem.button else { return }
        button.toolTip = "Autohand Voice — \(session.statusLabel)"

        if shouldShowLiveWaveform {
            if !statusAnimationIsLive {
                startLiveWaveform()
            }
            return
        }
        if statusAnimationIsLive {
            stopStatusAnimation()
        }

        guard shouldAnimateStatusItem else {
            stopStatusAnimation()
            button.image = NSImage(
                systemSymbolName: session.statusSymbol,
                accessibilityDescription: session.statusLabel
            )
            button.image?.isTemplate = true
            return
        }

        if statusAnimationTask == nil {
            startStatusAnimation()
        } else {
            applyStatusAnimationFrame()
        }
    }

    private func startStatusAnimation() {
        statusAnimationTask?.cancel()
        statusAnimationFrame = 0
        statusAnimationStartedAt = ProcessInfo.processInfo.systemUptime
        applyStatusAnimationFrame()
        statusAnimationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: StatusBarWaveformAnimation.frameInterval
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.advanceStatusAnimationFrame()
            }
        }
    }

    private func startLiveWaveform() {
        stopStatusAnimation()
        statusAnimationIsLive = true
        applyLiveWaveformFrame()
        statusAnimationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(
                        for: StatusBarWaveformAnimation.liveFrameInterval
                    )
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                guard self.shouldShowLiveWaveform else {
                    self.updateStatusItemAppearance()
                    return
                }
                self.statusAnimationFrame += 1
                self.applyLiveWaveformFrame()
            }
        }
    }

    private func applyLiveWaveformFrame() {
        statusItem.button?.image = StatusBarWaveformRenderer.liveFrame(
            level: StatusBarWaveformAnimation.meterLevel(
                rms: session.audioInputRMS
            ),
            frame: statusAnimationFrame
        )
    }

    private func advanceStatusAnimationFrame() {
        guard shouldAnimateStatusItem else {
            updateStatusItemAppearance()
            return
        }
        guard !statusAnimationImages.isEmpty else {
            stopStatusAnimation()
            return
        }
        statusAnimationFrame =
            (statusAnimationFrame + 1) % statusAnimationImages.count
        applyStatusAnimationFrame()
    }

    private func applyStatusAnimationFrame() {
        guard !statusAnimationImages.isEmpty else { return }
        statusItem.button?.image = statusAnimationImages[statusAnimationFrame]
    }

    private func stopStatusAnimation() {
        statusAnimationTask?.cancel()
        statusAnimationTask = nil
        statusAnimationIsLive = false
        statusAnimationFrame = 0
        statusAnimationStartedAt = nil
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
        let isOverridden = session.activeAppProfile?.outputMode != nil
        for mode in OutputMode.allCases {
            let title = mode == .type ? "Insert at Cursor" : "Copy to Clipboard"
            let child = item(title, action: #selector(selectOutputMode))
            child.representedObject = mode.rawValue
            child.state = session.activeConfiguration.outputMode == mode
                ? .on
                : .off
            child.isEnabled = !isOverridden
            menu.addItem(child)
        }
        if isOverridden {
            menu.addItem(.separator())
            menu.addItem(
                item("Change in App Profiles…", action: #selector(showSettings))
            )
        }
        parent.submenu = menu
        return parent
    }

    private func activationMenu() -> NSMenuItem {
        let parent = NSMenuItem(
            title: "Activation",
            action: nil,
            keyEquivalent: ""
        )
        let menu = NSMenu()
        let primaryTitle = session.preferences
            .functionKeyLongPressEnabled
            ? "Primary: Long-press Fn"
            : "Primary: "
                + session.preferences.shortcut.accessibilityName
        let primary = NSMenuItem(
            title: primaryTitle,
            action: nil,
            keyEquivalent: ""
        )
        primary.isEnabled = false
        menu.addItem(primary)
        if session.preferences.functionKeyLongPressEnabled {
            let status = NSMenuItem(
                title: session.functionKeyLongPressStatus,
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)
            let fallback = NSMenuItem(
                title: "Fallback: "
                    + session.preferences.shortcut.accessibilityName,
                action: nil,
                keyEquivalent: ""
            )
            fallback.isEnabled = false
            menu.addItem(fallback)
        }
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
        let isOverridden = session.activeAppProfile?.recordingMode != nil
        for mode in RecordingMode.allCases {
            let child = item(
                mode.displayName,
                action: #selector(selectRecordingMode)
            )
            child.representedObject = mode.rawValue
            child.state = session.effectiveRecordingMode == mode ? .on : .off
            child.isEnabled = !isOverridden
            menu.addItem(child)
        }
        if isOverridden {
            menu.addItem(.separator())
            menu.addItem(
                item("Change in App Profiles…", action: #selector(showSettings))
            )
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

    @objc private func startRecording() {
        session.beginRecording(origin: .menu)
    }
    @objc private func stopRecording() { session.finishRecording() }
    @objc private func cancelRecording() { session.cancelRecording() }
    @objc private func copyLastTranscript() { session.copyLastTranscript() }
    @objc private func copyLastUnformattedTranscript() {
        session.copyLastUnformattedTranscript()
    }
    @objc private func retryPendingTranscript() {
        session.retryPendingTranscriptHere()
    }
    @objc private func copyPendingTranscript() {
        session.copyPendingTranscript()
    }
    @objc private func discardPendingTranscript() {
        session.discardPendingTranscript()
    }
    @objc private func retryRecoverableAudio() {
        session.retryRecoverableAudio()
    }
    @objc private func discardRecoverableAudio() {
        session.discardRecoverableAudio()
    }
    @objc private func retryPersistentRecovery(_ sender: NSMenuItem) {
        guard
            let value = sender.representedObject as? String,
            let id = UUID(uuidString: value)
        else { return }
        session.retryPersistentRecovery(id)
    }
    @objc private func copyPersistentRecovery(_ sender: NSMenuItem) {
        guard
            let value = sender.representedObject as? String,
            let id = UUID(uuidString: value)
        else { return }
        session.copyPersistentRecovery(id)
    }
    @objc private func discardPersistentRecovery(_ sender: NSMenuItem) {
        guard
            let value = sender.representedObject as? String,
            let id = UUID(uuidString: value)
        else { return }
        session.discardPersistentRecovery(id)
    }
    @objc private func toggleEnabled() { session.setEnabled(!session.isEnabled) }
    @objc private func toggleSounds() {
        session.setPlaySounds(!session.preferences.playSounds)
    }
    @objc private func dismissError() { session.recover() }
    @objc private func dismissInAppNotification() {
        session.acknowledgeInAppNotification()
    }
    @objc private func openMicrophoneSettings() {
        openPrivacySettings(anchor: "Privacy_Microphone")
    }
    @objc private func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
    }
    @objc private func showSettings() {
        settingsWindowController?.show()
    }
    @objc private func showHistory() {
        historyWindowController?.show()
    }
    @objc private func showScratchpad() {
        scratchpadWindowController?.show()
    }
    @objc private func quickDictationToScratchpad() {
        scratchpadWindowController?.show()
        session.beginQuickDictationToScratchpad()
    }
    @objc private func showFileTranscription() {
        fileTranscriptionWindowController?.show()
    }
    @objc private func showInsights() {
        usageInsightsWindowController?.show()
    }
    @objc private func showAbout() {
        aboutWindowController?.show()
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
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.session.handleSleepInterruption()
                }
            }
        )
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
                        self?.restoreRuntimeAfterWake()
                    }
                }
            )
        }
        workspaceObservers.append(
            center.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.session.refreshActiveProfile()
                }
            }
        )
    }

    private func restoreRuntimeAfterWake() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastRuntimeRestoreAt > 1 else { return }
        lastRuntimeRestoreAt = now
        hotKeyMonitor?.reregisterAfterLifecycleChange()
        functionKeyLongPressMonitor?.stop()
        session.restoreFunctionKeyMonitoringAfterLifecycleChange()
        pointerInputMonitor?.stop()
        session.restorePointerMonitoringAfterLifecycleChange()
        settingsWindowController?.restoreAfterLifecycleChange()
        session.refreshActiveProfile()
    }
}
