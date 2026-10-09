import Foundation

@MainActor
public final class ZenmuxAPIService: ObservableObject {
    @Published public private(set) var subscriptionData: ZenmuxSubscriptionData?
    @Published public private(set) var statisticsTokens: ZenmuxStatisticsData?
    @Published public private(set) var statisticsCost: ZenmuxStatisticsData?
    @Published public private(set) var statisticsTokensError: ZenmuxAPIError?
    @Published public private(set) var statisticsCostError: ZenmuxAPIError?
    @Published public private(set) var lastError: ZenmuxAPIError?
    @Published public private(set) var lastUpdated: Date?
    @Published public private(set) var isPaused: Bool = false
    @Published public private(set) var isRefreshing: Bool = false

    private var apiClient: ZenmuxAPIClient
    private var refreshTask: Task<Void, Never>?
    private var inFlightRefreshTask: Task<RefreshResult, Error>?
    private var requestSequence: UInt64 = 0
    private var activeRequestID: UInt64?

    private static let statisticsDayCount = 30

    private struct AutoRefreshSnapshot {
        let alwaysRefresh: Bool
        let apiKey: String
        let apiBaseURLString: String
        let trimmedKeyIsEmpty: Bool
        let interval: TimeInterval
    }

    private struct RefreshResult {
        let subscriptionData: ZenmuxSubscriptionData
        let statisticsTokens: ZenmuxStatisticsData?
        let statisticsCost: ZenmuxStatisticsData?
        let statisticsTokensError: ZenmuxAPIError?
        let statisticsCostError: ZenmuxAPIError?
    }

    private struct StatisticsFetchResult {
        let data: ZenmuxStatisticsData?
        let error: ZenmuxAPIError?
    }

    public init(apiClient: ZenmuxAPIClient = ZenmuxAPIClient()) {
        self.apiClient = apiClient
    }

    public func updateProxyConfiguration(_ config: ProxyConfiguration?) {
        apiClient.invalidate()
        apiClient = ZenmuxAPIClient(proxyConfig: config)
        AppLog.settings.info("Proxy configuration updated: mode=\(config?.mode.rawValue ?? "none")")
    }

    deinit {
        apiClient.invalidate()
        refreshTask?.cancel()
        inFlightRefreshTask?.cancel()
    }

    public func refresh(apiKey: String, apiBaseURLString: String) async {
        inFlightRefreshTask?.cancel()
        requestSequence &+= 1
        let requestID = requestSequence
        activeRequestID = requestID

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            isRefreshing = false
            inFlightRefreshTask = nil
            lastError = ZenmuxAPIError(.noAPIKey, diagnosticMessage: "Attempted subscription refresh without an API key")
            AppLog.refresh.warning("Refresh \(requestID) skipped because API key is empty")
            return
        }
        guard AppConstants.API.subscriptionDetailURL(baseURLString: apiBaseURLString) != nil else {
            isRefreshing = false
            inFlightRefreshTask = nil
            lastError = ZenmuxAPIError(.invalidURL, diagnosticMessage: "Invalid API base URL: \(apiBaseURLString)")
            AppLog.refresh.error("Refresh \(requestID) skipped because API base URL is invalid")
            return
        }

        isRefreshing = true
        lastError = nil
        AppLog.refresh.info("Refresh \(requestID) started")

        let task = Task { [apiClient] in
            try await Self.loadRefreshData(
                apiClient: apiClient,
                apiKey: key,
                apiBaseURLString: apiBaseURLString
            )
        }
        inFlightRefreshTask = task

        do {
            let result = try await task.value
            guard activeRequestID == requestID else {
                AppLog.refresh.debug("Ignoring stale refresh \(requestID) success")
                return
            }
            subscriptionData = result.subscriptionData
            statisticsTokens = result.statisticsTokens
            statisticsCost = result.statisticsCost
            statisticsTokensError = result.statisticsTokensError
            statisticsCostError = result.statisticsCostError
            lastError = nil
            lastUpdated = Date()
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.info("Refresh \(requestID) succeeded")
        } catch is CancellationError {
            guard activeRequestID == requestID else { return }
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.debug("Refresh \(requestID) cancelled")
        } catch let apiError as ZenmuxAPIError {
            guard activeRequestID == requestID else {
                AppLog.refresh.debug("Ignoring stale refresh \(requestID) failure")
                return
            }
            lastError = apiError
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.error("Refresh \(requestID) failed: \(apiError.type.rawValue) status \(apiError.statusCode ?? -1)")
        } catch {
            guard activeRequestID == requestID else {
                AppLog.refresh.debug("Ignoring stale refresh \(requestID) unexpected failure")
                return
            }
            lastError = ZenmuxAPIError(.networkError, message: error.localizedDescription, diagnosticMessage: String(describing: error))
            isRefreshing = false
            inFlightRefreshTask = nil
            AppLog.refresh.error("Refresh \(requestID) failed unexpectedly: \(error.localizedDescription)")
        }
    }

    private static func loadRefreshData(
        apiClient: ZenmuxAPIClient,
        apiKey: String,
        apiBaseURLString: String
    ) async throws -> RefreshResult {
        let subscriptionData = try await apiClient.fetchSubscription(
            apiKey: apiKey,
            apiBaseURLString: apiBaseURLString
        )

        guard let dateRange = ZenmuxStatisticsDateRange.recentDays(Self.statisticsDayCount) else {
            return RefreshResult(
                subscriptionData: subscriptionData,
                statisticsTokens: nil,
                statisticsCost: nil,
                statisticsTokensError: nil,
                statisticsCostError: nil
            )
        }

        async let tokensResult = fetchStatistics(
            apiClient: apiClient,
            apiKey: apiKey,
            apiBaseURLString: apiBaseURLString,
            metric: .tokens,
            dateRange: dateRange
        )
        async let costResult = fetchStatistics(
            apiClient: apiClient,
            apiKey: apiKey,
            apiBaseURLString: apiBaseURLString,
            metric: .cost,
            dateRange: dateRange
        )

        let tokens = await tokensResult
        let cost = await costResult
        return RefreshResult(
            subscriptionData: subscriptionData,
            statisticsTokens: tokens.data,
            statisticsCost: cost.data,
            statisticsTokensError: tokens.error,
            statisticsCostError: cost.error
        )
    }

    private static func fetchStatistics(
        apiClient: ZenmuxAPIClient,
        apiKey: String,
        apiBaseURLString: String,
        metric: ZenmuxStatisticsMetric,
        dateRange: ZenmuxStatisticsDateRange
    ) async -> StatisticsFetchResult {
        var items: [ZenmuxAccountStatisticsItem] = []

        for month in dateRange.queryMonths {
            do {
                let monthItems = try await apiClient.fetchAccountStatistics(
                    apiKey: apiKey,
                    apiBaseURLString: apiBaseURLString,
                    metric: metric,
                    queryMonth: month
                )
                items.append(contentsOf: monthItems)
            } catch is CancellationError {
                return StatisticsFetchResult(data: nil, error: nil)
            } catch {
                let apiError = normalizedAPIError(from: error)
                AppLog.refresh.warning("Statistics \(metric.rawValue) refresh failed: \(apiError.type.rawValue)")
                return StatisticsFetchResult(data: nil, error: apiError)
            }
        }

        return StatisticsFetchResult(
            data: mergeStatistics(items, metric: metric, dateRange: dateRange),
            error: nil
        )
    }

    /// Converts `bizTime` (`YYYYMMDD`) items into per-day buckets, sums models within each day,
    /// and keeps only days inside the requested range.
    private static func mergeStatistics(
        _ items: [ZenmuxAccountStatisticsItem],
        metric: ZenmuxStatisticsMetric,
        dateRange: ZenmuxStatisticsDateRange
    ) -> ZenmuxStatisticsData {
        var modelsByDate: [String: [ZenmuxStatisticsModelValue]] = [:]
        for item in items {
            guard let date = apiDateString(fromBizTime: item.bizTime),
                date >= dateRange.startingAt, date <= dateRange.endingAt
            else { continue }
            modelsByDate[date, default: []].append(
                ZenmuxStatisticsModelValue(model: item.modelSlug, label: item.modelSlug, value: item.value)
            )
        }

        let series = modelsByDate.keys.sorted().map { date in
            ZenmuxStatisticsBucket(period: date, date: date, models: modelsByDate[date] ?? [])
        }
        return ZenmuxStatisticsData(
            metric: metric.rawValue,
            bucketWidth: "1d",
            startingAt: dateRange.startingAt,
            endingAt: dateRange.endingAt,
            totalBuckets: series.count,
            series: series
        )
    }

    /// `"20260903"` -> `"2026-09-03"`; returns nil for anything else.
    private static func apiDateString(fromBizTime bizTime: String?) -> String? {
        guard let bizTime, bizTime.count == 8, bizTime.allSatisfy(\.isNumber) else { return nil }
        let year = bizTime.prefix(4)
        let month = bizTime.dropFirst(4).prefix(2)
        let day = bizTime.suffix(2)
        return "\(year)-\(month)-\(day)"
    }

    private static func normalizedAPIError(from error: Error) -> ZenmuxAPIError {
        if let apiError = error as? ZenmuxAPIError {
            return apiError
        }
        return ZenmuxAPIError(
            .networkError,
            message: error.localizedDescription,
            diagnosticMessage: String(describing: error)
        )
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
                        AppLog.settings.warning("Refresh interval \(settings.refreshInterval)s is below minimum or invalid; using \(normalizedInterval)s")
                    }
                    self.isPaused = !settings.alwaysRefresh
                    return AutoRefreshSnapshot(
                        alwaysRefresh: settings.alwaysRefresh,
                        apiKey: settings.apiKey,
                        apiBaseURLString: settings.apiBaseURLString,
                        trimmedKeyIsEmpty: settings.trimmedAPIKey.isEmpty,
                        interval: normalizedInterval
                    )
                }

                if snapshot.alwaysRefresh, !snapshot.trimmedKeyIsEmpty {
                    await self.refresh(apiKey: snapshot.apiKey, apiBaseURLString: snapshot.apiBaseURLString)
                } else {
                    AppLog.refresh.debug("Auto refresh skipped; enabled=\(snapshot.alwaysRefresh), hasKey=\(!snapshot.trimmedKeyIsEmpty)")
                }

                AppLog.refresh.debug("Auto refresh sleeping for \(snapshot.interval)s")
                do {
                    try await Task.sleep(nanoseconds: Self.sleepNanoseconds(for: snapshot.interval))
                } catch is CancellationError {
                    AppLog.refresh.info("Auto refresh loop cancelled")
                    return
                } catch {
                    AppLog.refresh.error("Auto refresh sleep failed: \(error.localizedDescription)")
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
