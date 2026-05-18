import Foundation
import ServiceManagement

public struct LaunchAtLoginService {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    AppLog.settings.info("Launch at login registration requested")
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
                AppLog.settings.info("Launch at login unregistration requested")
            }
        } catch {
            AppLog.settings.error("Launch at login update failed: \(error.localizedDescription)")
            throw error
        }
    }
}
