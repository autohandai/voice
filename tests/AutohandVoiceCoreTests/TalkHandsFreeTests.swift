import XCTest
@testable import AutohandVoiceCore

final class TalkEndpointerTests: XCTestCase {
    /// Levels arrive about 20 times a second, like the capture tap's.
    private let step = 0.05
    private let room: Float = 0.007   // about -43 dBFS
    private let speech: Float = 0.06  // about -24 dBFS

    private func feed(
        _ endpointer: inout TalkEndpointer,
        _ rms: Float,
        seconds: Double,
        from start: Double
    ) -> (TalkEndpointer.Decision, Double) {
        var time = start
        var decision = TalkEndpointer.Decision.waiting
        while time < start + seconds - 1e-9 {
            decision = endpointer.observe(rms: rms, at: time)
            time += step
            if decision == .endOfTurn || decision == .idleTimeout { break }
        }
        return (decision, time)
    }

    func testRoomToneAloneNeverEndsATurn() {
        var endpointer = TalkEndpointer()
        let (decision, _) = feed(&endpointer, room, seconds: 10, from: 0)
        XCTAssertEqual(decision, .waiting)
    }

    func testSpeechFollowedBySilenceEndsTheTurn() {
        var endpointer = TalkEndpointer()
        var (decision, time) = feed(&endpointer, room, seconds: 1, from: 0)
        (decision, time) = feed(&endpointer, speech, seconds: 2, from: time)
        XCTAssertEqual(decision, .speaking)
        let silenceStart = time
        (decision, time) = feed(&endpointer, room, seconds: 3, from: time)
        XCTAssertEqual(decision, .endOfTurn)
        let silence = time - silenceStart
        XCTAssertGreaterThanOrEqual(silence, TalkEndpointer.Policy().endSilence - step)
        XCTAssertLessThan(silence, TalkEndpointer.Policy().endSilence + 0.3)
    }

    func testShortPausesInsideASentenceDoNotEndTheTurn() {
        var endpointer = TalkEndpointer()
        var (decision, time) = feed(&endpointer, room, seconds: 0.5, from: 0)
        (decision, time) = feed(&endpointer, speech, seconds: 1, from: time)
        (decision, time) = feed(&endpointer, room, seconds: 0.6, from: time)
        XCTAssertEqual(decision, .speaking)
        (decision, time) = feed(&endpointer, speech, seconds: 1, from: time)
        XCTAssertEqual(decision, .speaking)
    }

    func testSpeakingStraightAwayIsHeardAfterTheFirstGapBetweenWords() {
        var endpointer = TalkEndpointer()
        var (_, time) = feed(&endpointer, speech, seconds: 0.5, from: 0)
        (_, time) = feed(&endpointer, room, seconds: 0.25, from: time)
        let (decision, _) = feed(&endpointer, speech, seconds: 1, from: time)
        XCTAssertEqual(decision, .speaking)
    }

    func testTheRoomLevelCarriesOverToTheNextTurn() {
        var first = TalkEndpointer()
        _ = feed(&first, room, seconds: 1, from: 0)
        var next = TalkEndpointer(noiseFloorDB: first.noiseFloorDB)
        let (decision, _) = feed(&next, speech, seconds: 1, from: 0)
        XCTAssertEqual(decision, .speaking)
    }

    func testAFloorLearnedDuringLoudSoundCannotHideSpeech() {
        // Carried over from a moment when speech or a reply was playing.
        var endpointer = TalkEndpointer(noiseFloorDB: -12)
        var (decision, time) = feed(&endpointer, speech, seconds: 1, from: 0)
        XCTAssertEqual(decision, .speaking)
        (decision, _) = feed(&endpointer, room, seconds: 3, from: time)
        XCTAssertEqual(decision, .endOfTurn)
    }

    func testSilentWarmUpBuffersDoNotMakeRoomToneLookLikeSpeech() {
        var endpointer = TalkEndpointer()
        var (decision, time) = feed(&endpointer, 0, seconds: 0.4, from: 0)
        (decision, time) = feed(&endpointer, room, seconds: 3, from: time)
        XCTAssertEqual(decision, .waiting)
        (decision, time) = feed(&endpointer, speech, seconds: 1, from: time)
        XCTAssertEqual(decision, .speaking)
        (decision, _) = feed(&endpointer, room, seconds: 3, from: time)
        XCTAssertEqual(decision, .endOfTurn)
    }

    func testQuietSpeechAFewDecibelsAboveTheRoomIsHeard() {
        var endpointer = TalkEndpointer()
        // Room about -43 dBFS with its usual wobble; speech about -35 dBFS.
        var time = 0.0
        var decision = TalkEndpointer.Decision.waiting
        for index in 0..<60 {
            let wobble: Float = index % 7 == 0 ? 0.0125 : 0.007
            decision = endpointer.observe(rms: wobble, at: time)
            time += step
        }
        XCTAssertEqual(decision, .waiting)
        var (next, after) = feed(&endpointer, 0.018, seconds: 1, from: time)
        XCTAssertEqual(next, .speaking)
        (next, _) = feed(&endpointer, room, seconds: 3, from: after)
        XCTAssertEqual(next, .endOfTurn)
    }

    func testABriefClickIsNotSpeech() {
        var endpointer = TalkEndpointer()
        var (_, time) = feed(&endpointer, room, seconds: 1, from: 0)
        (_, time) = feed(&endpointer, 0.2, seconds: 0.1, from: time)
        let (decision, _) = feed(&endpointer, room, seconds: 3, from: time)
        XCTAssertEqual(decision, .waiting)
    }

    func testNobodySpeakingEventuallyTimesOut() {
        var endpointer = TalkEndpointer()
        let (decision, time) = feed(&endpointer, room, seconds: 60, from: 0)
        XCTAssertEqual(decision, .idleTimeout)
        XCTAssertEqual(time, TalkEndpointer.Policy().idleTimeout, accuracy: 0.2)
    }

    func testANoisyRoomRaisesTheBarForSpeech() {
        var endpointer = TalkEndpointer()
        let noisy: Float = 0.03 // about -30 dBFS fan or café
        var (decision, time) = feed(&endpointer, noisy, seconds: 3, from: 0)
        XCTAssertEqual(decision, .waiting)
        (decision, time) = feed(&endpointer, 0.2, seconds: 1, from: time)
        XCTAssertEqual(decision, .speaking)
        (decision, _) = feed(&endpointer, noisy, seconds: 3, from: time)
        XCTAssertEqual(decision, .endOfTurn)
    }
}

final class TalkTriggerTests: XCTestCase {
    func testPlainFnIsDictation() {
        XCTAssertEqual(
            TalkTrigger.resolve(shift: false, command: false, recordingMode: .pressAndHold, talkEnabled: true),
            .dictation
        )
        XCTAssertEqual(
            TalkTrigger.resolve(shift: false, command: true, recordingMode: .handsFree, talkEnabled: true),
            .dictation
        )
    }

    func testFnShiftIsATalkTurnAndCommandMakesItHandsFree() {
        XCTAssertEqual(
            TalkTrigger.resolve(shift: true, command: false, recordingMode: .pressAndHold, talkEnabled: true),
            .talkTurn
        )
        XCTAssertEqual(
            TalkTrigger.resolve(shift: true, command: true, recordingMode: .pressAndHold, talkEnabled: true),
            .handsFreeTalk
        )
    }

    func testHandsFreeRecordingModeMakesFnShiftHandsFree() {
        XCTAssertEqual(
            TalkTrigger.resolve(shift: true, command: false, recordingMode: .handsFree, talkEnabled: true),
            .handsFreeTalk
        )
    }

    func testTalkOffMeansDictation() {
        XCTAssertEqual(
            TalkTrigger.resolve(shift: true, command: true, recordingMode: .handsFree, talkEnabled: false),
            .dictation
        )
    }
}

final class TalkTranscriptTests: XCTestCase {
    func testConversationReadsAsAPlainTranscript() {
        let turns = [
            TalkTurn(question: "What's a good name for a coffee cart?", reply: "Bean There."),
            TalkTurn(question: "Something more serious?", reply: "Harbour Roast."),
        ]
        XCTAssertEqual(
            TalkTranscript.text(turns),
            """
            You: What's a good name for a coffee cart?

            Fantail: Bean There.

            You: Something more serious?

            Fantail: Harbour Roast.
            """
        )
    }

    func testTheAnswerIsCreditedToWhoeverAnswered() {
        let turns = [TalkTurn(question: "Hi", reply: "Hello!")]
        XCTAssertEqual(
            TalkTranscript.text(turns, assistantName: "Bonsai"),
            "You: Hi\n\nBonsai: Hello!"
        )
    }

    func testEmptyConversationIsEmptyText() {
        XCTAssertEqual(TalkTranscript.text([]), "")
    }

    func testHistoryKeepsTheMostRecentTurnsWithinBounds() {
        var history = TalkHistory()
        for index in 0..<(TalkHistory.maximumTurns + 5) {
            history.append(TalkTurn(question: "q\(index)", reply: "r\(index)"))
        }
        XCTAssertEqual(history.turns.count, TalkHistory.maximumTurns)
        XCTAssertEqual(history.turns.first?.question, "q5")
        history.removeAll()
        XCTAssertTrue(history.turns.isEmpty)
    }
}
