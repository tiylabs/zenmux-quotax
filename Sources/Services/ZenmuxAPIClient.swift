import Foundation

public protocol URLSessionDataFetching: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataFetching {}

public struct ZenmuxAPIClient: Sendable {
    private let session: URLSessionDataFetching
    private let decoder: JSONDecoder

    public init(session: URLSessionDataFetching = URLSession.shared, decoder: JSONDecoder = JSONDecoder()) {
        self.session = session
        self.decoder = decoder
    }

    public func fetchSubscription(apiKey: String) async throws -> ZenmuxSubscriptionData {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            throw ZenmuxAPIError(.noAPIKey, diagnosticMessage: "Attempted subscription refresh without an API key")
        }
        guard let url = URL(string: AppConstants.API.subscriptionDetailURLString) else {
            throw ZenmuxAPIError(.invalidURL, diagnosticMessage: "Invalid URL string: \(AppConstants.API.subscriptionDetailURLString)")
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
            let duration = Date().timeIntervalSince(startedAt)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLog.network.error("Subscription request returned a non-HTTP response after \(duration, privacy: .public)s")
                throw ZenmuxAPIError(.networkError, message: "Invalid HTTP response", diagnosticMessage: "Response type: \(String(describing: type(of: response)))")
            }

            AppLog.network.debug("Subscription request finished with status \(httpResponse.statusCode, privacy: .public) in \(duration, privacy: .public)s")
            guard (200..<300).contains(httpResponse.statusCode) else {
                let body = Self.responseSnippet(from: data) ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                AppLog.network.error("Subscription request failed with HTTP \(httpResponse.statusCode, privacy: .public); body snippet length \(body.count, privacy: .public)")
                throw ZenmuxAPIError(.httpError, statusCode: httpResponse.statusCode, message: body, diagnosticMessage: "HTTP \(httpResponse.statusCode), responseBodySnippet: \(body)")
            }

            do {
                let decodedResponse = try decoder.decode(ZenmuxSubscriptionResponse.self, from: data)
                if decodedResponse.success == false {
                    let message = decodedResponse.message ?? "Zenmux API returned success=false"
                    AppLog.network.error("Subscription API returned success=false with status \(decodedResponse.statusCode ?? -1, privacy: .public)")
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
                AppLog.network.info("Subscription request decoded successfully in \(duration, privacy: .public)s")
                return subscriptionData
            } catch let apiError as ZenmuxAPIError {
                throw apiError
            } catch let decodingError as DecodingError {
                let diagnostic = ZenmuxAPIError.diagnosticDescription(for: decodingError)
                AppLog.decode.error("Subscription response decode failed: \(diagnostic, privacy: .public)")
                throw ZenmuxAPIError(.decodeError, message: diagnostic, diagnosticMessage: "Body snippet: \(Self.responseSnippet(from: data) ?? "<unavailable>")")
            }
        } catch is CancellationError {
            AppLog.network.debug("Subscription request cancelled")
            throw CancellationError()
        } catch let apiError as ZenmuxAPIError {
            throw apiError
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                AppLog.network.debug("Subscription request URL cancelled: \(urlError.code.rawValue, privacy: .public) \(urlError.localizedDescription, privacy: .public)")
                throw CancellationError()
            }
            AppLog.network.error("Subscription request URL error: \(urlError.code.rawValue, privacy: .public) \(urlError.localizedDescription, privacy: .public)")
            throw ZenmuxAPIError(.networkError, message: urlError.localizedDescription, diagnosticMessage: "URLError code: \(urlError.code.rawValue)")
        } catch {
            AppLog.network.error("Subscription request failed unexpectedly: \(error.localizedDescription, privacy: .public)")
            throw ZenmuxAPIError(.networkError, message: error.localizedDescription, diagnosticMessage: String(describing: error))
        }
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
