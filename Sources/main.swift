import AppKit

@main
@MainActor
struct ZenmuxQuotaxApp {
    static func main() {
        AppLog.start()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
        AppLog.lifecycle.info("Application main started; version=\(version), build=\(build), macOS=\(ProcessInfo.processInfo.operatingSystemVersionString), architecture=\(ProcessInfo.processInfo.machineHardwareName)")
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
