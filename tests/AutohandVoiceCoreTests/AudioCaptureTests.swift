import XCTest
@testable import AutohandVoiceCore

final class AudioCaptureTests: XCTestCase {
    func testResamplingIsBoundedAndPreservesEndpoints() {
        let input: [Float] = [0, 0.25, 0.5, 0.75, 1]
        let output = AudioCapture.resample(input, from: 5, to: 3)

        XCTAssertEqual(output.count, 3)
        XCTAssertEqual(output[0], 0, accuracy: 0.001)
        XCTAssertGreaterThan(output[2], output[1])
        XCTAssertLessThanOrEqual(output[2], 1)
    }
}
