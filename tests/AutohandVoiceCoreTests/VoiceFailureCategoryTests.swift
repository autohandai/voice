import XCTest
@testable import AutohandVoiceCore

final class VoiceFailureCategoryTests: XCTestCase {
    func testFailureCodesAreFiniteStableAndUnique() {
        let failures: [VoiceFailureCategory] = [
            .unsupportedPlatform,
            .permission(.microphone, .denied),
            .shortcut(.registrationFailed),
            .pointer(.eventTapUnavailable),
            .microphone(.startFailed),
            .audioRoute(.routeChanged),
            .capture(.bufferOverflow),
            .model(.loadFailed),
            .recognition(.failed),
            .revision(.failed),
            .target(.changed),
            .insertion(.rejected),
            .recovery(.audioMissing),
            .storage(.corrupt),
            .notification(.deliveryFailed),
            .sync(.unavailable),
            .account(.signedOut),
        ]

        XCTAssertEqual(Set(failures.map(\.code)).count, failures.count)
        XCTAssertTrue(failures.allSatisfy { !$0.code.isEmpty })
        XCTAssertTrue(
            failures.allSatisfy {
                $0.policy.safeDiagnosticFields.contains(.categoryCode)
            }
        )
    }

    func testPermissionFailureHasOneSpecificRemediation() {
        let failure = VoiceFailureCategory.permission(.microphone, .denied)

        XCTAssertEqual(failure.code, "permission.microphone.denied")
        XCTAssertEqual(failure.policy.recoverableArtifact, .none)
        XCTAssertEqual(
            failure.policy.primaryRemediation,
            .openMicrophoneSettings
        )
        XCTAssertFalse(failure.policy.retryIsIdempotent)
        XCTAssertFalse(failure.policy.canContinueWithLiteral)
        XCTAssertTrue(failure.policy.recordsReliabilityEvent)
        XCTAssertEqual(
            failure.policy.safeDiagnosticFields,
            [.categoryCode, .permissionKind, .permissionState]
        )
    }

    func testRecognitionAndRevisionPreserveRecoverableArtifacts() {
        let recognition = VoiceFailureCategory.recognition(.failed).policy
        XCTAssertEqual(recognition.recoverableArtifact, .capturedAudio)
        XCTAssertEqual(recognition.primaryRemediation, .retryLocalRecognition)
        XCTAssertTrue(recognition.retryIsIdempotent)
        XCTAssertFalse(recognition.canContinueWithLiteral)

        let revision = VoiceFailureCategory.revision(.failed).policy
        XCTAssertEqual(revision.recoverableArtifact, .finalTranscript)
        XCTAssertEqual(revision.primaryRemediation, .useLiteralTranscript)
        XCTAssertTrue(revision.retryIsIdempotent)
        XCTAssertTrue(revision.canContinueWithLiteral)
    }

    func testTargetAndInsertionFailuresPreserveFinalText() {
        let target = VoiceFailureCategory.target(.changed).policy
        XCTAssertEqual(target.recoverableArtifact, .finalTranscript)
        XCTAssertEqual(target.primaryRemediation, .refocusAndRetryInsertion)

        let insertion = VoiceFailureCategory.insertion(.rejected).policy
        XCTAssertEqual(insertion.recoverableArtifact, .finalTranscript)
        XCTAssertEqual(insertion.primaryRemediation, .copyFinalTranscript)
        XCTAssertTrue(insertion.retryIsIdempotent)
    }

    func testOptionalExternalFailuresNeverBlockLiteralLocalDictation() {
        let sync = VoiceFailureCategory.sync(.unavailable).policy
        let account = VoiceFailureCategory.account(.signedOut).policy

        XCTAssertTrue(sync.canContinueWithLiteral)
        XCTAssertTrue(account.canContinueWithLiteral)
        XCTAssertFalse(sync.recordsReliabilityEvent)
        XCTAssertFalse(account.recordsReliabilityEvent)
    }

    func testLegacyErrorsMapWithoutPersistingArbitraryReasons() {
        XCTAssertEqual(
            VoiceError.microphoneUnavailable("private device detail")
                .failureCategory,
            .microphone(.startFailed)
        )
        XCTAssertEqual(
            VoiceError.modelUnavailable("/private/model/path")
                .failureCategory,
            .model(.unavailable)
        )
        XCTAssertEqual(
            VoiceError.insertionTargetChanged.failureCategory,
            .target(.changed)
        )
        XCTAssertEqual(
            VoiceError.transcriptIsNotFinal.failureCategory,
            .recognition(.provisionalNotFinal)
        )
    }
}
