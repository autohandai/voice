import AutohandVoiceCore
import Foundation
import UserNotifications

@MainActor
final class SystemNotificationBridge:
    NSObject,
    UNUserNotificationCenterDelegate
{
    var onAction:
        ((String, VoiceNotificationAction, String?) -> Void)?
    var onOpen: ((String?) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        registerCategories()
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(
                options: [.alert, .sound]
            )
        } catch {
            return false
        }
    }

    func deliver(_ notification: SystemVoiceNotification) {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = notification.category.rawValue
        if let deepLink = notification.deepLink {
            content.userInfo["deep_link"] = deepLink
        }
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let deepLink = response.notification.request.content
            .userInfo["deep_link"] as? String
        if response.actionIdentifier
            == UNNotificationDefaultActionIdentifier
        {
            Task { @MainActor [weak self] in
                self?.onOpen?(deepLink)
                completionHandler()
            }
            return
        }
        guard let action = VoiceNotificationAction(
            rawValue: response.actionIdentifier
        ) else {
            completionHandler()
            return
        }
        Task { @MainActor [weak self] in
            self?.onAction?(identifier, action, deepLink)
            completionHandler()
        }
    }

    private func registerCategories() {
        let copy = UNNotificationAction(
            identifier: VoiceNotificationAction.copyLast.rawValue,
            title: "Copy Last",
            options: []
        )
        let recover = UNNotificationAction(
            identifier: VoiceNotificationAction.recover.rawValue,
            title: "Recover",
            options: [.foreground]
        )
        let settings = UNNotificationAction(
            identifier: VoiceNotificationAction.openSettings.rawValue,
            title: "Open Settings",
            options: [.foreground]
        )
        let history = UNNotificationAction(
            identifier: VoiceNotificationAction.openHistory.rawValue,
            title: "Open History",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: VoiceNotificationCategory.completion.rawValue,
                actions: [copy, history],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: VoiceNotificationCategory.recovery.rawValue,
                actions: [recover],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: VoiceNotificationCategory.failures.rawValue,
                actions: [settings],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: VoiceNotificationCategory.permissions.rawValue,
                actions: [settings],
                intentIdentifiers: []
            ),
        ])
    }
}
