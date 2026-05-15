import Foundation

@MainActor
public final class ZenmuxAPIService: ObservableObject {
    @Published public private(set) var subscriptionData: ZenmuxSubscriptionData?
    @Published public private(set) var lastError: ZenmuxAPIError?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var isRefreshing: Bool = false

    private let apiClient: ZenmuxAPIClient
    private var refreshTask: Task<Void, Never>?
    private var inFlightRefreshTask: Task<ZenmuxSubscriptionData, Error>?
    private var requestSequence: UInt64 = 0
    private var activeRequestID: UInt64?

    private struct AutoRefreshSnapshot {
        let alwaysRefresh: Bool
        let apiKey: String
        let trimmedKeyIsEmpty: Bool
        let interval: TimeInterval
    }

    public init(apiClient: ZenmuxAPIClient = ZenmuxAPIClient()) {
        self.apiClient = apiClient
    }

    deinit {
        refreshTask?.cancel()
        inFlightRefreshTask?.cancel()
    }

    public func refresh(apiKey: String) async {
        inFlightRefreshTask?.cancel()
        requestSequence &+= 1
        let requestID = requestSequence
        activeRequestID = requestID

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            isRefreshing = false
            inFlightRefreshTask = nil
            lastError = ZenmuxAPIError(.noAPIKey, diagnosticMessage: "Attempted subscription refresh without an API key")
            AppLog.refresh.warning("Refresh \(requestID, privacy: .public) skipped because API key is empty")
            return
        }
        guard URL(string: AppConstants.API.subscriptionDetailURLString) != nil else {
            isRefreshing = false
            inFlightRefreshTask = nil
            lastError = ZenmuxAPIError(.invalidURL, diagnosticMessage: "Invalid URL string: \(AppConstants.API.subscriptionDetailURLString)")
            AppLog.refresh.error("Refresh \(requestID, privacy: .public) skipped because API URL is invalid")
            return
        }

        isRefreshing = true
        lastError = nil
        AppLog.refresh.info("Refresh \(requestID, privacy: .public) started")

        let task = Task { [apiClient] in
            try await apiClient.fetchSubscription(apiKey: key)
        }
        inFlightRefreshTask = task

        do {
            let data = try await task.value
            guard activeRequestID == requestID else {
                AppLog.refresh.debug("Ignoring stale refresh \(requestID, privacy: .public) success")
                return
            }
            subscriptionData = data
            lastError = nil
            lastUpdated = Date()
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.info("Refresh \(requestID, privacy: .public) succeeded")
        } catch is CancellationError {
            guard activeRequestID == requestID else { return }
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.debug("Refresh \(requestID, privacy: .public) cancelled")
        } catch let apiError as ZenmuxAPIError {
            guard activeRequestID == requestID else {
                AppLog.refresh.debug("Ignoring stale refresh \(requestID, privacy: .public) failure")
                return
            }
            lastError = apiError
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.error("Refresh \(requestID, privacy: .public) failed: \(apiError.type.rawValue, privacy: .public) status \(apiError.statusCode ?? -1, privacy: .public)")
        } catch {
            guard activeRequestID == requestID else {
                AppLog.refresh.debug("Ignoring stale refresh \(requestID, privacy: .public) unexpected failure")
                return
            }
            lastError = ZenmuxAPIError(.networkError, message: error.localizedDescription, diagnosticMessage: String(describing: error))
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.error("Refresh \(requestID, privacy: .public) failed unexpectedly: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func startAutoRefresh(settings: SettingsManager) {
        stopAutoRefresh()
        AppLog.refresh.info("Auto refresh loop starting")
        refreshTask = Task { [weak self, weak settings] in
            while !Task.isCancelled {
                guard let self, let settings else { return }
                let snapshot = await MainActor.run { () -> AutoRefreshSnapshot in
                    let normalizedInterval = AppConstants.Refresh.normalizedInterval(settings.refreshInterval)
                    if normalizedInterval != settings.refreshInterval {
                        AppLog.settings.warning("Refresh interval \(settings.refreshInterval, privacy: .public)s is below minimum or invalid; using \(normalizedInterval, privacy: .public)s")
                    }
                    self.isPaused = !settings.alwaysRefresh
                    return AutoRefreshSnapshot(
                        alwaysRefresh: settings.alwaysRefresh,
                        apiKey: settings.apiKey,
                        trimmedKeyIsEmpty: settings.trimmedAPIKey.isEmpty,
                        interval: normalizedInterval
                    )
                }

                if snapshot.alwaysRefresh, !snapshot.trimmedKeyIsEmpty {
                    await self.refresh(apiKey: snapshot.apiKey)
                } else {
                    AppLog.refresh.debug("Auto refresh skipped; enabled=\(snapshot.alwaysRefresh, privacy: .public), hasKey=\(!snapshot.trimmedKeyIsEmpty, privacy: .public)")
                }

                AppLog.refresh.debug("Auto refresh sleeping for \(snapshot.interval, privacy: .public)s")
                do {
                    try await Task.sleep(nanoseconds: Self.sleepNanoseconds(for: snapshot.interval))
                } catch is CancellationError {
                    AppLog.refresh.info("Auto refresh loop cancelled")
                    return
                } catch {
                    AppLog.refresh.error("Auto refresh sleep failed: \(error.localizedDescription, privacy: .public)")
                    return
                }
            }
        }
    }

    public func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        inFlightRefreshTask?.cancel()
        inFlightRefreshTask = nil
        if isRefreshing {
            isRefreshing = false
        }
        activeRequestID = nil
        AppLog.refresh.info("Auto refresh stopped")
    }

    public func pause() {
        isPaused = true
        AppLog.refresh.debug("Refresh paused")
    }

    public func resume() {
        isPaused = false
        AppLog.refresh.debug("Refresh resumed")
    }

    private static func sleepNanoseconds(for interval: TimeInterval) -> UInt64 {
        let seconds = AppConstants.Refresh.normalizedInterval(interval)
        let nanoseconds = seconds * 1_000_000_000
        guard nanoseconds.isFinite, nanoseconds > 0 else {
            return UInt64(AppConstants.Refresh.minimumInterval * 1_000_000_000)
        }
        if nanoseconds >= Double(UInt64.max) {
            return UInt64.max
        }
        return UInt64(nanoseconds)
    }
}
