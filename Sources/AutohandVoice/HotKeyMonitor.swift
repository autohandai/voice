import AutohandVoiceCore
import Carbon
import Foundation

private let autohandHotKeySignature: OSType = 0x4156_484B // AVHK
private let autohandHotKeyID: UInt32 = 1

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
        identifier.signature == autohandHotKeySignature,
        identifier.id == autohandHotKeyID
    else {
        return OSStatus(eventNotHandledErr)
    }

    let monitor = Unmanaged<HotKeyMonitor>
        .fromOpaque(userData)
        .takeUnretainedValue()
    let eventKind = GetEventKind(event)
    Task { @MainActor in
        monitor.handle(eventKind: eventKind)
    }
    return noErr
}

@MainActor
final class HotKeyMonitor {
    private var hotKey: EventHotKeyRef?
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

        let identifier = EventHotKeyID(
            signature: autohandHotKeySignature,
            id: autohandHotKeyID
        )
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            identifier,
            GetApplicationEventTarget(),
            OptionBits(0),
            &hotKey
        )
        if registerStatus != noErr {
            stop()
        }
        return registerStatus
    }

    func stop() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        hotKey = nil
        eventHandler = nil
    }

    fileprivate func handle(eventKind: UInt32) {
        switch eventKind {
        case UInt32(kEventHotKeyPressed):
            session.beginRecording()
        case UInt32(kEventHotKeyReleased):
            session.finishRecording()
        default:
            break
        }
    }
}
