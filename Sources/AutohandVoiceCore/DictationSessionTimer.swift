import Foundation

public enum DictationDurationWarning:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case fifteenMinutes = "fifteen_minutes"
    case nineteenMinutes = "nineteen_minutes"

    var threshold: TimeInterval {
        switch self {
        case .fifteenMinutes:
            15 * 60
        case .nineteenMinutes:
            19 * 60
        }
    }

    public var label: LocalizedStringResource {
        switch self {
        case .fifteenMinutes:
            "15 minutes elapsed"
        case .nineteenMinutes:
            "One minute remaining"
        }
    }
}

public struct DictationDurationPolicy: Equatable, Sendable {
    public let maximumDuration: TimeInterval
    public let warnings: [DictationDurationWarning]

    public init(flags: FeatureFlags) {
        self = flags.isEnabled(.longDictation20)
            ? .twentyMinutes
            : .legacyFiveMinutes
    }

    public init(
        maximumDuration: TimeInterval,
        warnings: [DictationDurationWarning]
    ) {
        let boundedMaximumDuration = max(1, maximumDuration)
        self.maximumDuration = boundedMaximumDuration
        self.warnings = warnings
            .filter { $0.threshold < boundedMaximumDuration }
            .sorted { $0.threshold < $1.threshold }
    }

    public static let legacyFiveMinutes = DictationDurationPolicy(
        maximumDuration: 5 * 60,
        warnings: []
    )

    public static let twentyMinutes = DictationDurationPolicy(
        maximumDuration: 20 * 60,
        warnings: [.fifteenMinutes, .nineteenMinutes]
    )
}

public struct DictationTimerObservation: Equatable, Sendable {
    public let elapsed: TimeInterval
    public let remaining: TimeInterval
    public let newWarnings: [DictationDurationWarning]
    public let shouldFinalize: Bool
    public let isCancelled: Bool
}

public struct DictationSessionTimer: Sendable {
    public let policy: DictationDurationPolicy
    public let startedAt: TimeInterval

    private var lastElapsed: TimeInterval = 0
    private var emittedWarnings = Set<DictationDurationWarning>()
    private var didRequestFinalization = false
    private var cancelled = false

    public init(
        policy: DictationDurationPolicy,
        startedAt: TimeInterval
    ) {
        self.policy = policy
        self.startedAt = startedAt
    }

    public mutating func observe(
        at monotonicTime: TimeInterval
    ) -> DictationTimerObservation {
        let observedElapsed = max(0, monotonicTime - startedAt)
        lastElapsed = max(lastElapsed, observedElapsed)

        let newWarnings: [DictationDurationWarning]
        if cancelled {
            newWarnings = []
        } else {
            newWarnings = policy.warnings.filter {
                lastElapsed >= $0.threshold
                    && emittedWarnings.insert($0).inserted
            }
        }

        let shouldFinalize =
            !cancelled
                && !didRequestFinalization
                && lastElapsed >= policy.maximumDuration
        if shouldFinalize {
            didRequestFinalization = true
        }

        return DictationTimerObservation(
            elapsed: lastElapsed,
            remaining: max(0, policy.maximumDuration - lastElapsed),
            newWarnings: newWarnings,
            shouldFinalize: shouldFinalize,
            isCancelled: cancelled
        )
    }

    public mutating func cancel() {
        cancelled = true
    }
}
