import Testing
import Foundation
@testable import Portly

struct NotificationActionTests {

    @Test func decodesProcessActionsWithIdentity() {
        let userInfo: [AnyHashable: Any] = ["pid": 42, "port": 3000, "startTime": 1234.5]
        let ref = ProcessRef(pid: 42, port: 3000, startTime: 1234.5)
        #expect(NotificationManager.action(for: "portly.action.kill", userInfo: userInfo) == .kill(ref))
        #expect(NotificationManager.action(for: "portly.action.forceKill", userInfo: userInfo) == .forceKill(ref))
        #expect(NotificationManager.action(for: "portly.action.restart", userInfo: userInfo) == .restart(ref))
        #expect(NotificationManager.action(for: "portly.action.open", userInfo: userInfo) == .openInBrowser(port: 3000))
    }

    @Test func relaunchNeedsACommandLine() {
        let complete: [AnyHashable: Any] = [
            "pid": 1, "port": 3000, "commandLine": "npm run dev", "workingDirectory": "/w", "logName": "web-3000",
        ]
        #expect(NotificationManager.action(for: "portly.action.relaunch", userInfo: complete)
                == .relaunch(commandLine: "npm run dev", workingDirectory: "/w", logName: "web-3000"))
        #expect(NotificationManager.action(for: "portly.action.relaunch", userInfo: ["pid": 1, "port": 3000]) == nil)
    }

    /// The default tap and dismissals aren't actions.
    @Test func ignoresUnknownIdentifiersAndMalformedPayloads() {
        #expect(NotificationManager.action(for: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: ["port": 1]) == nil)
        #expect(NotificationManager.action(for: "portly.action.kill", userInfo: ["port": 3000]) == nil)
    }
}
