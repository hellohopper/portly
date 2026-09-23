import PortlyCore
import UserNotifications

/// One specific process: a pid alone could be reused by the time someone clicks a
/// notification's button minutes later, so the exact start time comes along too.
struct ProcessRef: Equatable {
    let pid: Int32
    let port: Int
    let startTime: TimeInterval?
}

/// What a notification's action button asks for.
enum NotificationAction: Equatable {
    case openInBrowser(port: Int)
    case kill(ProcessRef)
    case forceKill(ProcessRef)
    case restart(ProcessRef)
    case relaunch(commandLine: String, workingDirectory: String?, logName: String)
}

enum NotificationManager {

    enum Category: String, CaseIterable {
        case newPort = "portly.newPort"
        case pinnedDied = "portly.pinnedDied"
        case healthRegression = "portly.healthRegression"
        case idlePort = "portly.idlePort"
        case killStalled = "portly.killStalled"
    }

    enum ActionID: String {
        case open = "portly.action.open"
        case kill = "portly.action.kill"
        case forceKill = "portly.action.forceKill"
        case restart = "portly.action.restart"
        case relaunch = "portly.action.relaunch"
    }

    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories(Set(Category.allCases.map(category)))
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func category(_ category: Category) -> UNNotificationCategory {
        func action(_ id: ActionID, _ title: String, destructive: Bool = false) -> UNNotificationAction {
            UNNotificationAction(identifier: id.rawValue, title: title, options: destructive ? [.destructive] : [])
        }
        let actions: [UNNotificationAction]
        switch category {
        case .newPort: actions = [action(.open, "Open in Browser")]
        case .pinnedDied: actions = [action(.relaunch, "Relaunch")]
        case .healthRegression: actions = [action(.restart, "Restart"), action(.open, "Open in Browser")]
        case .idlePort: actions = [action(.kill, "Kill", destructive: true)]
        case .killStalled: actions = [action(.forceKill, "Force Kill", destructive: true)]
        }
        return UNNotificationCategory(identifier: category.rawValue, actions: actions, intentIdentifiers: [])
    }

    static func notifyNewPort(_ info: PortInfo) {
        notify(
            title: "New port listening",
            body: "\(describe(info)) started on port \(info.port)",
            category: info.isTCP ? .newPort : nil,
            userInfo: processUserInfo(info)
        )
    }

    static func notifyPinnedPortDied(_ info: PortInfo) {
        // Relaunch needs the command line; without it the button would do nothing.
        let canRelaunch = info.commandLine?.isEmpty == false
        var userInfo = processUserInfo(info)
        if canRelaunch {
            userInfo["commandLine"] = info.commandLine
            userInfo["workingDirectory"] = info.workingDirectory
            userInfo["logName"] = launchLogName(project: info.projectName, process: info.processName, port: info.port)
        }
        notify(
            title: "Pinned port stopped",
            body: "\(describe(info)) on port \(info.port) is no longer listening",
            category: canRelaunch ? .pinnedDied : nil,
            userInfo: userInfo
        )
    }

    static func notifyHealthRegression(_ info: PortInfo, statusCode: Int) {
        notify(
            title: "Pinned port is failing",
            body: "\(describe(info)) on port \(info.port) is now returning HTTP \(statusCode)",
            category: .healthRegression,
            userInfo: processUserInfo(info)
        )
    }

    static func notifyIdlePort(_ info: PortInfo) {
        notify(
            title: "Idle port",
            body: "\(describe(info)) on port \(info.port) has seen no network activity in 30 minutes",
            category: .idlePort,
            userInfo: processUserInfo(info)
        )
    }

    static func notifyIdlePortKilled(_ info: PortInfo) {
        notify(
            title: "Idle port killed",
            body: "\(describe(info)) on port \(info.port) was idle for 30 minutes and has been stopped"
        )
    }

    static func notifyKillStalled(_ info: PortInfo) {
        notify(
            title: "Process didn't exit",
            body: "\(describe(info)) on port \(info.port) is still running 5 seconds after SIGTERM",
            category: .killStalled,
            userInfo: processUserInfo(info)
        )
    }

    static func notifyLaunchFailed(commandLine: String) {
        let executable = ProcessLauncher.argv(from: commandLine).first ?? commandLine
        notify(
            title: "Couldn't start the server",
            body: "\(executable) wasn't found on your PATH, or failed to launch: \(commandLine)"
        )
    }

    static func notifyRestartBlocked(_ info: PortInfo) {
        notify(
            title: "Restart cancelled",
            body: "\(describe(info)) on port \(info.port) didn't exit, so it wasn't relaunched"
        )
    }

    /// Log file name for a process Portly starts, so restarts of the same server
    /// keep appending to one file.
    static func launchLogName(project: String?, process: String, port: Int) -> String {
        LaunchLog.name(project ?? process, String(port))
    }

    // MARK: - Action decoding

    private static func processUserInfo(_ info: PortInfo) -> [String: Any] {
        var userInfo: [String: Any] = ["pid": Int(info.pid), "port": info.port]
        if let startTime = ProcessTerminator.startTime(of: info.pid) {
            userInfo["startTime"] = startTime
        }
        return userInfo
    }

    /// Maps a tapped action button back to what it should do. Nil for the default
    /// tap (which just brings the notification's app forward) or malformed payloads.
    static func action(for identifier: String, userInfo: [AnyHashable: Any]) -> NotificationAction? {
        guard let actionID = ActionID(rawValue: identifier) else { return nil }
        let port = userInfo["port"] as? Int
        let ref: ProcessRef? = {
            guard let pid = userInfo["pid"] as? Int, let port else { return nil }
            return ProcessRef(pid: Int32(pid), port: port, startTime: userInfo["startTime"] as? TimeInterval)
        }()

        switch actionID {
        case .open:
            return port.map { .openInBrowser(port: $0) }
        case .kill:
            return ref.map { .kill($0) }
        case .forceKill:
            return ref.map { .forceKill($0) }
        case .restart:
            return ref.map { .restart($0) }
        case .relaunch:
            guard let commandLine = userInfo["commandLine"] as? String, !commandLine.isEmpty,
                  let logName = userInfo["logName"] as? String else { return nil }
            return .relaunch(
                commandLine: commandLine,
                workingDirectory: userInfo["workingDirectory"] as? String,
                logName: logName
            )
        }
    }

    private static func describe(_ info: PortInfo) -> String {
        info.frameworkLabel ?? info.processName
    }

    private static func notify(
        title: String,
        body: String,
        category: Category? = nil,
        userInfo: [String: Any] = [:]
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let category {
            content.categoryIdentifier = category.rawValue
        }
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Receives action-button taps. Kept separate from `NotificationManager` (an enum of
/// static helpers) because the notification center needs an object delegate.
final class NotificationActionHandler: NSObject, UNUserNotificationCenterDelegate {
    private let onAction: @MainActor (NotificationAction) -> Void

    init(onAction: @escaping @MainActor (NotificationAction) -> Void) {
        self.onAction = onAction
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = NotificationManager.action(
            for: response.actionIdentifier,
            userInfo: response.notification.request.content.userInfo
        )
        if let action {
            let onAction = self.onAction
            Task { @MainActor in onAction(action) }
        }
        completionHandler()
    }

    /// Portly is often the active app (its panel is open) when something happens;
    /// without this, those notifications were silently swallowed.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
