import XCTest
@testable import AutohandVoiceCore

final class SystemCheckTests: XCTestCase {
    func testAppleSiliconAndIntelAreSupportedOnMacOS14() {
        XCTAssertTrue(SystemCheck.isSupported(architecture: "arm64", macOSMajorVersion: 14))
        XCTAssertTrue(SystemCheck.isSupported(architecture: "x86_64", macOSMajorVersion: 15))
    }

    func testOlderMacOSAndUnknownArchitecturesAreUnsupported() {
        XCTAssertFalse(SystemCheck.isSupported(architecture: "x86_64", macOSMajorVersion: 13))
        XCTAssertFalse(SystemCheck.isSupported(architecture: "unsupported", macOSMajorVersion: 15))
    }

    func testCurrentArchitectureIsReported() {
        #if arch(arm64)
        XCTAssertEqual(SystemCheck().architecture, "arm64")
        #elseif arch(x86_64)
        XCTAssertEqual(SystemCheck().architecture, "x86_64")
        #endif
    }
}
