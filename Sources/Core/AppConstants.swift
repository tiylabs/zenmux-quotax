import CoreGraphics
import Foundation

public enum AppConstants {
    public enum API {
        public static let subscriptionDetailURLString = "https://zenmux.ai/api/v1/management/subscription/detail"
        public static let managementPortalURLString = "https://zenmux.ai/platform/management"
    }

    public enum Network {
        public static let timeoutInterval: TimeInterval = 20
        public static let responseSnippetLimit = 512
    }

    public enum Refresh {
        public static let minimumInterval: TimeInterval = 30
        public static let defaultInterval: TimeInterval = 300

        public static func normalizedInterval(_ interval: TimeInterval) -> TimeInterval {
            guard interval.isFinite, interval >= minimumInterval else {
                return minimumInterval
            }
            return interval
        }
    }

    public enum StatusBar {
        public static let width: CGFloat = 72
    }

    public enum Menu {
        public static let width: CGFloat = 380
        public static let minimumHeight: CGFloat = 180
        public static let edgeInset: CGFloat = 8
        public static let verticalOffset: CGFloat = 6
        public static let fallbackTopOffset: CGFloat = 32
    }
}
