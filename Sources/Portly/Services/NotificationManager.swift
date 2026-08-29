import PortlyCore
import UserNotifications

enum NotificationManager {

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyNewPort(_ info: PortInfo) {
        let content = UNMutableNotificationContent()
        content.title = "New port listening"
        content.body = "\(info.frameworkLabel ?? info.processName) started on port \(info.port)"
        content.sound = .default
        post(content)
    }

    static func notifyPinnedPortDied(_ info: PortInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Pinned port stopped"
        content.body = "\(info.frameworkLabel ?? info.processName) on port \(info.port) is no longer listening"
        content.sound = .default
        post(content)
    }

    static func notifyHealthRegression(_ info: PortInfo, statusCode: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Pinned port is failing"
        content.body = "\(info.frameworkLabel ?? info.processName) on port \(info.port) is now returning HTTP \(statusCode)"
        content.sound = .default
        post(content)
    }

    static func notifyIdlePort(_ info: PortInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Idle port"
        content.body = "\(info.frameworkLabel ?? info.processName) on port \(info.port) has seen no network activity in 30 minutes"
        content.sound = .default
        post(content)
    }

    static func notifyIdlePortKilled(_ info: PortInfo) {
        let content = UNMutableNotificationContent()
        content.title = "Idle port killed"
        content.body = "\(info.frameworkLabel ?? info.processName) on port \(info.port) was idle for 30 minutes and has been stopped"
        content.sound = .default
        post(content)
    }

    private static func post(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
