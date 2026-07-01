import ServiceManagement

enum LaunchAtLoginManager {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            // Registration can fail if the app isn't in /Applications or isn't signed;
            // there's no user-facing recovery beyond leaving the toggle in its prior state.
        }
    }
}
