import AppKit
import Combine
import SwiftUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public var statusItem: NSStatusItem?
    public var statusView: StatusBarView?
    public var settingsWindow: NSWindow?
    public var menuPanel: NSPanel?
    public var isMenuOpen = false
    public let apiService = ZenmuxAPIService()
    public let settings = SettingsManager.shared

    private let menuWidth: CGFloat = 380
    private var menuHost: NSHostingView<MenuContentView>?
    private var appearanceCancellable: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyAppearanceMode(settings.appearanceMode)
        appearanceCancellable = settings.$appearanceMode.sink { [weak self] mode in
            self?.applyAppearanceMode(mode)
        }
        settings.refreshLaunchAtLoginStatus()
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

    private func applyAppearanceMode(_ mode: AppearanceMode) {
        let appearance: NSAppearance?
        switch mode {
        case .system:
            appearance = nil
        case .light:
            appearance = NSAppearance(named: .aqua)
        case .dark:
            appearance = NSAppearance(named: .darkAqua)
        }

        NSApp.appearance = appearance
        settingsWindow?.appearance = appearance
        menuPanel?.appearance = appearance
        menuHost?.appearance = appearance
        menuHost?.needsLayout = true
        statusItem?.button?.appearance = appearance
        statusView?.appearance = appearance
        statusView?.needsDisplay = true
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
        let statusWidth: CGFloat = 72
        let item = NSStatusBar.system.statusItem(withLength: statusWidth)
        let view = StatusBarView(frame: NSRect(x: 0, y: 0, width: statusWidth, height: NSStatusBar.system.thickness))
        view.apiService = apiService
        view.settings = settings
        item.button?.title = ""
        item.button?.image = nil
        item.button?.target = self
        item.button?.action = #selector(toggleMenuPanel)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
        statusItem = item
        statusView = view
    }

    @objc private func toggleMenuPanel() {
        if isMenuOpen {
            closeMenuPanel()
        } else {
            openMenuPanel()
        }
    }

    private func openMenuPanel() {
        guard !isMenuOpen, menuPanel == nil else { return }
        guard let button = statusItem?.button else { return }
        let host = makeMenuHost()
        let fittingSize = host.fittingSize
        let panelHeight = max(fittingSize.height, 180)
        host.frame = NSRect(x: 0, y: 0, width: menuWidth, height: panelHeight)

        let panel = NSPanel(
            contentRect: host.frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.appearance = NSApp.appearance
        panel.contentView = host
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false

        if let screenFrame = button.window?.screen?.visibleFrame, let buttonFrame = button.window?.convertToScreen(button.frame) {
            let originX = min(max(buttonFrame.midX - menuWidth / 2, screenFrame.minX + 8), screenFrame.maxX - menuWidth - 8)
            let originY = buttonFrame.minY - panelHeight - 6
            panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        } else if let screenFrame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: screenFrame.midX - menuWidth / 2, y: screenFrame.maxY - panelHeight - 32))
        }
        host.layoutSubtreeIfNeeded()

        menuPanel = panel
        isMenuOpen = true
        installMenuPanelEventMonitors()
        panel.orderFrontRegardless()
    }

    private func closeMenuPanel() {
        menuPanel?.orderOut(nil)
        menuPanel = nil
        menuHost = nil
        isMenuOpen = false
        removeMenuPanelEventMonitors()
    }

    private func makeMenuHost() -> NSHostingView<MenuContentView> {
        let view = MenuContentView(
            apiService: apiService,
            settings: settings,
            onRefresh: { [weak self] in
                guard let self else { return }
                Task { await self.apiService.refresh(apiKey: self.settings.apiKey) }
            },
            onOpenSettings: { [weak self] in
                self?.closeMenuPanel()
                self?.openSettings()
            },
            onOpenManagement: { [weak self] in self?.openManagementPortal() },
            onQuit: { [weak self] in self?.quitApp() }
        )
        let host = NSHostingView(rootView: view)
        host.appearance = NSApp.appearance
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.frame = NSRect(x: 0, y: 0, width: menuWidth, height: 1)
        host.layoutSubtreeIfNeeded()
        menuHost = host
        return host
    }

    private func installMenuPanelEventMonitors() {
        removeMenuPanelEventMonitors()
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 {
                self.closeMenuPanel()
                return nil
            }
            if let panel = self.menuPanel, event.window === panel {
                return event
            }
            if event.window === self.statusItem?.button?.window {
                return event
            }
            self.closeMenuPanel()
            return event
        }
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeMenuPanel() }
        }
    }

    private func removeMenuPanelEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
    }

    @objc public func openSettings() {
        if let settingsWindow {
            settings.refreshLaunchAtLoginStatus()
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        settings.refreshLaunchAtLoginStatus()
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
        window.appearance = NSApp.appearance
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
        closeMenuPanel()
        settingsWindow?.close()
        apiService.stopAutoRefresh()
        NSApp.terminate(nil)
    }

    public func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === settingsWindow {
            settingsWindow = nil
        }
    }
}
