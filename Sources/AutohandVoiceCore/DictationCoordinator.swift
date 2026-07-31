import Foundation

public enum DictationOrigin: String, Codable, CaseIterable, Sendable {
    case keyboard
    case shortcut
    case menu
    case hud
    case pointer
    case onboarding
    case scratchpad
}

public enum DictationStyle: String, Codable, CaseIterable, Sendable {
    case literal
    case light
    case medium
    case high
}

public struct DictationSessionProfile: Codable, Equatable, Sendable {
    public let modelVersion: SpeechModelVariant
    public let language: SupportedDictationLanguage
    public let outputMode: OutputMode
    public let style: DictationStyle

    public init(
        modelVersion: SpeechModelVariant,
        language: SupportedDictationLanguage,
        outputMode: OutputMode,
        style: DictationStyle
    ) {
        self.modelVersion = modelVersion
        self.language = language
        self.outputMode = outputMode
        self.style = style
    }

    public static let `default` = DictationSessionProfile(
        modelVersion: .default,
        language: .english,
        outputMode: .type,
        style: .literal
    )
}

public enum DictationLifecycleEvent: String, Codable, CaseIterable, Sendable {
    case sleep
    case terminationConfirmed = "termination_confirmed"
}

public enum DictationTerminalRequest: String, Codable, CaseIterable, Sendable {
    case stop
    case cancel
    case durationLimit = "duration_limit"
    case sleep
    case termination
    case failure
}

public enum DictationCompletionOutcome:
    String,
    Codable,
    CaseIterable,
    Sendable
{
    case inserted
    case copied
}

public enum DictationCoordinatorState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case finalizing
    case revising
    case committing
    case completed(DictationCompletionOutcome)
    case cancelled
    case interrupted(RecoverableVoiceArtifact)
    case failed(VoiceFailureCategory, RecoverableVoiceArtifact)
}

public struct DictationTerminalEvent: Equatable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let request: DictationTerminalRequest

    public init(
        id: UUID,
        sessionID: UUID,
        request: DictationTerminalRequest
    ) {
        self.id = id
        self.sessionID = sessionID
        self.request = request
    }
}

public struct DictationSnapshot: Equatable, Sendable {
    public let sequence: Int
    public let state: DictationCoordinatorState
    public let sessionID: UUID?
    public let startedAtUptimeNanoseconds: UInt64?
    public let origin: DictationOrigin?
    public let profile: DictationSessionProfile?
    public let terminalRequest: DictationTerminalRequest?
    public let terminalEvent: DictationTerminalEvent?
    public let acceptedFinalCount: Int
    public let commitCount: Int

    public var allowsProvisionalText: Bool {
        state == .recording
    }
}

public enum DictationIntent: Sendable {
    case start(
        origin: DictationOrigin,
        profile: DictationSessionProfile?
    )
    case captureStarted(UUID)
    case stop
    case cancel
    case durationLimitReached
    case rawFinalProduced(UUID)
    case revisionProduced(UUID)
    case dictationCommandCancelled(UUID)
    case commitSucceeded(
        UUID,
        outcome: DictationCompletionOutcome
    )
    case fail(UUID?, category: VoiceFailureCategory)
    case selectLanguage(SupportedDictationLanguage)
    case selectStyle(DictationStyle)
    case retryRecovery
    case retryInsertion
    case copyFinal
    case discardRecovery
    case handleLifecycleEvent(DictationLifecycleEvent)
}

/// Serializes session transitions and makes terminal races deterministic.
///
/// This actor owns no text, audio, UI, or platform adapter. Those side effects
/// report finite intents back with the session identifier they received.
public actor DictationCoordinator {
    private let idProvider: @Sendable () -> UUID
    private let uptimeProvider: @Sendable () -> UInt64

    private var sequence = 0
    private var state: DictationCoordinatorState = .idle
    private var sessionID: UUID?
    private var startedAtUptimeNanoseconds: UInt64?
    private var origin: DictationOrigin?
    private var profile: DictationSessionProfile?
    private var terminalRequest: DictationTerminalRequest?
    private var terminalEvent: DictationTerminalEvent?
    private var acceptedFinalCount = 0
    private var commitCount = 0
    private var selectedLanguage = SupportedDictationLanguage.english
    private var selectedStyle = DictationStyle.literal
    private var continuations:
        [UUID: AsyncStream<DictationSnapshot>.Continuation] = [:]

    public init(
        idProvider: @escaping @Sendable () -> UUID = { UUID() },
        uptimeProvider: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        }
    ) {
        self.idProvider = idProvider
        self.uptimeProvider = uptimeProvider
    }

    @discardableResult
    public func handle(_ intent: DictationIntent) -> DictationSnapshot {
        sequence += 1
        transition(for: intent)
        let current = snapshot()
        for continuation in continuations.values {
            continuation.yield(current)
        }
        return current
    }

    public func currentSnapshot() -> DictationSnapshot {
        snapshot()
    }

    public func snapshots() -> AsyncStream<DictationSnapshot> {
        let token = idProvider()
        let (stream, continuation) =
            AsyncStream<DictationSnapshot>.makeStream(
                bufferingPolicy: .bufferingNewest(32)
            )
        continuations[token] = continuation
        continuation.yield(snapshot())
        continuation.onTermination = { [weak self] _ in
            Task {
                await self?.removeContinuation(token)
            }
        }
        return stream
    }

    private func transition(for intent: DictationIntent) {
        switch intent {
        case let .start(origin, requestedProfile):
            guard canStartNewSession else { return }
            let resolvedProfile = requestedProfile
                ?? DictationSessionProfile(
                    modelVersion: .default,
                    language: selectedLanguage,
                    outputMode: .type,
                    style: selectedStyle
                )
            state = .starting
            sessionID = idProvider()
            startedAtUptimeNanoseconds = uptimeProvider()
            self.origin = origin
            profile = resolvedProfile
            terminalRequest = nil
            terminalEvent = nil
            acceptedFinalCount = 0
            commitCount = 0

        case let .captureStarted(eventSessionID):
            guard
                state == .starting,
                eventSessionID == sessionID
            else { return }
            switch terminalRequest {
            case .cancel:
                finishTerminal(.cancelled, request: .cancel)
            case .sleep:
                finishTerminal(
                    .interrupted(.none),
                    request: .sleep
                )
            case .termination:
                finishTerminal(.cancelled, request: .termination)
            case .stop, .durationLimit:
                state = .finalizing
            case .failure, .none:
                state = .recording
            }

        case .stop:
            requestFinalization(.stop)

        case .durationLimitReached:
            requestFinalization(.durationLimit)

        case .cancel:
            switch state {
            case .starting:
                guard terminalRequest == nil else { return }
                terminalRequest = .cancel
            case .recording:
                guard terminalRequest == nil else { return }
                finishTerminal(.cancelled, request: .cancel)
            default:
                return
            }

        case let .rawFinalProduced(eventSessionID):
            guard
                state == .finalizing,
                eventSessionID == sessionID,
                acceptedFinalCount == 0
            else { return }
            acceptedFinalCount = 1
            state = .revising

        case let .revisionProduced(eventSessionID):
            guard
                state == .revising,
                eventSessionID == sessionID,
                acceptedFinalCount == 1
            else { return }
            state = .committing

        case let .dictationCommandCancelled(eventSessionID):
            guard
                state == .finalizing,
                eventSessionID == sessionID,
                acceptedFinalCount == 0
            else { return }
            finishTerminal(.cancelled, request: .cancel)

        case let .commitSucceeded(eventSessionID, outcome):
            guard
                state == .committing,
                eventSessionID == sessionID,
                acceptedFinalCount == 1,
                commitCount == 0
            else { return }
            commitCount = 1
            finishTerminal(
                .completed(outcome),
                request: terminalRequest ?? .stop
            )

        case let .fail(eventSessionID, category):
            if let eventSessionID, eventSessionID != sessionID {
                return
            }
            guard !hasTerminalEvent else { return }
            let artifact = category.policy.recoverableArtifact
            finishTerminal(
                .failed(category, artifact),
                request: .failure
            )

        case let .selectLanguage(language):
            guard canChangeNextSessionProfile else { return }
            selectedLanguage = language

        case let .selectStyle(style):
            guard canChangeNextSessionProfile else { return }
            selectedStyle = style

        case .retryRecovery:
            guard recoverableArtifact == .capturedAudio else { return }
            beginRecovery(in: .finalizing)

        case .retryInsertion:
            guard recoverableArtifact == .finalTranscript else { return }
            beginRecovery(in: .committing)

        case .copyFinal:
            guard recoverableArtifact == .finalTranscript else { return }
            beginRecovery(in: .committing)
            guard let sessionID else { return }
            transition(
                for: .commitSucceeded(sessionID, outcome: .copied)
            )

        case .discardRecovery:
            guard recoverableArtifact != .none else { return }
            resetToIdle()

        case let .handleLifecycleEvent(event):
            handleLifecycleEvent(event)
        }
    }

    private func requestFinalization(
        _ request: DictationTerminalRequest
    ) {
        switch state {
        case .starting:
            guard terminalRequest == nil else { return }
            terminalRequest = request
        case .recording:
            guard terminalRequest == nil else { return }
            terminalRequest = request
            state = .finalizing
        default:
            return
        }
    }

    private func handleLifecycleEvent(_ event: DictationLifecycleEvent) {
        switch event {
        case .sleep:
            switch state {
            case .starting:
                guard terminalRequest == nil else { return }
                terminalRequest = .sleep
            case .recording, .finalizing:
                finishTerminal(
                    .interrupted(.capturedAudio),
                    request: .sleep
                )
            case .revising, .committing:
                finishTerminal(
                    .interrupted(.finalTranscript),
                    request: .sleep
                )
            default:
                return
            }
        case .terminationConfirmed:
            switch state {
            case .starting, .recording, .finalizing, .revising, .committing:
                finishTerminal(.cancelled, request: .termination)
            default:
                return
            }
        }
    }

    private func beginRecovery(in newState: DictationCoordinatorState) {
        state = newState
        sessionID = idProvider()
        startedAtUptimeNanoseconds = uptimeProvider()
        origin = .menu
        terminalRequest = nil
        terminalEvent = nil
        acceptedFinalCount = newState == .committing ? 1 : 0
        commitCount = 0
    }

    private func finishTerminal(
        _ terminalState: DictationCoordinatorState,
        request: DictationTerminalRequest
    ) {
        guard let sessionID, terminalEvent == nil else { return }
        state = terminalState
        terminalRequest = request
        terminalEvent = DictationTerminalEvent(
            id: idProvider(),
            sessionID: sessionID,
            request: request
        )
    }

    private func resetToIdle() {
        state = .idle
        sessionID = nil
        startedAtUptimeNanoseconds = nil
        origin = nil
        profile = nil
        terminalRequest = nil
        terminalEvent = nil
        acceptedFinalCount = 0
        commitCount = 0
    }

    private var canStartNewSession: Bool {
        switch state {
        case .idle, .completed, .cancelled:
            true
        case let .failed(_, artifact), let .interrupted(artifact):
            artifact == .none
        default:
            false
        }
    }

    private var canChangeNextSessionProfile: Bool {
        switch state {
        case .idle, .completed, .cancelled, .failed, .interrupted:
            true
        default:
            false
        }
    }

    private var recoverableArtifact: RecoverableVoiceArtifact {
        switch state {
        case let .failed(_, artifact), let .interrupted(artifact):
            artifact
        default:
            .none
        }
    }

    private var hasTerminalEvent: Bool {
        terminalEvent != nil
    }

    private func snapshot() -> DictationSnapshot {
        DictationSnapshot(
            sequence: sequence,
            state: state,
            sessionID: sessionID,
            startedAtUptimeNanoseconds: startedAtUptimeNanoseconds,
            origin: origin,
            profile: profile,
            terminalRequest: terminalRequest,
            terminalEvent: terminalEvent,
            acceptedFinalCount: acceptedFinalCount,
            commitCount: commitCount
        )
    }

    private func removeContinuation(_ token: UUID) {
        continuations.removeValue(forKey: token)
    }
}
