import AVFoundation
import ApplicationServices
import Foundation

public struct SystemCheck: Codable, Equatable, Sendable {
    public let supported: Bool
    public let architecture: String
    public let macOSVersion: String
    public let microphonePermission: String
    public let accessibilityPermission: Bool
    public let remoteFallbackEnabled: Bool

    public init() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        architecture = "arm64"
        #else
        architecture = "unsupported"
        #endif
        macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        supported = version.majorVersion >= 14 && architecture == "arm64"
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: microphonePermission = "authorized"
        case .denied: microphonePermission = "denied"
        case .restricted: microphonePermission = "restricted"
        case .notDetermined: microphonePermission = "not-determined"
        @unknown default: microphonePermission = "unknown"
        }
        accessibilityPermission = AXIsProcessTrusted()
        remoteFallbackEnabled = false
    }

    public init(
        supported: Bool,
        architecture: String,
        macOSVersion: String,
        microphonePermission: String,
        accessibilityPermission: Bool
    ) {
        self.supported = supported
        self.architecture = architecture
        self.macOSVersion = macOSVersion
        self.microphonePermission = microphonePermission
        self.accessibilityPermission = accessibilityPermission
        remoteFallbackEnabled = false
    }
}
