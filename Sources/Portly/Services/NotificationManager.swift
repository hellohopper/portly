import PortlyCore
import UserNotifications

enum NotificationManager {

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyNewPort(_ info: PortInfo) {
        notify(title: "New port listening", body: "\(describe(info)) started on port \(info.port)")
    }

    static func notifyPinnedPortDied(_ info: PortInfo) {
        notify(title: "Pinned port stopped", body: "\(describe(info)) on port \(info.port) is no longer listening")
    }

    static func notifyHealthRegression(_ info: PortInfo, statusCode: Int) {
        notify(
            title: "Pinned port is failing",
            body: "\(describe(info)) on port \(info.port) is now returning HTTP \(statusCode)"
        )
    }

    static func notifyIdlePort(_ info: PortInfo) {
        notify(
            title: "Idle port",
            body: "\(describe(info)) on port \(info.port) has seen no network activity in 30 minutes"
        )
    }

    static func notifyIdlePortKilled(_ info: PortInfo) {
        notify(
            title: "Idle port killed",
            body: "\(describe(info)) on port \(info.port) was idle for 30 minutes and has been stopped"
        )
    }

    private static func describe(_ info: PortInfo) -> String {
        info.frameworkLabel ?? info.processName
    }

    private static func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
