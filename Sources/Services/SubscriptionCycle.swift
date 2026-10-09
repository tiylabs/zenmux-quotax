import Foundation

struct ZenmuxStatisticsDateRange: Sendable {
    let start: Date
    let end: Date

    var startingAt: String {
        Self.apiDateString(from: start)
    }

    var endingAt: String {
        Self.apiDateString(from: end)
    }

    var dayCount: Int {
        let calendar = Self.utcCalendar
        guard let days = calendar.dateComponents([.day], from: start, to: end).day else { return 0 }
        return days + 1
    }

    static func recentDays(_ count: Int, now: Date = Date()) -> ZenmuxStatisticsDateRange? {
        guard count > 0 else { return nil }

        let calendar = Self.utcCalendar
        let end = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(count - 1), to: end) else {
            return nil
        }
        return Self(start: start, end: end)
    }

    /// Distinct calendar months (`yyyyMM`, UTC) touched by this range, in ascending order.
    var queryMonths: [String] {
        guard start <= end else { return [] }

        let calendar = Self.utcCalendar
        var months: [String] = []
        var cursor = start
        while cursor <= end {
            let parts = calendar.dateComponents([.year, .month], from: cursor)
            if let year = parts.year, let month = parts.month {
                let value = String(format: "%04d%02d", year, month)
                if months.last != value { months.append(value) }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        return months
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func apiDateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = utcCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = utcCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
