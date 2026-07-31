import Foundation

public enum OnboardingRequirement: CaseIterable, Sendable {
    case microphone
    case accessibility
    case localModel
    case dictationTest
}

public struct OnboardingReadiness: Equatable, Sendable {
    public var microphoneAuthorized: Bool
    public var accessibilityAuthorized: Bool
    public var modelReady: Bool
    public var dictationTestPassed: Bool

    public init(
        microphoneAuthorized: Bool,
        accessibilityAuthorized: Bool,
        modelReady: Bool,
        dictationTestPassed: Bool
    ) {
        self.microphoneAuthorized = microphoneAuthorized
        self.accessibilityAuthorized = accessibilityAuthorized
        self.modelReady = modelReady
        self.dictationTestPassed = dictationTestPassed
    }

    public var canTestDictation: Bool {
        microphoneAuthorized && accessibilityAuthorized && modelReady
    }

    public var canComplete: Bool {
        canTestDictation && dictationTestPassed
    }

    public mutating func set(
        _ requirement: OnboardingRequirement,
        completed: Bool
    ) {
        switch requirement {
        case .microphone:
            microphoneAuthorized = completed
        case .accessibility:
            accessibilityAuthorized = completed
        case .localModel:
            modelReady = completed
        case .dictationTest:
            dictationTestPassed = completed
        }
    }
}
