import Foundation
import Combine

@MainActor
public final class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    private enum Keys {
        static let apiKey = "api_key"
        static let refreshInterval = "refresh_interval"
        static let alwaysRefresh = "alwaysRefresh"
    }

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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        let storedInterval = defaults.double(forKey: Keys.refreshInterval)
        self.refreshInterval = storedInterval > 0 ? storedInterval : 300
        self.alwaysRefresh = defaults.object(forKey: Keys.alwaysRefresh) as? Bool ?? true
    }

    public var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
