import AppKit
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    public var statusItem: NSStatusItem?
    public var statusView: StatusBarView?
    public var settingsWindow: NSWindow?
    public var isMenuOpen = false
    public let apiService = ZenmuxAPIService()
    public let settings = SettingsManager.shared

    private var menuHost: NSHostingView<MenuContentView>?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupApplicationMenu()
        setupStatusItem()
        apiService.startAutoRefresh(settings: settings)
        if settings.trimmedAPIKey.isEmpty {
            openSettings()
        } else {
            Task { await apiService.refresh(apiKey: settings.apiKey) }
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupApplicationMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "Quotax")
        appMenu.addItem(NSMenuItem(title: "Quit Quotax", action: #selector(quitApp), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: 104)
        let view = StatusBarView(frame: NSRect(x: 0, y: 0, width: 104, height: NSStatusBar.system.thickness))
        view.apiService = apiService
        item.button?.title = ""
        item.button?.image = nil
        item.button?.addSubview(view)
        view.translatesAutoresizingMaskIntoConstraints = false
        if let button = item.button {
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: button.trailingAnchor),
                view.topAnchor.constraint(equalTo: button.topAnchor),
                view.bottomAnchor.constraint(equalTo: button.bottomAnchor)
            ])
        }
        item.menu = buildMenu()
        statusItem = item
        statusView = view
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu(title: "Quotax")
        menu.delegate = self
        menu.autoenablesItems = false
        rebuildMenu(menu)
        return menu
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let view = MenuContentView(
            apiService: apiService,
            settings: settings,
            onRefresh: { [weak self] in
                guard let self else { return }
                Task { await self.apiService.refresh(apiKey: self.settings.apiKey) }
            },
            onOpenSettings: { [weak self] in self?.openSettings() },
            onOpenManagement: { [weak self] in self?.openManagementPortal() },
            onQuit: { [weak self] in self?.quitApp() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 360, height: 1)
        host.layoutSubtreeIfNeeded()
        host.frame = NSRect(x: 0, y: 0, width: 360, height: max(host.fittingSize.height, 180))
        let item = NSMenuItem()
        item.view = host
        menu.addItem(item)
        menuHost = host
    }

    public func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        rebuildMenu(menu)
        if !settings.trimmedAPIKey.isEmpty {
            Task { await apiService.refresh(apiKey: settings.apiKey) }
        }
    }

    public func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
    }

    @objc public func openSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let content = SettingsView(
            settings: settings,
            onSaveAPIKey: { [weak self] apiKey in
                guard let self else { return }
                self.settings.apiKey = apiKey
                Task { await self.apiService.refresh(apiKey: apiKey) }
            }
        )
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Quotax Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openManagementPortal() {
        if let url = URL(string: "https://zenmux.ai/platform/management") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc public func quitApp() {
        apiService.stopAutoRefresh()
        NSApp.terminate(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }
}
