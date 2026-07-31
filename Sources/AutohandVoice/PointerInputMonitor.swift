import ApplicationServices
import AutohandVoiceCore
import Foundation

enum PointerInputMonitorResult: Equatable {
    case started
    case permissionDenied
    case unavailable
}

@MainActor
final class PointerInputMonitor {
    var onEvent: ((Int, InputTriggerEvent) -> Void)?
    var onObservedCompatibleButton: ((Int) -> Void)?
    var onDeviceAvailability: ((Bool) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let deviceMonitor = ExtraPointerDeviceMonitor()

    var isRunning: Bool { eventTap != nil }

    func start(requestPermission: Bool) -> PointerInputMonitorResult {
        if isRunning { return .started }
        var trusted = CGPreflightListenEventAccess()
        if !trusted, requestPermission {
            trusted = CGRequestListenEventAccess()
        }
        guard trusted else { return .permissionDenied }

        let mask =
            (CGEventMask(1) << CGEventType.otherMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue)
            | (CGEventMask(1) << CGEventType.tapDisabledByTimeout.rawValue)
            | (CGEventMask(1)
                << CGEventType.tapDisabledByUserInput.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: pointerInputCallback,
            userInfo: userInfo
        ) else {
            return .unavailable
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        deviceMonitor.onAvailabilityChange = {
            [weak self] available in
            self?.onDeviceAvailability?(available)
        }
        deviceMonitor.start()
        return .started
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
        runLoopSource = nil
        eventTap = nil
        deviceMonitor.stop()
    }

    fileprivate func handle(
        type: CGEventType,
        event: CGEvent
    ) {
        if type == .tapDisabledByTimeout
            || type == .tapDisabledByUserInput
        {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        let button = Int(
            event.getIntegerValueField(.mouseEventButtonNumber)
        )
        guard
            button > 1,
            button <= InputConfiguration.maximumPointerButton
        else { return }
        onObservedCompatibleButton?(button)
        switch type {
        case .otherMouseDown:
            onEvent?(button, .pressed)
        case .otherMouseUp:
            onEvent?(button, .released)
        default:
            break
        }
    }

    deinit {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                runLoopSource,
                .commonModes
            )
        }
    }
}

private let pointerInputCallback:
    CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let monitor = Unmanaged<PointerInputMonitor>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        Task { @MainActor in
            monitor.handle(type: type, event: event)
        }
        return Unmanaged.passUnretained(event)
    }
