import Foundation

public struct ZenmuxSubscriptionResponse: Decodable {
    public var success: Bool?
    public var statusCode: Int?
    public var message: String?
    public var data: ZenmuxSubscriptionData?

    enum CodingKeys: String, CodingKey {
        case success
        case statusCode
        case message
        case data
    }

    public init(success: Bool? = nil, statusCode: Int? = nil, message: String? = nil, data: ZenmuxSubscriptionData? = nil) {
        self.success = success
        self.statusCode = statusCode
        self.message = message
        self.data = data
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        statusCode = try container.decodeIfPresent(Int.self, forKey: .statusCode)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        data = try container.decodeIfPresent(ZenmuxSubscriptionData.self, forKey: .data)

        if data == nil {
            data = try? ZenmuxSubscriptionData(from: decoder)
        }
    }
}

public struct ZenmuxSubscriptionData: Decodable {
    public var plan: ZenmuxPlan?
    public var currency: String?
    public var baseUSDPerFlow: Double?
    public var effectiveUSDPerFlow: Double?
    public var quotaMonthly: ZenmuxQuotaMonthly?
    public var quota5Hour: ZenmuxQuotaWindow?
    public var quota7Day: ZenmuxQuotaWindow?
    public var accountStatus: String?

    enum CodingKeys: String, CodingKey {
        case plan
        case currency
        case baseUSDPerFlow = "base_usd_per_flow"
        case effectiveUSDPerFlow = "effective_usd_per_flow"
        case quotaMonthly = "quota_monthly"
        case quota5Hour = "quota_5_hour"
        case quota7Day = "quota_7_day"
        case accountStatus = "account_status"
    }

    public init(
        plan: ZenmuxPlan? = nil,
        currency: String? = nil,
        baseUSDPerFlow: Double? = nil,
        effectiveUSDPerFlow: Double? = nil,
        quotaMonthly: ZenmuxQuotaMonthly? = nil,
        quota5Hour: ZenmuxQuotaWindow? = nil,
        quota7Day: ZenmuxQuotaWindow? = nil,
        accountStatus: String? = nil
    ) {
        self.plan = plan
        self.currency = currency
        self.baseUSDPerFlow = baseUSDPerFlow
        self.effectiveUSDPerFlow = effectiveUSDPerFlow
        self.quotaMonthly = quotaMonthly
        self.quota5Hour = quota5Hour
        self.quota7Day = quota7Day
        self.accountStatus = accountStatus
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        plan = try container.decodeFlexibleIfPresent(ZenmuxPlan.self, forKey: .plan)
        currency = try container.decodeFlexibleStringIfPresent(forKey: .currency)
        baseUSDPerFlow = try container.decodeFlexibleDoubleIfPresent(forKey: .baseUSDPerFlow)
        effectiveUSDPerFlow = try container.decodeFlexibleDoubleIfPresent(forKey: .effectiveUSDPerFlow)
        quotaMonthly = try container.decodeFlexibleIfPresent(ZenmuxQuotaMonthly.self, forKey: .quotaMonthly)
        quota5Hour = try container.decodeFlexibleIfPresent(ZenmuxQuotaWindow.self, forKey: .quota5Hour)
        quota7Day = try container.decodeFlexibleIfPresent(ZenmuxQuotaWindow.self, forKey: .quota7Day)
        accountStatus = try container.decodeFlexibleStringIfPresent(forKey: .accountStatus)
    }
}

public struct ZenmuxQuotaMonthly: Decodable, Equatable {
    public var maxFlows: Double?
    public var maxValueUSD: Double?

    enum CodingKeys: String, CodingKey {
        case maxFlows = "max_flows"
        case maxValueUSD = "max_value_usd"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxFlows = try container.decodeFlexibleDoubleIfPresent(forKey: .maxFlows)
        maxValueUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .maxValueUSD)
    }
}

public struct ZenmuxQuotaWindow: Decodable, Equatable {
    public var usagePercentage: Double?
    public var resetsAt: String?
    public var maxFlows: Double?
    public var usedFlows: Double?
    public var remainingFlows: Double?
    public var usedValueUSD: Double?
    public var maxValueUSD: Double?

    enum CodingKeys: String, CodingKey {
        case usagePercentage = "usage_percentage"
        case resetsAt = "resets_at"
        case maxFlows = "max_flows"
        case usedFlows = "used_flows"
        case remainingFlows = "remaining_flows"
        case usedValueUSD = "used_value_usd"
        case maxValueUSD = "max_value_usd"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usagePercentage = try container.decodeFlexibleDoubleIfPresent(forKey: .usagePercentage)
        resetsAt = try container.decodeFlexibleStringIfPresent(forKey: .resetsAt)
        maxFlows = try container.decodeFlexibleDoubleIfPresent(forKey: .maxFlows)
        usedFlows = try container.decodeFlexibleDoubleIfPresent(forKey: .usedFlows)
        remainingFlows = try container.decodeFlexibleDoubleIfPresent(forKey: .remainingFlows)
        usedValueUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .usedValueUSD)
        maxValueUSD = try container.decodeFlexibleDoubleIfPresent(forKey: .maxValueUSD)
    }
}

public struct ZenmuxPlan: Decodable, Equatable {
    public var tier: String?
    public var amountUSD: Double?
    public var interval: String?
    public var expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case tier
        case amountUSD = "amount_usd"
        case interval
        case expiresAt = "expires_at"
    }

    public init(tier: String? = nil, amountUSD: Double? = nil, interval: String? = nil, expiresAt: String? = nil) {
        self.tier = tier
        self.amountUSD = amountUSD
        self.interval = interval
        self.expiresAt = expiresAt
    }

    public init(from decoder: Decoder) throws {
        if let singleValue = try? decoder.singleValueContainer(), let planName = try? singleValue.decode(String.self) {
            self.init(tier: planName)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTier = try container.decodeFlexibleStringIfPresent(forKey: .tier)
        let decodedAmount = try container.decodeFlexibleDoubleIfPresent(forKey: .amountUSD)
        let decodedInterval = try container.decodeFlexibleStringIfPresent(forKey: .interval)
        let decodedExpiresAt = try container.decodeFlexibleStringIfPresent(forKey: .expiresAt)
        self.init(tier: decodedTier, amountUSD: decodedAmount, interval: decodedInterval, expiresAt: decodedExpiresAt)
    }
}

public enum ZenmuxAPIErrorType: String, Codable {
    case invalidURL
    case noAPIKey
    case networkError
    case httpError
    case decodeError
    case apiError
}

public struct ZenmuxAPIError: LocalizedError, Identifiable, Equatable {
    public let id = UUID()
    public let type: ZenmuxAPIErrorType
    public let statusCode: Int?
    public let message: String
    public let diagnosticMessage: String?

    public init(_ type: ZenmuxAPIErrorType, statusCode: Int? = nil, message: String? = nil, diagnosticMessage: String? = nil) {
        self.type = type
        self.statusCode = statusCode
        self.message = message ?? type.rawValue
        self.diagnosticMessage = diagnosticMessage
    }

    public var errorDescription: String? {
        switch type {
        case .invalidURL:
            return "Invalid Zenmux API URL."
        case .noAPIKey:
            return "No API Key. Please set your Zenmux Management API Key."
        case .networkError:
            return "Network error: \(message)"
        case .httpError:
            if let statusCode { return "HTTP error \(statusCode): \(message)" }
            return "HTTP error: \(message)"
        case .decodeError:
            return "Decode error: \(message)"
        case .apiError:
            return "API error: \(message)"
        }
    }

    public static func == (lhs: ZenmuxAPIError, rhs: ZenmuxAPIError) -> Bool {
        lhs.type == rhs.type && lhs.statusCode == rhs.statusCode && lhs.message == rhs.message && lhs.diagnosticMessage == rhs.diagnosticMessage
    }

    public static func diagnosticDescription(for error: DecodingError) -> String {
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .keyNotFound(_, let context), .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            let location = path.isEmpty ? "<root>" : path
            return "\(context.debugDescription) at \(location)"
        @unknown default:
            return String(describing: error)
        }
    }
}

extension KeyedDecodingContainer {
    func decodeFlexibleIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T? {
        if let value = try? decodeIfPresent(T.self, forKey: key) { return value }
        return nil
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value ? "true" : "false" }
        return nil
    }

    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

extension ZenmuxSubscriptionData {
    var primaryPlanName: String {
        plan?.tier?.capitalized ?? "Zenmux"
    }

    var primaryStatus: String {
        accountStatus ?? "Unknown"
    }
}
