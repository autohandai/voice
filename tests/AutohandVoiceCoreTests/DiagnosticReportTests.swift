import Foundation
import XCTest
@testable import AutohandVoiceCore

final class DiagnosticReportTests: XCTestCase {
    func testReportContainsOnlyExplicitRedactedFields() throws {
        let deviceName = "Igor /Users/igorcosta secret microphone"
        let runtime = DiagnosticRuntime(
            shortcutState: .registered,
            microphoneState: .configured,
            microphoneDisplayName: deviceName,
            signal: .healthy,
            modelState: .ready,
            modelStorageBytes: 42,
            issues: [
                OperationalIssue(
                    kind: .insertion,
                    firstSeenAt: Date(timeIntervalSince1970: 10),
                    lastSeenAt: Date(timeIntervalSince1970: 20),
                    count: 2
                ),
            ]
        )
        let report = DiagnosticSnapshot(
            check: SystemCheck(),
            preferences: VoicePreferences(),
            runtime: runtime
        ).report

        let data = try JSONEncoder().encode(report)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            Set(object.keys),
            [
                "accessibilityPermission",
                "architecture",
                "dictationLanguageCode",
                "macOSVersion",
                "microphonePermission",
                "modelState",
                "modelStorageBytes",
                "modelVersion",
                "product",
                "recentOperationalIssues",
                "remoteFallbackEnabled",
                "selectedMicrophone",
                "shortcut",
                "shortcutState",
                "signal",
                "speechEngine",
                "supported",
                "version",
            ]
        )
        XCTAssertEqual(object["product"] as? String, Brand.productName)
        XCTAssertEqual(object["remoteFallbackEnabled"] as? Bool, false)
        XCTAssertEqual(object["selectedMicrophone"] as? String, "configured")
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(deviceName))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/Users/"))
    }

    func testEveryUnavailableCheckHasOneRemediation() {
        let snapshot = DiagnosticSnapshot(
            check: SystemCheck(
                supported: false,
                architecture: "unsupported",
                macOSVersion: "13.0.0",
                microphonePermission: "denied",
                accessibilityPermission: false
            ),
            preferences: VoicePreferences(),
            runtime: DiagnosticRuntime(
                shortcutState: .unavailable,
                microphoneState: .unavailable,
                microphoneDisplayName: "Unavailable",
                signal: .disconnected,
                modelState: .unavailable
            )
        )

        let failures = snapshot.checks.filter {
            $0.status == .unavailable
        }
        XCTAssertFalse(failures.isEmpty)
        for failure in failures {
            XCTAssertNotNil(
                failure.remediation,
                "\(failure.id) has no remediation"
            )
        }
    }

    func testSnapshotKeepsPrivateMicrophoneNameOnlyInAppRows() {
        let snapshot = DiagnosticSnapshot(
            check: SystemCheck(),
            preferences: VoicePreferences(),
            runtime: DiagnosticRuntime(
                microphoneState: .configured,
                microphoneDisplayName: "Studio Microphone"
            )
        )

        XCTAssertEqual(
            snapshot.checks.first { $0.id == .microphone }?.value,
            "Studio Microphone"
        )
        XCTAssertEqual(snapshot.report.selectedMicrophone, .configured)
    }
}
