import AppKit

@main
@MainActor
struct zenmux_monitorApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        _ = delegate
    }
}
