import Foundation

public enum VoiceLifecycleEvent: Sendable {
    case sleep
    case wake
    case termination
}

public enum DictationActivity: CaseIterable, Sendable {
    case ready
    case starting
    case recording
    case processing
}

public enum VoiceLifecycleAction: Equatable, Sendable {
    case none
    case cancelAndReport
    case retainAudioAndReport
    case restoreRuntimeHandlers
    case confirmDiscard
}

public enum VoiceLifecyclePolicy {
    public static func action(
        for event: VoiceLifecycleEvent,
        activity: DictationActivity
    ) -> VoiceLifecycleAction {
        switch event {
        case .wake:
            .restoreRuntimeHandlers
        case .sleep:
            switch activity {
            case .starting:
                .cancelAndReport
            case .recording:
                .retainAudioAndReport
            case .ready, .processing:
                .none
            }
        case .termination:
            switch activity {
            case .starting, .recording:
                .confirmDiscard
            case .ready, .processing:
                .none
            }
        }
    }
}
