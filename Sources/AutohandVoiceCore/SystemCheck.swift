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
        #elseif arch(x86_64)
        architecture = "x86_64"
        #else
        architecture = "unsupported"
        #endif
        macOSVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        supported = Self.isSupported(
            architecture: architecture,
            macOSMajorVersion: version.majorVersion
        )
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

    /// Apple Silicon runs CoreML on the Neural Engine; Intel Macs run the
    /// same local CoreML model on the CPU and GPU.
    public static func isSupported(
        architecture: String,
        macOSMajorVersion: Int
    ) -> Bool {
        macOSMajorVersion >= 14
            && (architecture == "arm64" || architecture == "x86_64")
    }
}
