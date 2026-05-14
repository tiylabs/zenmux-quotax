import AppKit

@MainActor
func zenmuxAppIcon() -> NSImage {
    if let image = Bundle.main.image(forResource: "AppIcon") {
        return image
    }
    if let resourceURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
       let image = NSImage(contentsOf: resourceURL) {
        return image
    }
    return NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
}
