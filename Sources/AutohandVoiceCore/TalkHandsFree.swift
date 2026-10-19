import Foundation

/// Decides when a hands-free Talk turn is over from the microphone level.
/// The noise floor is measured briefly when listening starts and then
/// follows the room, so a quiet office and a busy café both work: speech is
/// anything clearly above the floor, and a turn ends after a pause.
public struct TalkEndpointer: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Nothing said yet.
        case waiting
        /// The person is talking, or pausing mid-sentence.
        case speaking
        /// They spoke and then paused long enough: send the turn.
        case endOfTurn
        /// Nobody spoke for a long time: stop listening.
        case idleTimeout
    }

    public struct Policy: Equatable, Sendable {
        /// How far above the noise floor counts as speech.
        public var speechMarginDB = 7.0
        /// Speech must also be louder than this, so a very quiet room does
        /// not turn breathing into speech.
        public var minimumSpeechDB = -45.0
        /// Continuous speech needed before a turn starts (ignores clicks).
        public var minimumSpeech: TimeInterval = 0.5
        /// A pause this long after speech ends the turn.
        public var endSilence: TimeInterval = 1.2
        /// Stop listening if nobody speaks for this long.
        public var idleTimeout: TimeInterval = 30
        /// Time spent measuring the room before listening for speech.
        public var calibration: TimeInterval = 0.3
        /// How quickly the floor may rise while it is quiet.
        public var floorRiseDBPerSecond = 1.0
        /// The floor never sits above this, so a level learned while
        /// something loud was playing can't make speech undetectable.
        public var maximumFloorDB = -33.0
        /// Buffers quieter than this are the microphone warming up (digital
        /// silence), not the room; they are ignored.
        public var digitalSilenceDB = -100.0

        public init() {}
    }

    public let policy: Policy
    private var startedAt: TimeInterval?
    private var lastTime: TimeInterval?
    private var floorDB: Double?
    private var calibrationMinimum = 0.0
    private var speechRunStart: TimeInterval?
    private var silenceStart: TimeInterval?
    private var turnStarted = false

    /// Pass the previous turn's `noiseFloorDB` to skip measuring the room
    /// again, so someone who answers straight away is heard.
    public init(policy: Policy = Policy(), noiseFloorDB: Double? = nil) {
        self.policy = policy
        floorDB = noiseFloorDB.map { min($0, policy.maximumFloorDB) }
    }

    public var hasHeardSpeech: Bool { turnStarted }

    /// The current estimate of the room's level, once measured.
    public var noiseFloorDB: Double? { floorDB }

    public mutating func observe(rms: Float, at time: TimeInterval) -> Decision {
        let decibels = 20 * log10(Double(max(rms, 1e-7)))
        if decibels < policy.digitalSilenceDB {
            // Warm-up silence: let time pass but learn nothing from it.
            if startedAt == nil { return .waiting }
            lastTime = time
            if turnStarted { return .speaking }
            return time - (startedAt ?? time) >= policy.idleTimeout
                ? .idleTimeout : .waiting
        }
        let elapsedSinceLast = lastTime.map { max(0, time - $0) } ?? 0
        lastTime = time
        guard let startedAt else {
            startedAt = time
            calibrationMinimum = decibels
            if floorDB == nil { return .waiting }
            return observe(rms: rms, at: time)
        }
        guard let floor = floorDB else {
            calibrationMinimum = min(calibrationMinimum, decibels)
            if time - startedAt >= policy.calibration {
                floorDB = min(calibrationMinimum, policy.maximumFloorDB)
            }
            return .waiting
        }

        let threshold = max(floor + policy.speechMarginDB, policy.minimumSpeechDB)
        let isSpeech = decibels > threshold
        if isSpeech {
            silenceStart = nil
            let runStart = speechRunStart ?? time
            speechRunStart = runStart
            if time - runStart >= policy.minimumSpeech {
                turnStarted = true
            }
        } else {
            speechRunStart = nil
            // The floor falls quickly to quieter levels and rises slowly, so
            // it follows the room without chasing the voice.
            if decibels < floor {
                floorDB = floor + (decibels - floor) * 0.3
            } else {
                floorDB = min(
                    decibels,
                    floor + policy.floorRiseDBPerSecond * elapsedSinceLast,
                    policy.maximumFloorDB
                )
            }
            if turnStarted {
                let pauseStart = silenceStart ?? time
                silenceStart = pauseStart
                if time - pauseStart >= policy.endSilence {
                    return .endOfTurn
                }
            }
        }

        if turnStarted { return .speaking }
        if time - startedAt >= policy.idleTimeout { return .idleTimeout }
        return .waiting
    }
}

/// Modifiers seen while Fn was held.
public struct FunctionKeyModifiers: Equatable, Sendable {
    public var shift: Bool
    public var command: Bool

    public init(shift: Bool = false, command: Bool = false) {
        self.shift = shift
        self.command = command
    }
}

/// What a press of Fn means, from the modifiers held with it.
public enum TalkTrigger: Equatable, Sendable {
    /// Plain dictation at the cursor.
    case dictation
    /// One Talk question while Fn is held.
    case talkTurn
    /// A hands-free Talk conversation that keeps listening between replies.
    case handsFreeTalk

    /// Fn + Shift asks Fantail; adding Command, or using the Hands-Free
    /// recording mode, keeps the conversation going without holding keys.
    public static func resolve(
        shift: Bool,
        command: Bool,
        recordingMode: RecordingMode,
        talkEnabled: Bool
    ) -> TalkTrigger {
        guard shift, talkEnabled else { return .dictation }
        if command || recordingMode == .handsFree { return .handsFreeTalk }
        return .talkTurn
    }
}

/// One question and its answer.
public struct TalkTurn: Equatable, Sendable {
    public let question: String
    public let reply: String

    public init(question: String, reply: String) {
        self.question = question
        self.reply = reply
    }
}

/// Every turn of the current conversation, for copying it out at the end.
/// Separate from the short context sent to Fantail, and bounded.
public struct TalkHistory: Equatable, Sendable {
    public static let maximumTurns = 100

    public private(set) var turns: [TalkTurn] = []

    public init() {}

    public mutating func append(_ turn: TalkTurn) {
        turns.append(turn)
        if turns.count > Self.maximumTurns {
            turns.removeFirst(turns.count - Self.maximumTurns)
        }
    }

    public mutating func removeAll() {
        turns.removeAll()
    }
}

public enum TalkTranscript {
    public static func text(
        _ turns: [TalkTurn],
        assistantName: String = "Fantail"
    ) -> String {
        turns
            .flatMap { ["You: \($0.question)", "\(assistantName): \($0.reply)"] }
            .joined(separator: "\n\n")
    }
}
