import Foundation

public protocol URLSessionDataFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataFetching {}

public struct ZenmuxAPIClient: Sendable {
    private let session: URLSessionDataFetching
    private let decoder: JSONDecoder
    /// Non-nil only when this client owns the URLSession (created via `init(proxyConfig:)`);
    /// used to invalidate the session on replacement, preventing delegate/resource leaks.
    private let managedSession: URLSession?

    public init(session: URLSessionDataFetching = URLSession.shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
        self.managedSession = nil
    }

    public init(proxyConfig: ProxyConfiguration?, decoder: JSONDecoder = JSONDecoder()) {
        let urlSession = Self.createSession(proxyConfig: proxyConfig)
        self.session = urlSession
        self.decoder = decoder
        self.managedSession = urlSession
    }

    /// Invalidate the underlying URLSession created by `init(proxyConfig:)`.
    /// Call this before replacing the client to avoid leaking the session and its delegate.
    /// No-op for clients initialized with an injected session.
    public func invalidate() {
        managedSession?.invalidateAndCancel()
    }

    private static func createSession(proxyConfig: ProxyConfiguration?) -> URLSession {
        guard let config = proxyConfig else {
            // No proxy config specified — explicitly disable system proxy to avoid
            // inheriting system proxy settings from the ephemeral configuration.
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.connectionProxyDictionary = [:]
            return URLSession(configuration: sessionConfig)
        }

        switch config.mode {
        case .none:
            let config = URLSessionConfiguration.ephemeral
            config.connectionProxyDictionary = [:]
            return URLSession(configuration: config)

        case .system:
            return URLSession(configuration: .default)

        case .manual:
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.connectionProxyDictionary = buildProxyDictionary(config: config)
            let delegate = ProxyAuthenticationDelegate(
                username: config.username?.nilIfEmpty,
                password: config.password?.nilIfEmpty
            )
            return URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        }
    }

    private static func buildProxyDictionary(config: ProxyConfiguration) -> [AnyHashable: Any] {
        guard let host = config.host?.nilIfEmpty, let port = config.port, (1...65535).contains(port) else {
            return [:]
        }

        var proxy: [AnyHashable: Any] = [:]
        let portNumber = NSNumber(value: port)

        switch config.type {
        case .http?:
            proxy[kCFNetworkProxiesHTTPEnable] = true
            proxy[kCFNetworkProxiesHTTPProxy] = host
            proxy[kCFNetworkProxiesHTTPPort] = portNumber
        case .https?:
            proxy[kCFNetworkProxiesHTTPSEnable] = true
            proxy[kCFNetworkProxiesHTTPSProxy] = host
            proxy[kCFNetworkProxiesHTTPSPort] = portNumber
        case .socks5?:
            proxy[kCFNetworkProxiesSOCKSEnable] = true
            proxy[kCFNetworkProxiesSOCKSProxy] = host
            proxy[kCFNetworkProxiesSOCKSPort] = portNumber
            // Explicitly request SOCKS5; default version varies by platform.
            proxy[kCFStreamPropertySOCKSVersion] = kCFStreamSocketSOCKSVersion5
            // SOCKS credentials must be placed in the proxy dictionary.
            // URLSessionDelegate-based challenges are not reliably delivered for SOCKS5.
            if let username = config.username?.nilIfEmpty {
                proxy[kCFStreamPropertySOCKSUser] = username
                if let password = config.password {
                    proxy[kCFStreamPropertySOCKSPassword] = password
                }
            }
        case nil:
            return [:]
        }

        return proxy
    }

    public func fetchSubscription(apiKey: String, apiBaseURLString: String) async throws -> ZenmuxSubscriptionData {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ZenmuxAPIError(.noAPIKey, diagnosticMessage: "Attempted subscription refresh without an API key")
        }
        guard let url = AppConstants.API.subscriptionDetailURL(baseURLString: apiBaseURLString) else {
            throw ZenmuxAPIError(.invalidURL, diagnosticMessage: "Invalid API base URL: \(apiBaseURLString)")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: AppConstants.Network.timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let startedAt = Date()
        AppLog.network.debug("Subscription request started")

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = try validateHTTPResponse(
                response,
                duration: Date().timeIntervalSince(startedAt),
                requestName: "Subscription"
            )
            try validateStatusCode(
                httpResponse,
                data: data,
                duration: Date().timeIntervalSince(startedAt),
                requestName: "Subscription"
            )
            return try decodeSubscriptionResponse(from: data, duration: Date().timeIntervalSince(startedAt))
        } catch let error as ZenmuxAPIError {
            throw error
        } catch is CancellationError {
            AppLog.network.debug("Subscription request cancelled")
            throw CancellationError()
        } catch let urlError as URLError {
            throw wrapURLError(urlError, requestName: "Subscription")
        } catch {
            AppLog.network.error("Subscription request failed unexpectedly: \(error.localizedDescription)")
            throw ZenmuxAPIError(.networkError, message: error.localizedDescription, diagnosticMessage: String(describing: error))
        }
    }

    /// Fetches the personal account's daily series for one month (`yyyyMM`) from the
    /// `management/usage` (tokens) or `management/cost` endpoint.
    public func fetchAccountStatistics(
        apiKey: String,
        apiBaseURLString: String,
        metric: ZenmuxStatisticsMetric,
        queryMonth: String
    ) async throws -> [ZenmuxAccountStatisticsItem] {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ZenmuxAPIError(.noAPIKey, diagnosticMessage: "Attempted statistics request without an API key")
        }
        guard
            let url = AppConstants.API.accountStatisticsURL(
                baseURLString: apiBaseURLString,
                metric: metric,
                queryMonth: queryMonth
            )
        else {
            throw ZenmuxAPIError(.invalidURL, diagnosticMessage: "Invalid API base URL: \(apiBaseURLString)")
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: AppConstants.Network.timeoutInterval)
        request.httpMethod = "GET"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestName = "Statistics \(metric.rawValue) \(queryMonth)"
        let startedAt = Date()
        AppLog.network.debug("\(requestName) request started")

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = try validateHTTPResponse(
                response,
                duration: Date().timeIntervalSince(startedAt),
                requestName: requestName
            )
            try validateStatusCode(
                httpResponse,
                data: data,
                duration: Date().timeIntervalSince(startedAt),
                requestName: requestName
            )
            return try decodeAccountStatisticsResponse(
                from: data,
                metric: metric,
                requestName: requestName,
                duration: Date().timeIntervalSince(startedAt)
            )
        } catch let error as ZenmuxAPIError {
            throw error
        } catch is CancellationError {
            AppLog.network.debug("\(requestName) request cancelled")
            throw CancellationError()
        } catch let urlError as URLError {
            throw wrapURLError(urlError, requestName: requestName)
        } catch {
            AppLog.network.error("\(requestName) request failed unexpectedly: \(error.localizedDescription)")
            throw ZenmuxAPIError(.networkError, message: error.localizedDescription, diagnosticMessage: String(describing: error))
        }
    }

    private func validateHTTPResponse(
        _ response: URLResponse,
        duration: TimeInterval,
        requestName: String
    ) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            AppLog.network.error("\(requestName) request returned a non-HTTP response after \(duration)s")
            throw ZenmuxAPIError(
                .networkError,
                message: "Invalid HTTP response",
                diagnosticMessage: "Response type: \(String(describing: type(of: response)))"
            )
        }
        AppLog.network.debug("\(requestName) request finished with status \(httpResponse.statusCode) in \(duration)s")
        return httpResponse
    }

    private func validateStatusCode(
        _ httpResponse: HTTPURLResponse,
        data: Data,
        duration: TimeInterval,
        requestName: String
    ) throws {
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = Self.responseSnippet(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            AppLog.network.error("\(requestName) request failed with HTTP \(httpResponse.statusCode); body snippet length \(body.count)")
            throw ZenmuxAPIError(
                .httpError,
                statusCode: httpResponse.statusCode,
                message: body,
                diagnosticMessage: "HTTP \(httpResponse.statusCode), responseBodySnippet: \(body)"
            )
        }
    }

    private func decodeAccountStatisticsResponse(
        from data: Data,
        metric: ZenmuxStatisticsMetric,
        requestName: String,
        duration: TimeInterval
    ) throws -> [ZenmuxAccountStatisticsItem] {
        do {
            let decodedResponse = try decoder.decode(ZenmuxAccountStatisticsResponse.self, from: data)
            if decodedResponse.success == false {
                let message = decodedResponse.message ?? "ZenMux statistics API returned success=false"
                AppLog.network.error("\(requestName) API returned success=false with status \(decodedResponse.statusCode ?? -1)")
                throw ZenmuxAPIError(
                    .apiError,
                    statusCode: decodedResponse.statusCode,
                    message: message,
                    diagnosticMessage: "Statistics envelope success=false"
                )
            }
            guard let payload = decodedResponse.data else {
                AppLog.decode.error("\(requestName) response decoded without data")
                throw ZenmuxAPIError(
                    .decodeError,
                    message: "Statistics response did not include data.",
                    diagnosticMessage: "Decoded response had nil data; body snippet: \(Self.responseSnippet(from: data) ?? "<unavailable>")"
                )
            }
            AppLog.network.info("\(requestName) request decoded successfully in \(duration)s")
            switch metric {
            case .tokens: return payload.tokensByModel
            case .cost: return payload.costByModel
            }
        } catch let apiError as ZenmuxAPIError {
            throw apiError
        } catch let decodingError as DecodingError {
            let diagnostic = ZenmuxAPIError.diagnosticDescription(for: decodingError)
            AppLog.decode.error("\(requestName) response decode failed: \(diagnostic)")
            throw ZenmuxAPIError(
                .decodeError,
                message: diagnostic,
                diagnosticMessage: "Body snippet: \(Self.responseSnippet(from: data) ?? "<unavailable>")"
            )
        }
    }

    private func decodeSubscriptionResponse(from data: Data, duration: TimeInterval) throws -> ZenmuxSubscriptionData {
        do {
            let decodedResponse = try decoder.decode(ZenmuxSubscriptionResponse.self, from: data)
            if decodedResponse.success == false {
                let message = decodedResponse.message ?? "Zenmux API returned success=false"
                AppLog.network.error("Subscription API returned success=false with status \(decodedResponse.statusCode ?? -1)")
                throw ZenmuxAPIError(.apiError, statusCode: decodedResponse.statusCode, message: message, diagnosticMessage: "Envelope success=false")
            }
            guard let subscriptionData = decodedResponse.data else {
                AppLog.decode.error("Subscription response decoded without data")
                throw ZenmuxAPIError(
                    .decodeError,
                    message: "Subscription response did not include data.",
                    diagnosticMessage: "Decoded response had nil data; body snippet: \(Self.responseSnippet(from: data) ?? "<unavailable>")"
                )
            }
            AppLog.network.info("Subscription request decoded successfully in \(duration)s")
            return subscriptionData
        } catch let apiError as ZenmuxAPIError {
            throw apiError
        } catch let decodingError as DecodingError {
            let diagnostic = ZenmuxAPIError.diagnosticDescription(for: decodingError)
            AppLog.decode.error("Subscription response decode failed: \(diagnostic)")
            throw ZenmuxAPIError(
                .decodeError,
                message: diagnostic,
                diagnosticMessage: "Body snippet: \(Self.responseSnippet(from: data) ?? "<unavailable>")"
            )
        }
    }

    private func wrapURLError(_ urlError: URLError, requestName: String) -> Error {
        if urlError.code == .cancelled {
            AppLog.network.debug("\(requestName) request URL cancelled: \(urlError.code.rawValue) \(urlError.localizedDescription)")
            return CancellationError()
        }
        AppLog.network.error("\(requestName) request URL error: \(urlError.code.rawValue) \(urlError.localizedDescription)")
        return ZenmuxAPIError(.networkError, message: urlError.localizedDescription, diagnosticMessage: "URLError code: \(urlError.code.rawValue)")
    }

    private static func responseSnippet(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        let prefix = data.prefix(AppConstants.Network.responseSnippetLimit)
        if let utf8Snippet = String(data: prefix, encoding: .utf8) {
            return utf8Snippet
        }
        let hexSnippet = prefix.map { String(format: "%02x", $0) }.joined(separator: " ")
        return "<non-UTF8 body hex: \(hexSnippet)>"
    }
}

private final class ProxyAuthenticationDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let username: String?
    private let password: String?

    init(username: String?, password: String?) {
        self.username = username
        self.password = password
        super.init()
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {

        guard
            challenge.protectionSpace.authenticationMethod == "NSURLAuthenticationMethodHTTPProxy"
                || challenge.protectionSpace.authenticationMethod == "NSURLAuthenticationMethodSOCKS",
            let username, let password, !username.isEmpty
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        if challenge.previousFailureCount > 0 {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let credential = URLCredential(user: username, password: password, persistence: .forSession)
        completionHandler(.useCredential, credential)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
