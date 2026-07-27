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

    func testAudioHealthReportsNoSignalAfterGracePeriod() {
        var monitor = AudioHealthMonitor(noSignalDelay: 2)

        XCTAssertEqual(monitor.observe(level: 0, at: 10), .listening)
        XCTAssertEqual(monitor.observe(level: 0.001, at: 11.9), .listening)
        XCTAssertEqual(monitor.observe(level: 0.001, at: 12.1), .noSignal)
        XCTAssertEqual(monitor.observe(level: 0.02, at: 12.2), .healthy)
    }

    func testAudioHealthRequiresSustainedClipping() {
        var monitor = AudioHealthMonitor(clippingSampleCount: 3)

        XCTAssertEqual(monitor.observe(level: 0.99, at: 1), .healthy)
        XCTAssertEqual(monitor.observe(level: 0.99, at: 1.1), .healthy)
        XCTAssertEqual(monitor.observe(level: 0.99, at: 1.2), .clipping)
        XCTAssertEqual(monitor.observe(level: 0.2, at: 1.3), .healthy)
    }

    func testAudioHealthCanReportDisconnectedDevice() {
        var monitor = AudioHealthMonitor()

        monitor.disconnect()

        XCTAssertEqual(monitor.state, .disconnected)
    }

    func testAudioInputDeviceDiscoveryReturnsStableUniqueIDs() throws {
        let devices = try AudioInputDevices.available()

        XCTAssertEqual(Set(devices.map(\.id)).count, devices.count)
        XCTAssertTrue(devices.allSatisfy { !$0.id.isEmpty && !$0.name.isEmpty })
    }
}
