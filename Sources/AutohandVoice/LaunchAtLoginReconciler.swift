import AutohandVoiceCore
import OSLog
import ServiceManagement

/// Re-applies the person's "Launch at Login" choice at every launch, since
/// replacing the app with an update can drop the system login item.
@MainActor
enum LaunchAtLoginReconciler {
    private static let logger = Logger(
        subsystem: Brand.bundleIdentifier,
        category: "launch-at-login"
    )

    static func reconcile(session: VoiceSession) {
        let service = SMAppService.mainApp
        let status: LaunchAtLoginReconciliation.SystemStatus
        switch service.status {
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        case .notFound: status = .notFound
        case .notRegistered: status = .notRegistered
        @unknown default: return
        }
        switch LaunchAtLoginReconciliation.action(
            wanted: session.preferences.launchAtLogin,
            status: status
        ) {
        case .none:
            break
        case .register:
            do {
                try service.register()
                logger.notice("Launch at login registered again after an update")
            } catch {
                logger.error(
                    "Launch at login could not be registered: \(error.localizedDescription)"
                )
            }
        case .askForApproval:
            logger.notice(
                "Launch at login is turned off for Autohand Voice in System Settings"
            )
        case .adoptEnabled:
            session.setLaunchAtLogin(true)
        }
    }
}
