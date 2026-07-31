import Foundation

public enum FunctionKeyMonitoringAuthorization {
    public static func isSufficient(
        inputMonitoringGranted: Bool,
        accessibilityGranted: Bool
    ) -> Bool {
        inputMonitoringGranted || accessibilityGranted
    }
}
