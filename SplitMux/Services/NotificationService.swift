import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Send system notification + update dock badge
    /// When tabIsActive=true AND app is focused, suppresses the banner (only plays sound)
    func send(title: String, body: String, tabIsActive: Bool = false) {
        // Check if notifications are enabled
        guard SettingsManager.shared.showNotificationBanners else { return }

        // If the tab is active and app is focused, skip notification entirely
        if tabIsActive && NSApp.isActive {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)

        if !NSApp.isActive {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }

    /// Update dock badge with total unread count
    func updateDockBadge(count: Int) {
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // Show banner even when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
