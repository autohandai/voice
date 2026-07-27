import Foundation
import XCTest
@testable import AutohandVoiceCore

final class FileTranscriptionTests: XCTestCase {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        var value: Int { lock.withLock { storage } }
        func increment() { lock.withLock { storage += 1 } }
    }

    func testSupportedAudioExtensionsAreAcceptedBeforeModelWork() throws {
        for name in [
            "voice.wav", "voice.wave", "voice.aac", "voice.m4a", "voice.mp3",
            "voice.aiff", "voice.aif", "voice.caf", "voice.flac",
        ] {
            XCTAssertNoThrow(
                try AudioImportValidator.validate(
                    URL(fileURLWithPath: "/tmp/\(name)")
                )
            )
        }
    }

    func testUnsupportedImportIsRejectedDeterministically() {
        XCTAssertThrowsError(
            try AudioImportValidator.validate(
                URL(fileURLWithPath: "/tmp/meeting.mov")
            )
        ) {
            XCTAssertEqual(
                $0 as? AudioImportError,
                .unsupportedFormat("mov")
            )
        }
    }

    func testSecurityScopedLeaseStopsExactlyOnce() {
        let stopCount = Counter()
        let lease = SecurityScopedResourceLease(
            start: { true },
            stop: { stopCount.increment() }
        )

        XCTAssertTrue(lease.isActive)
        lease.close()
        lease.close()

        XCTAssertEqual(stopCount.value, 1)
    }

    func testInactiveSecurityScopeDoesNotStop() {
        let stopCount = Counter()
        let lease = SecurityScopedResourceLease(
            start: { false },
            stop: { stopCount.increment() }
        )

        XCTAssertFalse(lease.isActive)
        lease.close()

        XCTAssertEqual(stopCount.value, 0)
    }
}
