import Foundation

/// Explicit module seams where deterministic tests may request a finite error.
///
/// Production code uses ``NoVoiceFaultInjector``. There is no environment,
/// preferences, or command-line path that enables fault injection.
public enum VoiceFaultPoint: String, Codable, CaseIterable, Sendable {
    case captureStart = "capture_start"
    case audioRouteSwitch = "audio_route_switch"
    case modelValidation = "model_validation"
    case recognition
    case revision
    case targetCapture = "target_capture"
    case insertion
    case recoveryRead = "recovery_read"
    case storageWrite = "storage_write"
    case notificationDelivery = "notification_delivery"
    case sync
    case account
}

public protocol VoiceFaultInjecting: Sendable {
    func failure(at point: VoiceFaultPoint) async -> VoiceFailureCategory?
}

public struct VoiceInjectedFailure: LocalizedError, Equatable, Sendable {
    public let category: VoiceFailureCategory

    public init(category: VoiceFailureCategory) {
        self.category = category
    }

    public var errorDescription: String? {
        "Deterministic test fault: \(category.code)"
    }
}

public struct NoVoiceFaultInjector: VoiceFaultInjecting {
    public init() {}

    public func failure(
        at _: VoiceFaultPoint
    ) async -> VoiceFailureCategory? {
        nil
    }
}

/// A per-instance FIFO fault schedule for unit and integration tests.
///
/// It deliberately has no singleton or process-environment integration, so a
/// deterministic test seam cannot silently become a production backdoor.
public actor DeterministicVoiceFaultInjector: VoiceFaultInjecting {
    private var schedule: [VoiceFaultPoint: [VoiceFailureCategory]]

    public init(
        schedule: [VoiceFaultPoint: [VoiceFailureCategory]] = [:]
    ) {
        self.schedule = schedule
    }

    public func failure(
        at point: VoiceFaultPoint
    ) -> VoiceFailureCategory? {
        guard var failures = schedule[point], !failures.isEmpty else {
            return nil
        }
        let failure = failures.removeFirst()
        if failures.isEmpty {
            schedule.removeValue(forKey: point)
        } else {
            schedule[point] = failures
        }
        return failure
    }

    public func reset(
        schedule: [VoiceFaultPoint: [VoiceFailureCategory]] = [:]
    ) {
        self.schedule = schedule
    }
}
