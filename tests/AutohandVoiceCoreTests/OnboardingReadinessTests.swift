import XCTest
@testable import AutohandVoiceCore

final class OnboardingReadinessTests: XCTestCase {
    func testEveryRequiredCapabilityMustPassBeforeCompletion() {
        let complete = OnboardingReadiness(
            microphoneAuthorized: true,
            accessibilityAuthorized: true,
            modelReady: true,
            dictationTestPassed: true
        )

        XCTAssertTrue(complete.canComplete)

        for missing in OnboardingRequirement.allCases {
            var readiness = complete
            readiness.set(missing, completed: false)
            XCTAssertFalse(
                readiness.canComplete,
                "\(missing) must gate onboarding completion"
            )
        }
    }

    func testSetupCanAdvanceBeforeDictationTest() {
        let readiness = OnboardingReadiness(
            microphoneAuthorized: true,
            accessibilityAuthorized: true,
            modelReady: true,
            dictationTestPassed: false
        )

        XCTAssertTrue(readiness.canTestDictation)
        XCTAssertFalse(readiness.canComplete)
    }
}
