import AppKit
import ApplicationServices
import AutohandVoiceCore
import CoreGraphics
import Foundation

enum FunctionKeyMonitorResult {
    case started
    case permissionDenied
    case unavailable
}

/// Observes the modifier-only Fn/Globe key without consuming the event.
/// Short presses therefore retain their configured macOS behavior.
@MainActor
final class FunctionKeyLongPressMonitor {
    static let holdDuration: TimeInterval = 0.4

    /// Delivers each intent with the modifiers held during the press
    /// (Fn+Shift talks to Fantail; adding Command keeps it hands-free).
    var onIntent: ((FunctionKeyIntent, FunctionKeyModifiers) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var thresholdWorkItem: DispatchWorkItem?
    private var reducer = FunctionKeyLongPressReducer()
    private var functionKeyIsDown = false
    private var modifiersSeenDuringPress = FunctionKeyModifiers()

    func start(requestPermission: Bool) -> FunctionKeyMonitorResult {
        stop(deliverCancellation: false)

        let inputMonitoringGranted = CGPreflightListenEventAccess()
            || (requestPermission && CGRequestListenEventAccess())
        let accessibilityGranted = AXIsProcessTrusted()
        guard FunctionKeyMonitoringAuthorization.isSufficient(
            inputMonitoringGranted: inputMonitoringGranted,
            accessibilityGranted: accessibilityGranted
        ) else {
            return .permissionDenied
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor [weak self] in
                self?.observe(flags)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.observe(event.modifierFlags)
            return event
        }

        guard globalMonitor != nil, localMonitor != nil else {
            stop(deliverCancellation: false)
            return .unavailable
        }
        return .started
    }

    func stop() {
        stop(deliverCancellation: true)
    }

    private func stop(deliverCancellation: Bool) {
        thresholdWorkItem?.cancel()
        thresholdWorkItem = nil
        functionKeyIsDown = false
        let intent = reducer.reduce(.cancelled)
        if deliverCancellation, intent != .none {
            onIntent?(intent, modifiersSeenDuringPress)
        }
        modifiersSeenDuringPress = FunctionKeyModifiers()
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
    }

    private func observe(_ flags: NSEvent.ModifierFlags) {
        let modifiers = flags.intersection(.deviceIndependentFlagsMask)
        let isDown = modifiers.contains(.function)
        if isDown, modifiers.contains(.shift) {
            modifiersSeenDuringPress.shift = true
        }
        if isDown, modifiers.contains(.command) {
            modifiersSeenDuringPress.command = true
        }
        if isDown {
            guard !functionKeyIsDown else { return }
            functionKeyIsDown = true
            emit(.pressed)
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.functionKeyIsDown else { return }
                    self.thresholdWorkItem = nil
                    self.emit(.thresholdReached)
                }
            }
            thresholdWorkItem = item
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.holdDuration,
                execute: item
            )
        } else {
            guard functionKeyIsDown else { return }
            functionKeyIsDown = false
            thresholdWorkItem?.cancel()
            thresholdWorkItem = nil
            emit(.released)
            modifiersSeenDuringPress = FunctionKeyModifiers()
        }
    }

    private func emit(_ event: FunctionKeyLongPressEvent) {
        let intent = reducer.reduce(event)
        if intent != .none {
            onIntent?(intent, modifiersSeenDuringPress)
        }
    }
}
