import XCTest
@testable import AutohandVoiceCore

final class FeatureFlagTests: XCTestCase {
    func testAllFlagsDefaultOff() {
        let flags = FeatureFlags(environment: [:])

        for flag in FeatureFlag.allCases {
            XCTAssertFalse(flags.isEnabled(flag), "\(flag.rawValue) must default off")
        }
    }

    func testExplicitOptInValuesEnableFlagsCaseInsensitively() {
        let truthyValues = ["1", "true", "TRUE", "yes", "YeS", "on", "ON"]

        for value in truthyValues {
            let flags = FeatureFlags(
                environment: [FeatureFlag.hudEdgePlacement.environmentKey: value]
            )

            XCTAssertTrue(
                flags.isEnabled(.hudEdgePlacement),
                "\(value) should explicitly enable the flag"
            )
        }
    }

    func testMalformedAndUnknownValuesRemainOff() {
        let malformedValues = ["", "0", "false", "no", "off", "enabled", " true ", "2"]

        for value in malformedValues {
            let flags = FeatureFlags(
                environment: [FeatureFlag.hudEdgePlacement.environmentKey: value]
            )

            XCTAssertFalse(
                flags.isEnabled(.hudEdgePlacement),
                "\(value) must not enable the flag"
            )
        }

        let unknownOnly = FeatureFlags(
            environment: ["AUTOHAND_VOICE_UNKNOWN_FUTURE_FLAG": "true"]
        )
        XCTAssertFalse(unknownOnly.isEnabled(.hudEdgePlacement))
    }
}
