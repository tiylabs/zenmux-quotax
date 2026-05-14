import Combine
import Foundation

@MainActor
public final class ZenmuxAPIService: ObservableObject {
    public let baseURL = "https://zenmux.ai/api/v1/management/subscription/detail"

    @Published public private(set) var subscriptionData: ZenmuxSubscriptionData?
    @Published public private(set) var lastError: ZenmuxAPIError?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var isRefreshing: Bool = false

    private var refreshTask: Task<Void, Never>?
    private var inFlightRefreshTask: Task<Void, Never>?
    private var cancellables: Set<AnyCancellable> = []

    public init() {}

    deinit {
        refreshTask?.cancel()
        inFlightRefreshTask?.cancel()
    }

    public func refresh(apiKey: String) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            lastError = ZenmuxAPIError(.noAPIKey)
            return
        }
        guard let url = URL(string: baseURL) else {
            lastError = ZenmuxAPIError(.invalidURL)
            return
        }

        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = ZenmuxAPIError(.networkError, message: "Invalid HTTP response")
                return
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                lastError = ZenmuxAPIError(.httpError, statusCode: httpResponse.statusCode, message: body)
                return
            }

            let decoder = JSONDecoder()
            let decodedResponse = try decoder.decode(ZenmuxSubscriptionResponse.self, from: data)
            if decodedResponse.success == false {
                lastError = ZenmuxAPIError(.apiError, statusCode: decodedResponse.statusCode, message: decodedResponse.message)
                return
            }
            subscriptionData = decodedResponse.data
            lastError = nil
            lastUpdated = Date()
        } catch let decodingError as DecodingError {
            lastError = ZenmuxAPIError(.decodeError, message: String(describing: decodingError))
        } catch {
            lastError = ZenmuxAPIError(.networkError, message: error.localizedDescription)
        }
    }

    public func startAutoRefresh(settings: SettingsManager) {
        stopAutoRefresh()
        refreshTask = Task { [weak self, weak settings] in
            while !Task.isCancelled {
                guard let self, let settings else { return }
                await MainActor.run {
                    self.isPaused = !settings.alwaysRefresh
                    if settings.alwaysRefresh, !settings.trimmedAPIKey.isEmpty {
                        self.inFlightRefreshTask?.cancel()
                        self.inFlightRefreshTask = Task { await self.refresh(apiKey: settings.apiKey) }
                    }
                }
                let interval = await MainActor.run { max(settings.refreshInterval, 30) }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
    }

    public func pause() {
        isPaused = true
    }

    public func resume() {
        isPaused = false
    }
}
