import Foundation
import Combine
import ServiceManagement

public enum StatusBarQuotaDisplayMode: String, CaseIterable, Identifiable {
    case used
    case left

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .used: return "Used percentage"
        case .left: return "Left percentage"
        }
    }
}

public enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

public enum StatusBarDataColorMode: String, CaseIterable, Identifiable {
    case white
    case black

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .white: return "White"
        case .black: return "Black"
        }
    }
}

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    private enum Keys {
        static let apiKey = "api_key"
        static let refreshInterval = "refresh_interval"
        static let alwaysRefresh = "alwaysRefresh"
        static let statusBarQuotaDisplayMode = "statusBarQuotaDisplayMode"
        static let statusBarDataColorMode = "statusBarDataColorMode"
        static let appearanceMode = "appearanceMode"
        static let timeZoneIdentifier = "timeZoneIdentifier"
        static let launchAtLogin = "launchAtLogin"
    }

    public static let preferredTimeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

    private let defaults: UserDefaults

    @Published public var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    @Published public var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published public var alwaysRefresh: Bool {
        didSet { defaults.set(alwaysRefresh, forKey: Keys.alwaysRefresh) }
    }

    @Published public var statusBarQuotaDisplayMode: StatusBarQuotaDisplayMode {
        didSet { defaults.set(statusBarQuotaDisplayMode.rawValue, forKey: Keys.statusBarQuotaDisplayMode) }
    }

    @Published public var statusBarDataColorMode: StatusBarDataColorMode {
        didSet { defaults.set(statusBarDataColorMode.rawValue, forKey: Keys.statusBarDataColorMode) }
    }

    @Published public var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }

    @Published public var timeZoneIdentifier: String {
        didSet { defaults.set(timeZoneIdentifier, forKey: Keys.timeZoneIdentifier) }
    }

    @Published public var launchAtLogin: Bool {
        didSet {
            guard !isApplyingLaunchAtLoginRollback else { return }
            setLaunchAtLogin(launchAtLogin)
        }
    }

    @Published public private(set) var launchAtLoginError: String?
    public let hasStoredLaunchAtLoginPreference: Bool
    private var isApplyingLaunchAtLoginRollback = false

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasStoredLaunchAtLoginPreference = defaults.object(forKey: Keys.launchAtLogin) != nil
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        let storedInterval = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = storedInterval > 0 ? storedInterval : 300
        self.alwaysRefresh = defaults.object(forKey: Keys.alwaysRefresh) as? Bool ?? true
        let storedDisplayMode = defaults.string(forKey: Keys.statusBarQuotaDisplayMode) ?? StatusBarQuotaDisplayMode.used.rawValue
        self.statusBarQuotaDisplayMode = StatusBarQuotaDisplayMode(rawValue: storedDisplayMode) ?? .used
        let storedStatusBarDataColorMode = defaults.string(forKey: Keys.statusBarDataColorMode) ?? StatusBarDataColorMode.white.rawValue
        self.statusBarDataColorMode = StatusBarDataColorMode(rawValue: storedStatusBarDataColorMode) ?? .white
        let storedAppearanceMode = defaults.string(forKey: Keys.appearanceMode) ?? AppearanceMode.system.rawValue
        self.appearanceMode = AppearanceMode(rawValue: storedAppearanceMode) ?? .system
        let storedTimeZone = defaults.string(forKey: Keys.timeZoneIdentifier) ?? TimeZone.current.identifier
        self.timeZoneIdentifier = TimeZone(identifier: storedTimeZone)?.identifier ?? TimeZone.current.identifier
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.launchAtLoginError = nil
    }

    public var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .current
    }

    public func syncLaunchAtLoginSetting() {
        refreshLaunchAtLoginStatus()
    }

    public func refreshLaunchAtLoginStatus() {
        applyLaunchAtLoginStatus(SMAppService.mainApp.status == .enabled, clearError: true)
    }

    private func applyLaunchAtLoginStatus(_ systemEnabled: Bool, clearError: Bool) {
        isApplyingLaunchAtLoginRollback = true
        launchAtLogin = systemEnabled
        isApplyingLaunchAtLoginRollback = false
        defaults.set(systemEnabled, forKey: Keys.launchAtLogin)
        if clearError {
            launchAtLoginError = nil
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status != .notRegistered {
                try SMAppService.mainApp.unregister()
            }
            applyLaunchAtLoginStatus(SMAppService.mainApp.status == .enabled, clearError: true)
        } catch {
            launchAtLoginError = error.localizedDescription
            applyLaunchAtLoginStatus(SMAppService.mainApp.status == .enabled, clearError: false)
        }
    }
}