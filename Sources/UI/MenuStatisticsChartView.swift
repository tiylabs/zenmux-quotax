import Charts
import Foundation
import SwiftUI

struct MenuStatisticsChartView: View {
    let tokensData: ZenmuxStatisticsData?
    let costData: ZenmuxStatisticsData?
    let tokensError: ZenmuxAPIError?
    let costError: ZenmuxAPIError?
    let timeZone: TimeZone

    @State private var selectedMetric: ZenmuxStatisticsMetric = .tokens
    @State private var hoveredPointID: String?

    private var availableMetrics: [ZenmuxStatisticsMetric] {
        ZenmuxStatisticsMetric.allCases.filter { metric in
            switch metric {
            case .tokens: return tokensData != nil || tokensError != nil
            case .cost: return costData != nil || costError != nil
            }
        }
    }

    private var activeMetric: ZenmuxStatisticsMetric {
        availableMetrics.contains(selectedMetric) ? selectedMetric : (availableMetrics.first ?? .tokens)
    }

    private var displayedData: ZenmuxStatisticsData? {
        switch activeMetric {
        case .tokens: return tokensData
        case .cost: return costData
        }
    }

    private var displayedError: ZenmuxAPIError? {
        switch activeMetric {
        case .tokens: return tokensError
        case .cost: return costError
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let data = displayedData {
                let points = chartPoints(from: data)
                if points.isEmpty {
                    emptyState
                } else {
                    chart(points: points)
                    summary(points: points)
                }
            } else if let displayedError {
                errorState(displayedError)
            } else {
                emptyState
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .controlBackgroundColor).opacity(0.92),
                            Color.primary.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.16), radius: 16, x: 0, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            normalizeSelectedMetric()
        }
        .onChange(of: availableMetrics) { _, _ in
            hoveredPointID = nil
            normalizeSelectedMetric()
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label("Daily usage", systemImage: "chart.bar.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(periodText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if availableMetrics.count > 1 {
                Picker("Statistics metric", selection: $selectedMetric) {
                    ForEach(availableMetrics) { metric in
                        Text(metric.title).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .accessibilityLabel("Statistics metric")
            }
        }
    }

    private func chart(points: [DailyStatisticsPoint]) -> some View {
        Chart(points) { point in
            BarMark(
                x: .value("Day", point.date, unit: .day),
                y: .value(activeMetric.title, point.value)
            )
            .foregroundStyle(barColor(for: point))
            .cornerRadius(point.id == hoveredPointID ? 4 : 3)
        }
        .chartYScale(domain: 0...yAxisMaximum(points: points))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride(for: points.count))) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 3]))
                    .foregroundStyle(Color.primary.opacity(0.16))
                AxisTick()
                    .foregroundStyle(Color.primary.opacity(0.22))
                AxisValueLabel {
                    if let date: Date = value.as(Date.self) {
                        Text(displayDateFormatter.string(from: date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6))
                    .foregroundStyle(Color.primary.opacity(0.16))
                AxisTick()
                    .foregroundStyle(Color.primary.opacity(0.22))
                AxisValueLabel {
                    if let rawValue: Double = value.as(Double.self) {
                        Text(axisValueText(rawValue))
                    }
                }
            }
        }
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.primary.opacity(0.025))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        updateHoveredPoint(phase, proxy: proxy, geometry: geometry, points: points)
                    }
            }
        }
        .frame(height: 148)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Daily \(activeMetric.title.lowercased()) chart")
    }

    private func summary(points: [DailyStatisticsPoint]) -> some View {
        let total = points.reduce(0) { $0 + $1.value }
        let average = total / Double(points.count)
        let lastDate = points.last.map { displayDateFormatter.string(from: $0.date) } ?? "—"

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(summaryText(points: points, average: average))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()

            Spacer(minLength: 8)

            Text("Through \(lastDate)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .animation(.easeOut(duration: 0.12), value: hoveredPointID)
    }

    private func summaryText(points: [DailyStatisticsPoint], average: Double) -> String {
        guard let hoveredPointID, let hoveredPoint = points.first(where: { $0.id == hoveredPointID }) else {
            return "Average \(metricValueText(average))/day"
        }
        return "\(displayDateFormatter.string(from: hoveredPoint.date)) · \(metricValueText(hoveredPoint.value))"
    }

    private func barColor(for point: DailyStatisticsPoint) -> Color {
        point.id == hoveredPointID ? Color.accentColor : Color.accentColor.opacity(0.72)
    }

    private func updateHoveredPoint(
        _ phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy,
        points: [DailyStatisticsPoint]
    ) {
        switch phase {
        case .active(let location):
            guard let plotFrame = proxy.plotFrame else {
                hoveredPointID = nil
                return
            }

            let plotRect = geometry[plotFrame]
            guard plotRect.contains(location) else {
                hoveredPointID = nil
                return
            }

            let plotX = location.x - plotRect.origin.x
            guard let hoveredDate: Date = proxy.value(atX: plotX, as: Date.self) else {
                hoveredPointID = nil
                return
            }

            hoveredPointID =
                points.min {
                    abs($0.date.timeIntervalSince(hoveredDate))
                        < abs($1.date.timeIntervalSince(hoveredDate))
                }?.id
        case .ended:
            hoveredPointID = nil
        }
    }

    private var periodText: String {
        guard let data = displayedData else { return "Last 30 days" }
        guard
            let startingAt = data.startingAt,
            let endingAt = data.endingAt,
            let startDate = chartDate(from: startingAt),
            let endDate = chartDate(from: endingAt)
        else {
            return "Last 30 days"
        }
        let start = displayDateFormatter.string(from: startDate)
        let end = displayDateFormatter.string(from: endDate)
        return "Last 30 days · \(start) – \(end)"
    }

    private var emptyState: some View {
        Label("No daily usage recorded yet", systemImage: "chart.bar.xaxis")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
    }

    private func errorState(_ error: ZenmuxAPIError) -> some View {
        Label {
            Text(error.localizedDescription)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func chartPoints(from data: ZenmuxStatisticsData) -> [DailyStatisticsPoint] {
        var valuesByDate: [String: Double] = [:]
        for bucket in data.series {
            guard let dateString = bucket.date else { continue }
            let value = bucket.models.reduce(0) { partialResult, modelValue in
                partialResult + max(0, modelValue.value ?? 0)
            }

            valuesByDate[dateString, default: 0] += value
        }

        guard
            let startingAt = data.startingAt,
            let endingAt = data.endingAt,
            let startDate = apiDateFormatter.date(from: startingAt),
            let endDate = apiDateFormatter.date(from: endingAt),
            startDate <= endDate
        else {
            return valuesByDate.keys.sorted().compactMap { dateString in
                guard let date = chartDate(from: dateString) else { return nil }
                return DailyStatisticsPoint(id: dateString, date: date, value: valuesByDate[dateString] ?? 0)
            }
        }

        var points: [DailyStatisticsPoint] = []
        var date = apiCalendar.startOfDay(for: startDate)
        let lastDate = apiCalendar.startOfDay(for: endDate)
        while date <= lastDate {
            let dateString = apiDateFormatter.string(from: date)
            let chartDate = apiCalendar.date(byAdding: .hour, value: 12, to: date) ?? date
            points.append(DailyStatisticsPoint(id: dateString, date: chartDate, value: valuesByDate[dateString] ?? 0))

            guard let nextDate = apiCalendar.date(byAdding: .day, value: 1, to: date), nextDate > date else {
                break
            }
            date = nextDate
        }
        return points
    }

    private func yAxisMaximum(points: [DailyStatisticsPoint]) -> Double {
        let maximum = points.map(\.value).max() ?? 0
        return maximum > 0 ? maximum * 1.12 : 1
    }

    private func xAxisStride(for count: Int) -> Int {
        if count > 21 { return 7 }
        if count > 10 { return 3 }
        return 1
    }

    private func metricValueText(_ value: Double) -> String {
        switch activeMetric {
        case .tokens: return compactNumber(value)
        case .cost: return "$" + decimalNumber(value, maximumFractionDigits: 2)
        }
    }

    private func axisValueText(_ value: Double) -> String {
        switch activeMetric {
        case .tokens: return compactNumber(value)
        case .cost: return "$" + (value < 1 ? decimalNumber(value, maximumFractionDigits: 2) : compactNumber(value))
        }
    }

    private func compactNumber(_ value: Double) -> String {
        let absoluteValue = abs(value)
        let suffix: String
        let scaledValue: Double
        switch absoluteValue {
        case 1_000_000_000...:
            suffix = "B"
            scaledValue = value / 1_000_000_000
        case 1_000_000...:
            suffix = "M"
            scaledValue = value / 1_000_000
        case 1_000...:
            suffix = "K"
            scaledValue = value / 1_000
        default:
            return decimalNumber(value, maximumFractionDigits: 0)
        }

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        let formattedValue = formatter.string(from: NSNumber(value: scaledValue)) ?? String(scaledValue)
        return formattedValue + suffix
    }

    private func decimalNumber(_ value: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func normalizeSelectedMetric() {
        guard !availableMetrics.isEmpty, !availableMetrics.contains(selectedMetric) else { return }
        selectedMetric = availableMetrics[0]
    }

    private var apiDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = apiCalendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = apiCalendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private func chartDate(from dateString: String) -> Date? {
        guard let midnight = apiDateFormatter.date(from: dateString) else { return nil }
        return apiCalendar.date(byAdding: .hour, value: 12, to: midnight) ?? midnight
    }

    private var displayDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        return formatter
    }

    private var apiCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private struct DailyStatisticsPoint: Identifiable {
        let id: String
        let date: Date
        let value: Double
    }
}
