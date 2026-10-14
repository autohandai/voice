import AutohandVoiceCore
import Carbon
import Foundation

private let autohandHotKeySignature: OSType = 0x4156_484B // AVHK
private let autohandHotKeyID: UInt32 = 1
private let autohandCancelHotKeyID: UInt32 = 2
private let autohandScratchpadHotKeyID: UInt32 = 3
private let autohandCustomHotKeyBaseID: UInt32 = 100

private let autohandHotKeyHandler: EventHandlerUPP = {
    _, event, userData in
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }

    var identifier = EventHotKeyID()
    let readStatus = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard
        readStatus == noErr,
        identifier.signature == autohandHotKeySignature
    else {
        return OSStatus(eventNotHandledErr)
    }

    let monitor = Unmanaged<HotKeyMonitor>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let eventKind = GetEventKind(event)
    Task { @MainActor in
        monitor.handle(identifier: identifier.id, eventKind: eventKind)
    }
    return noErr
}

@MainActor
final class HotKeyMonitor {
    private var hotKey: EventHotKeyRef?
    private var cancelHotKey: EventHotKeyRef?
    private var scratchpadHotKey: EventHotKeyRef?
    private var customHotKeys: [UInt32: EventHotKeyRef] = [:]
    private var customBindings: [UInt32: InputBinding] = [:]
    private var eventHandler: EventHandlerRef?
    private let session: VoiceSession

    init(session: VoiceSession) {
        self.session = session
    }

    func start() -> OSStatus {
        guard hotKey == nil, eventHandler == nil else { return noErr }

        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            ),
        ]
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = eventTypes.withUnsafeMutableBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                autohandHotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                userData,
                &eventHandler
            )
        }
        guard handlerStatus == noErr else { return handlerStatus }

        let registerStatus = registerPrimary(session.preferences.shortcut)
        if registerStatus != noErr {
            stop()
            return registerStatus
        }
        let customStatus = registerCustomBindings(
            session.preferences.inputBindings
        )
        if customStatus != noErr {
            stop()
            return customStatus
        }
        if session.scratchpadEnabled {
            let scratchpadStatus = registerScratchpad(
                session.preferences.scratchpadShortcut
            )
            session.reportScratchpadShortcutRegistration(
                scratchpadStatus
            )
        }
        return registerStatus
    }

    func stop() {
        unregisterCancelHotKey()
        unregisterCustomHotKeys()
        if let scratchpadHotKey {
            UnregisterEventHotKey(scratchpadHotKey)
        }
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKey = nil
        scratchpadHotKey = nil
        eventHandler = nil
    }

    func updateShortcut(_ shortcut: RegisteredShortcut) -> OSStatus {
        guard shortcut.isValid else { return OSStatus(paramErr) }
        let previous = session.preferences.shortcut
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }

        let status = registerPrimary(shortcut)
        guard status != noErr else { return noErr }

        let restoreStatus = registerPrimary(previous)
        if restoreStatus != noErr {
            session.reportFailure(
                "The shortcut could not be restored (error \(restoreStatus))."
            )
        }
        return status
    }

    func updateScratchpadShortcut(
        _ shortcut: RegisteredShortcut
    ) -> OSStatus {
        guard shortcut.isValid else { return OSStatus(paramErr) }
        let previous = session.preferences.scratchpadShortcut
        if let scratchpadHotKey {
            UnregisterEventHotKey(scratchpadHotKey)
            self.scratchpadHotKey = nil
        }
        let status = registerScratchpad(shortcut)
        guard status != noErr else { return noErr }
        _ = registerScratchpad(previous)
        return status
    }

    func synchronizeCancellationHotKey() {
        // Escape cancels Hands-Free recordings and stops Fantail while it is
        // thinking or speaking; it is never held globally otherwise.
        let shouldRegister = (
            session.effectiveRecordingMode == .handsFree
                && session.isRecordingOrStarting
        ) || (session.talk.isWorking && !session.isRecordingOrStarting)
        if shouldRegister {
            let status = registerCancelHotKey()
            // Talk keeps its on-screen Stop button if Escape is unavailable.
            if status != noErr, session.isRecordingOrStarting {
                session.cancelRecording()
                session.reportFailure(
                    "Escape could not be registered for Hands-Free mode "
                        + "(error \(status))."
                )
            }
        } else {
            unregisterCancelHotKey()
        }
    }

    fileprivate func handle(identifier: UInt32, eventKind: UInt32) {
        if identifier == autohandCancelHotKeyID {
            guard eventKind == UInt32(kEventHotKeyPressed) else { return }
            if session.isRecordingOrStarting {
                perform(.cancel)
            } else {
                session.talk.stopSpeaking()
                synchronizeCancellationHotKey()
            }
            return
        }
        if identifier == autohandScratchpadHotKeyID {
            guard eventKind == UInt32(kEventHotKeyPressed) else { return }
            session.openScratchpad()
            return
        }
        if let binding = customBindings[identifier] {
            let triggerEvent: InputTriggerEvent
            switch eventKind {
            case UInt32(kEventHotKeyPressed):
                triggerEvent = .pressed
            case UInt32(kEventHotKeyReleased):
                triggerEvent = .released
            default:
                return
            }
            guard case let .keyboard(shortcut) = binding.trigger else {
                return
            }
            session.handleKeyboardInput(
                shortcut: shortcut,
                event: triggerEvent
            )
            return
        }
        guard identifier == autohandHotKeyID else { return }

        let event: ShortcutEvent
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            event = .pressed
        case UInt32(kEventHotKeyReleased):
            event = .released
        default:
            return
        }
        perform(
            session.effectiveRecordingMode.action(
                for: event,
                isRecording: session.isRecordingOrStarting
            )
        )
    }

    private func perform(_ action: ShortcutAction) {
        switch action {
        case .none:
            break
        case .start:
            session.beginRecording(origin: .shortcut)
            synchronizeCancellationHotKey()
        case .finish:
            unregisterCancelHotKey()
            session.finishRecording()
        case .cancel:
            unregisterCancelHotKey()
            session.cancelRecording()
        }
    }

    private func registerPrimary(_ shortcut: RegisteredShortcut) -> OSStatus {
        let identifier = EventHotKeyID(
            signature: autohandHotKeySignature,
            id: autohandHotKeyID
        )
        return RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(shortcut.modifiers),
            identifier,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKey
        )
    }

    private func registerCancelHotKey() -> OSStatus {
        guard cancelHotKey == nil else { return noErr }
        let identifier = EventHotKeyID(
            signature: autohandHotKeySignature,
            id: autohandCancelHotKeyID
        )
        return RegisterEventHotKey(
            UInt32(kVK_Escape),
            0,
            identifier,
            GetApplicationEventTarget(),
            OptionBits(0),
            &cancelHotKey
        )
    }

    private func registerScratchpad(
        _ shortcut: RegisteredShortcut
    ) -> OSStatus {
        let identifier = EventHotKeyID(
            signature: autohandHotKeySignature,
            id: autohandScratchpadHotKeyID
        )
        return RegisterEventHotKey(
            shortcut.keyCode,
            carbonModifiers(shortcut.modifiers),
            identifier,
            GetApplicationEventTarget(),
            OptionBits(0),
            &scratchpadHotKey
        )
    }

    func updateInputBindings(_ bindings: [InputBinding]) -> OSStatus {
        let previous = customBindings.values.map { $0 }
        unregisterCustomHotKeys()
        let status = registerCustomBindings(bindings)
        guard status != noErr else { return noErr }
        unregisterCustomHotKeys()
        _ = registerCustomBindings(previous)
        return status
    }

    private func registerCustomBindings(
        _ bindings: [InputBinding]
    ) -> OSStatus {
        let keyboardBindings = bindings.filter {
            guard case .keyboard = $0.trigger else { return false }
            return $0.action != .startStop
        }
        for (index, binding) in keyboardBindings.enumerated() {
            guard case let .keyboard(shortcut) = binding.trigger else {
                continue
            }
            let id = autohandCustomHotKeyBaseID + UInt32(index)
            let identifier = EventHotKeyID(
                signature: autohandHotKeySignature,
                id: id
            )
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                carbonModifiers(shortcut.modifiers),
                identifier,
                GetApplicationEventTarget(),
                OptionBits(0),
                &reference
            )
            guard status == noErr, let reference else {
                unregisterCustomHotKeys()
                return status == noErr ? OSStatus(eventNotHandledErr) : status
            }
            customHotKeys[id] = reference
            customBindings[id] = binding
        }
        return noErr
    }

    private func unregisterCustomHotKeys() {
        for reference in customHotKeys.values {
            UnregisterEventHotKey(reference)
        }
        customHotKeys.removeAll(keepingCapacity: true)
        customBindings.removeAll(keepingCapacity: true)
    }

    private func unregisterCancelHotKey() {
        if let cancelHotKey {
            UnregisterEventHotKey(cancelHotKey)
            self.cancelHotKey = nil
        }
    }

    func reregisterAfterLifecycleChange() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        let status = registerPrimary(session.preferences.shortcut)
        if status != noErr {
            session.reportFailure(
                "The shortcut could not be re-registered (error \(status))."
            )
        }
        if session.scratchpadEnabled {
            if let scratchpadHotKey {
                UnregisterEventHotKey(scratchpadHotKey)
                self.scratchpadHotKey = nil
            }
            session.reportScratchpadShortcutRegistration(
                registerScratchpad(session.preferences.scratchpadShortcut)
            )
        }
        let customStatus = updateInputBindings(
            session.preferences.inputBindings
        )
        if customStatus != noErr {
            session.reportFailure(
                "A keyboard binding could not be re-registered "
                    + "(error \(customStatus))."
            )
        }
    }

    private func carbonModifiers(
        _ modifiers: ShortcutModifiers
    ) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        return value
    }
}
