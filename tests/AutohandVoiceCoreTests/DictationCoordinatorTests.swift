import Foundation
import XCTest
@testable import AutohandVoiceCore

final class DictationCoordinatorTests: XCTestCase {
    func testStopWinsWhenItArrivesBeforeCancelAndCommitsOnce() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .keyboard, profile: .default)
        )
        let sessionID = try! XCTUnwrap(started.sessionID)

        _ = await coordinator.handle(.captureStarted(sessionID))
        let stopping = await coordinator.handle(.stop)
        let lateCancel = await coordinator.handle(.cancel)

        XCTAssertEqual(stopping.state, .finalizing)
        XCTAssertEqual(lateCancel.state, .finalizing)
        XCTAssertEqual(lateCancel.terminalRequest, .stop)

        _ = await coordinator.handle(.rawFinalProduced(sessionID))
        _ = await coordinator.handle(.revisionProduced(sessionID))
        let completed = await coordinator.handle(
            .commitSucceeded(sessionID, outcome: .inserted)
        )
        let duplicate = await coordinator.handle(
            .commitSucceeded(sessionID, outcome: .inserted)
        )

        XCTAssertEqual(completed.state, .completed(.inserted))
        XCTAssertEqual(completed.acceptedFinalCount, 1)
        XCTAssertEqual(completed.commitCount, 1)
        XCTAssertEqual(duplicate.terminalEvent, completed.terminalEvent)
        XCTAssertEqual(duplicate.commitCount, 1)
    }

    func testCancelWinsWhenItArrivesBeforeStop() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .menu, profile: .default)
        )
        let sessionID = try! XCTUnwrap(started.sessionID)
        _ = await coordinator.handle(.captureStarted(sessionID))

        let cancelled = await coordinator.handle(.cancel)
        let lateStop = await coordinator.handle(.stop)
        let lateFinal = await coordinator.handle(
            .rawFinalProduced(sessionID)
        )

        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.terminalRequest, .cancel)
        XCTAssertEqual(lateStop.terminalEvent, cancelled.terminalEvent)
        XCTAssertEqual(lateFinal.state, .cancelled)
        XCTAssertEqual(lateFinal.acceptedFinalCount, 0)
        XCTAssertEqual(lateFinal.commitCount, 0)
    }

    func testStopDuringStartupFinalizesAfterCaptureStarts() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .shortcut, profile: .default)
        )
        let sessionID = try! XCTUnwrap(started.sessionID)

        let queuedStop = await coordinator.handle(.stop)
        XCTAssertEqual(queuedStop.state, .starting)
        XCTAssertEqual(queuedStop.terminalRequest, .stop)

        let captureStarted = await coordinator.handle(
            .captureStarted(sessionID)
        )
        XCTAssertEqual(captureStarted.state, .finalizing)
        XCTAssertEqual(captureStarted.terminalRequest, .stop)
    }

    func testSleepDuringStartupTerminatesWithoutFinalOrCommit() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .hud, profile: .default)
        )
        let sessionID = try! XCTUnwrap(started.sessionID)

        _ = await coordinator.handle(.handleLifecycleEvent(.sleep))
        let interrupted = await coordinator.handle(
            .captureStarted(sessionID)
        )

        XCTAssertEqual(interrupted.state, .interrupted(.none))
        XCTAssertEqual(interrupted.terminalRequest, .sleep)
        XCTAssertEqual(interrupted.acceptedFinalCount, 0)
        XCTAssertEqual(interrupted.commitCount, 0)
    }

    func testProvisionalVisibilityExistsOnlyWhileRecording() async {
        let coordinator = DictationCoordinator()
        let starting = await coordinator.handle(
            .start(origin: .keyboard, profile: .default)
        )
        let sessionID = try! XCTUnwrap(starting.sessionID)
        XCTAssertFalse(starting.allowsProvisionalText)

        let recording = await coordinator.handle(
            .captureStarted(sessionID)
        )
        XCTAssertTrue(recording.allowsProvisionalText)

        let finalizing = await coordinator.handle(.durationLimitReached)
        XCTAssertFalse(finalizing.allowsProvisionalText)
    }

    func testFailureUsesFiniteRecoverabilityPolicy() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .keyboard, profile: .default)
        )
        let sessionID = try! XCTUnwrap(started.sessionID)

        let failed = await coordinator.handle(
            .fail(
                sessionID,
                category: .insertion(.rejected)
            )
        )

        XCTAssertEqual(
            failed.state,
            .failed(.insertion(.rejected), .finalTranscript)
        )
        XCTAssertEqual(failed.terminalRequest, .failure)
        XCTAssertNotNil(failed.terminalEvent)
    }

    func testLanguageAndStyleAreFrozenForActiveSession() async {
        let coordinator = DictationCoordinator()
        _ = await coordinator.handle(.selectLanguage(.spanish))
        _ = await coordinator.handle(.selectStyle(.medium))
        let started = await coordinator.handle(
            .start(origin: .keyboard, profile: nil)
        )

        _ = await coordinator.handle(.selectLanguage(.german))
        let unchanged = await coordinator.handle(.selectStyle(.literal))

        XCTAssertEqual(started.profile?.language, .spanish)
        XCTAssertEqual(started.profile?.style, .medium)
        XCTAssertEqual(unchanged.profile, started.profile)
    }

    func testMismatchedSessionEventsAreIgnored() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .keyboard, profile: .default)
        )

        let ignored = await coordinator.handle(
            .captureStarted(UUID())
        )
        XCTAssertEqual(ignored.state, .starting)
        XCTAssertEqual(ignored.sessionID, started.sessionID)
    }

    func testSnapshotStreamEmitsInitialAndTransitionStates() async {
        let coordinator = DictationCoordinator()
        let stream = await coordinator.snapshots()
        var iterator = stream.makeAsyncIterator()

        let initial = await iterator.next()
        _ = await coordinator.handle(
            .start(origin: .keyboard, profile: .default)
        )
        let starting = await iterator.next()

        XCTAssertEqual(initial?.state, .idle)
        XCTAssertEqual(starting?.state, .starting)
        XCTAssertGreaterThan(starting?.sequence ?? 0, initial?.sequence ?? 0)
    }

    func testExplicitVoiceCommandCancelsBeforeRawFinalIsAccepted() async {
        let coordinator = DictationCoordinator()
        let started = await coordinator.handle(
            .start(origin: .keyboard, profile: .default)
        )
        let sessionID = try! XCTUnwrap(started.sessionID)
        _ = await coordinator.handle(.captureStarted(sessionID))
        _ = await coordinator.handle(.stop)

        let cancelled = await coordinator.handle(
            .dictationCommandCancelled(sessionID)
        )

        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertEqual(cancelled.acceptedFinalCount, 0)
        XCTAssertEqual(cancelled.commitCount, 0)
    }
}
