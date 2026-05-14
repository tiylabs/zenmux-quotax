import AppKit
import SwiftUI

struct PanelTimeFormatter {
    private static func outputFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    private static func isoFormatter(formatOptions: ISO8601DateFormatter.Options) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = formatOptions
        return formatter
    }

    static func format(date: Date, timeZone: TimeZone) -> String {
        outputFormatter(timeZone: timeZone).string(from: date)
    }

    static func format(isoString: String, timeZone: TimeZone) -> String {
        let date = isoFormatter(formatOptions: [.withInternetDateTime, .withFractionalSeconds]).date(from: isoString)
            ?? isoFormatter(formatOptions: [.withInternetDateTime]).date(from: isoString)
        guard let date else { return isoString }
        return format(date: date, timeZone: timeZone)
    }

    static func relativeUpdatedText(since date: Date, now: Date = Date()) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(date)))
        if elapsed < 60 { return "Updated \(elapsed) seconds ago" }
        let minutes = elapsed / 60
        if minutes < 60 { return "Updated \(minutes) minutes ago" }
        let hours = minutes / 60
        if hours < 24 { return "Updated \(hours) hours ago" }
        let days = hours / 24
        return "Updated \(days) days ago"
    }
}

struct MenuHeaderView: View {
    @ObservedObject var apiService: ZenmuxAPIService
    @ObservedObject var settings: SettingsManager
    let data: ZenmuxSubscriptionData?

    var body: some View {
        HStack(alignment: .top) {
            Image(nsImage: zenmuxAppIcon())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(expText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let data {
                    Text("Status: \(data.primaryStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let updatedText {
                        Text(updatedText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else if apiService.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .offset(y: 2)
        }
    }

    private var title: String {
        guard let data else { return "ZenMux" }
        return "ZenMux · \(data.primaryPlanName)"
    }

    private var expText: String {
        guard let expiresAt = data?.plan?.expiresAt else { return "Management API" }
        return "Exp: \(PanelTimeFormatter.format(isoString: expiresAt, timeZone: settings.timeZone))"
    }

    private var updatedText: String? {
        guard !apiService.isPaused, let updated = apiService.lastUpdated else { return nil }
        return PanelTimeFormatter.relativeUpdatedText(since: updated)
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
    let timeZone: TimeZone
    let showsWaveProgress: Bool

    init(title: String, monthly: ZenmuxQuotaMonthly, timeZone: TimeZone) {
        self.title = title
        self.usedFlows = nil
        self.remainingFlows = nil
        self.maxFlows = monthly.maxFlows
        self.usedValueUSD = nil
        self.maxValueUSD = monthly.maxValueUSD
        self.usagePercentage = nil
        self.resetsAt = nil
        self.timeZone = timeZone
        self.showsWaveProgress = false
    }

    init(title: String, window: ZenmuxQuotaWindow, timeZone: TimeZone) {
        self.title = title
        self.usedFlows = window.usedFlows
        self.remainingFlows = window.remainingFlows
        self.maxFlows = window.maxFlows
        self.usedValueUSD = window.usedValueUSD
        self.maxValueUSD = window.maxValueUSD
        self.usagePercentage = window.usagePercentage
        self.resetsAt = window.resetsAt
        self.timeZone = timeZone
        self.showsWaveProgress = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline).bold()
                Spacer()
                if let resetsAt, !resetsAt.isEmpty {
                    Text("Resets: \(PanelTimeFormatter.format(isoString: resetsAt, timeZone: timeZone))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            HStack(spacing: 0) {
                metric("Used", value: usedFlows.map(formatNumber) ?? "—")
                metric("Left", value: remainingFlows.map(formatNumber) ?? "—")
                metric("Limit", value: maxFlows.map(formatNumber) ?? "—")
                metric("Value", value: maxValueUSD.map { "$" + formatNumber($0) } ?? usedValueUSD.map { "$" + formatNumber($0) } ?? "—")
            }
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(.quaternary.opacity(0.6))
            if showsWaveProgress, let usagePercentage {
                WaveProgressBackground(progress: min(max(usagePercentage, 0), 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

struct WaveProgressBackground: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * progress
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.20),
                                Color.cyan.opacity(0.14)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width)

                WaveShape(progressWidth: width, amplitude: 5, wavelength: 34)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: width)
            }
        }
        .allowsHitTesting(false)
    }
}

struct WaveShape: Shape {
    let progressWidth: CGFloat
    let amplitude: CGFloat
    let wavelength: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard progressWidth > 0 else { return path }

        let waveWidth = min(progressWidth, rect.width)
        let centerY = rect.midY
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: waveWidth, y: 0))
        path.addLine(to: CGPoint(x: waveWidth, y: centerY))

        stride(from: waveWidth, through: CGFloat(0), by: -2).forEach { x in
            let y = centerY + sin((x / wavelength) * .pi * 2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }

        path.addLine(to: CGPoint(x: 0, y: 0))
        path.closeSubpath()
        return path
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
            MenuHeaderView(apiService: apiService, settings: settings, data: apiService.subscriptionData)

            if let data = apiService.subscriptionData {
                if let quota5 = data.quota5Hour {
                    MenuQuotaView(title: "5 hour flows", window: quota5, timeZone: settings.timeZone)
                }
                if let quota7 = data.quota7Day {
                    MenuQuotaView(title: "7 day flows", window: quota7, timeZone: settings.timeZone)
                }
                if let monthly = data.quotaMonthly {
                    MenuQuotaView(title: "Monthly flows", monthly: monthly, timeZone: settings.timeZone)
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
                .padding(.top, 2)
            HStack(spacing: 8) {
                footerButton("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                footerButton("Settings", systemImage: "gearshape", action: onOpenSettings)
                Spacer(minLength: 12)
                footerButton("Quit", systemImage: "power", role: .destructive, action: onQuit)
            }
        }
        .padding(14)
        .frame(width: 360)
    }

    private func footerButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(role == .destructive ? Color.red.opacity(0.10) : Color.primary.opacity(0.07))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(role == .destructive ? Color.red.opacity(0.22) : Color.white.opacity(0.22), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .primary)
        .accessibilityLabel(title)
    }
}

struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    let onSaveAPIKey: (String) -> Void
    @State private var apiKeyInput: String = ""
    @State private var showKeySaved = false

    private static let managementPortalURL = URL(string: "https://zenmux.ai/platform/management")!

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            apiKeySection
            preferencesSection
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 500, height: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            apiKeyInput = settings.apiKey
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: zenmuxAppIcon())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Quotax")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Settings for your ZenMux quota monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var apiKeySection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Management API Key")
                            .font(.headline)
                        Text("Connect Quotax to your ZenMux subscription data.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Link("Get Key", destination: Self.managementPortalURL)
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 8) {
                    SecureField("Zenmux Management API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        onSaveAPIKey(apiKeyInput)
                        showKeySaved = true
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }

                if showKeySaved {
                    Label("API Key saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private var preferencesSection: some View {
        settingsCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Preferences")
                        .font(.headline)
                    Text("Tune update behavior and the menu bar display.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Auto refresh", isOn: $settings.alwaysRefresh)
                            .help("Keep quota data updated while Quotax is running.")

                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Refresh interval")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("How often Quotax requests fresh quota data.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            TextField("refresh_interval", value: $settings.refreshInterval, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 76)
                            Text("sec")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Toggle("Launch at login", isOn: $settings.launchAtLogin)

                    if let launchAtLoginError = settings.launchAtLoginError {
                        Label("Launch at login: \(launchAtLoginError)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    Picker("Status bar quota", selection: $settings.statusBarQuotaDisplayMode) {
                        ForEach(StatusBarQuotaDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Time zone", selection: $settings.timeZoneIdentifier) {
                        ForEach(SettingsManager.preferredTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                }
            }
        }
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 4)
    }
}
