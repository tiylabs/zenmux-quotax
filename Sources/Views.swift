import AppKit
import SwiftUI

struct MenuHeaderView: View {
    @ObservedObject var apiService: ZenmuxAPIService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(nsImage: zenmuxAppIcon())
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quotax")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if apiService.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
    }

    private var subtitle: String {
        if apiService.isPaused { return "Auto refresh paused" }
        if let updated = apiService.lastUpdated { return "Updated \(updated.formatted(date: .omitted, time: .shortened))" }
        return "Management API"
    }
}

struct MenuQuotaView: View {
    let title: String
    let usedFlows: Double?
    let remainingFlows: Double?
    let maxFlows: Double?
    let usedValueUSD: Double?
    let maxValueUSD: Double?
    let usagePercentage: Double?
    let resetsAt: String?

    init(title: String, monthly: ZenmuxQuotaMonthly) {
        self.title = title
        self.usedFlows = nil
        self.remainingFlows = nil
        self.maxFlows = monthly.maxFlows
        self.usedValueUSD = nil
        self.maxValueUSD = monthly.maxValueUSD
        self.usagePercentage = nil
        self.resetsAt = nil
    }

    init(title: String, window: ZenmuxQuotaWindow) {
        self.title = title
        self.usedFlows = window.usedFlows
        self.remainingFlows = window.remainingFlows
        self.maxFlows = window.maxFlows
        self.usedValueUSD = window.usedValueUSD
        self.maxValueUSD = window.maxValueUSD
        self.usagePercentage = window.usagePercentage
        self.resetsAt = window.resetsAt
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).bold()
                Spacer()
                if let remainingFlows {
                    Text("\(formatNumber(remainingFlows)) left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 12) {
                metric("Used", value: usedFlows.map(formatNumber) ?? "—")
                metric("Remaining", value: remainingFlows.map(formatNumber) ?? "—")
                metric("Max", value: maxFlows.map(formatNumber) ?? "—")
                metric("USD", value: maxValueUSD.map { "$" + formatNumber($0) } ?? usedValueUSD.map { "$" + formatNumber($0) } ?? "—")
            }
            HStack(spacing: 10) {
                if let usagePercentage {
                    Text("Usage: \(formatPercent(usagePercentage))")
                }
                if let resetsAt, !resetsAt.isEmpty {
                    Text("Resets: \(resetsAt)")
                        .lineLimit(1)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption).monospacedDigit()
        }
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func formatPercent(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value * 100)%"
    }
}

struct MenuContentView: View {
    @ObservedObject var apiService: ZenmuxAPIService
    @ObservedObject var settings: SettingsManager
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onOpenManagement: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MenuHeaderView(apiService: apiService)

            if let data = apiService.subscriptionData {
                planSection(data)
                if let quota5 = data.quota5Hour {
                    MenuQuotaView(title: "5 hour quota", window: quota5)
                }
                if let quota7 = data.quota7Day {
                    MenuQuotaView(title: "7 day quota", window: quota7)
                }
                if let monthly = data.quotaMonthly {
                    MenuQuotaView(title: "Monthly quota", monthly: monthly)
                }
            } else {
                ContentUnavailableView(
                    "No subscription data",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text(settings.trimmedAPIKey.isEmpty ? "Set Management API Key in Settings." : "Refresh to load quota.")
                )
                .frame(height: 120)
            }

            if let error = apiService.lastError {
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            HStack {
                Button("Refresh", action: onRefresh)
                Button("Open Management", action: onOpenManagement)
                Spacer()
                Button("Settings", action: onOpenSettings)
                Button("Quit", action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func planSection(_ data: ZenmuxSubscriptionData) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(data.primaryPlanName)
                    .font(.title3)
                    .bold()
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Status: \(data.primaryStatus)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let expiresAt = data.plan?.expiresAt {
                    Text(expiresAt)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    let onSaveAPIKey: (String) -> Void
    @State private var apiKeyInput: String = ""
    @State private var showKeySaved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quotax")
                .font(.title2)
                .bold()

            VStack(alignment: .leading, spacing: 6) {
                Text("Management API Key").font(.headline)
                HStack {
                    SecureField("Zenmux Management API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        onSaveAPIKey(apiKeyInput)
                        showKeySaved = true
                    }
                }
                if showKeySaved {
                    Text("API Key saved")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto refresh", isOn: $settings.alwaysRefresh)
                HStack {
                    Text("Refresh interval")
                    TextField("refresh_interval", value: $settings.refreshInterval, format: .number)
                        .frame(width: 80)
                    Text("seconds")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 460, height: 300)
        .onAppear {
            apiKeyInput = settings.apiKey
        }
    }
}
