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

    var onIntent: ((DictationInputIntent) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var thresholdWorkItem: DispatchWorkItem?
    private var reducer = FunctionKeyLongPressReducer()
    private var functionKeyIsDown = false

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
            onIntent?(intent)
        }
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
        let isDown = flags
            .intersection(.deviceIndependentFlagsMask)
            .contains(.function)
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
        }
    }

    private func emit(_ event: FunctionKeyLongPressEvent) {
        let intent = reducer.reduce(event)
        if intent != .none {
            onIntent?(intent)
        }
    }
}
