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
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: zenmuxAppIcon())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(expText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)

            Spacer(minLength: 8)

            statusBadge
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Label(statusText, systemImage: statusIcon)
            .font(.caption2)
            .fontWeight(.semibold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(statusColor.opacity(0.12))
            }
            .accessibilityLabel("Status: \(statusText). \(statusDescription)")
            .help(statusDescription)
    }

    private var title: String {
        guard let data else { return "ZenMux" }
        return "ZenMux · \(data.primaryPlanName)"
    }

    private var expText: String {
        guard let expiresAt = data?.plan?.expiresAt else { return "Management API quota monitor" }
        return "Expires \(PanelTimeFormatter.format(isoString: expiresAt, timeZone: settings.timeZone))"
    }

    private var statusText: String {
        if apiService.isRefreshing { return "refreshing" }
        if apiService.isPaused { return "paused" }
        guard let rawStatus = data?.primaryStatus.trimmingCharacters(in: .whitespacesAndNewlines), !rawStatus.isEmpty else {
            return settings.trimmedAPIKey.isEmpty ? "setup" : "ready"
        }
        return rawStatus.lowercased()
    }

    private var statusDescription: String {
        guard let rawStatus = data?.primaryStatus.lowercased() else { return statusText }
        switch rawStatus {
        case "healthy": return "Normal"
        case "monitored": return "Usage anomaly detected; service remains available"
        case "abusive": return "Abusive usage detected; restrictions applied"
        case "suspended": return "Account suspended"
        case "banned": return "Account banned"
        default: return statusText
        }
    }

    private var statusIcon: String {
        if apiService.isRefreshing { return "arrow.triangle.2.circlepath" }
        if apiService.isPaused { return "pause.fill" }
        guard let rawStatus = data?.primaryStatus.lowercased() else {
            return settings.trimmedAPIKey.isEmpty ? "key.slash" : "bolt.fill"
        }

        switch rawStatus {
        case "healthy": return "checkmark.seal.fill"
        case "monitored": return "eye.fill"
        case "abusive": return "exclamationmark.triangle.fill"
        case "suspended": return "pause.octagon.fill"
        case "banned": return "xmark.octagon.fill"
        default: return "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        if apiService.isRefreshing { return Color.accentColor }
        if apiService.isPaused { return .orange }
        guard let rawStatus = data?.primaryStatus.lowercased() else {
            return settings.trimmedAPIKey.isEmpty ? .orange : Color.accentColor
        }

        switch rawStatus {
        case "healthy": return .green
        case "monitored": return .yellow
        case "abusive": return .orange
        case "suspended": return .red
        case "banned": return .red
        default: return .secondary
        }
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let resetText {
                    Text(resetText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(primaryLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(primaryValueText)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .layoutPriority(1)

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(secondaryLabel)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(secondaryValueText)
                        .font(.callout)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            if let progressValue {
                progressBar(progressValue)
            }

            HStack(spacing: 8) {
                metric("Used", value: usedFlows.map(formatNumber) ?? "—")
                metric("Left", value: remainingFlows.map(formatNumber) ?? "—")
                metric("Limit", value: maxFlows.map(formatNumber) ?? "—")
                metric("Value", value: valueText)
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
            if let progressValue {
                WaveProgressBackground(progress: progressValue)
                    .opacity(0.26)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var resetText: String? {
        guard let resetsAt, !resetsAt.isEmpty else { return nil }
        return "Resets \(PanelTimeFormatter.format(isoString: resetsAt, timeZone: timeZone))"
    }

    private var progressValue: Double? {
        guard showsWaveProgress, let usagePercentage else { return nil }
        return min(max(usagePercentage, 0), 1)
    }

    private var primaryLabel: String {
        progressValue == nil ? "Monthly limit" : "Usage"
    }

    private var primaryValueText: String {
        if let progressValue { return "\(Int((progressValue * 100).rounded()))%" }
        return maxFlows.map(formatNumber) ?? "—"
    }

    private var secondaryLabel: String {
        progressValue == nil ? "Value" : "Remaining"
    }

    private var secondaryValueText: String {
        if progressValue == nil { return valueText }
        return remainingFlows.map(formatNumber) ?? "—"
    }

    private var valueText: String {
        if let maxValueUSD { return "$" + formatNumber(maxValueUSD) }
        if let usedValueUSD { return "$" + formatNumber(usedValueUSD) }
        return "—"
    }

    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.12))
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.cyan.opacity(0.85)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geometry.size.width * progress))
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Usage \(primaryValueText)")
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
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
                    .fill(Color.primary.opacity(0.06))
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
                VStack(spacing: 8) {
                    if let quota5 = data.quota5Hour {
                        MenuQuotaView(title: "5 hour flows", window: quota5, timeZone: settings.timeZone)
                    }
                    if let quota7 = data.quota7Day {
                        MenuQuotaView(title: "7 day flows", window: quota7, timeZone: settings.timeZone)
                    }
                    if let monthly = data.quotaMonthly {
                        MenuQuotaView(title: "Monthly flows", monthly: monthly, timeZone: settings.timeZone)
                    }
                }
            } else {
                emptyState
            }

            if let error = apiService.lastError {
                errorBanner(error.localizedDescription)
            }

            footerToolbar
        }
        .padding(12)
        .frame(width: 380)
        .background(panelBackground)
        .foregroundStyle(Color.primary)
    }

    private var panelBackground: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [
                    Color.accentColor.opacity(0.18),
                    Color.cyan.opacity(0.08),
                    Color.primary.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.accentColor.opacity(0.16), .clear],
                center: .topLeading,
                startRadius: 12,
                endRadius: 260
            )
        }
    }

    private var headerUpdatedText: String? {
        guard !apiService.isPaused, let updated = apiService.lastUpdated else { return nil }
        return PanelTimeFormatter.relativeUpdatedText(since: updated)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: settings.trimmedAPIKey.isEmpty ? "key.slash" : "chart.bar.doc.horizontal")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background {
                    Circle().fill(Color.accentColor.opacity(0.12))
                }

            Text("No subscription data")
                .font(.headline)
            Text(settings.trimmedAPIKey.isEmpty ? "Set your Management API Key in Settings to load quota." : "Refresh to load the latest quota data.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
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
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var footerToolbar: some View {
        HStack(spacing: 8) {
            Button(action: onRefresh) {
                Image(systemName: apiService.isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.accentColor.opacity(0.18))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.20), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(apiService.isRefreshing ? "Refreshing" : "Refresh")

            if let updatedText = headerUpdatedText {
                Text(updatedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            footerButton("Settings", systemImage: "gearshape", action: onOpenSettings)
            footerButton("Quit", systemImage: "power", role: .destructive, action: onQuit)
        }
        .padding(.top, 2)
    }

    private func errorBanner(_ message: String) -> some View {
        Label {
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill")
        }
        .foregroundStyle(.red)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.red.opacity(0.10))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(0.20), lineWidth: 1)
        }
    }

    private func footerButton(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 32, height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(role == .destructive ? Color.red.opacity(0.12) : Color.primary.opacity(0.08))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(role == .destructive ? Color.red.opacity(0.30) : Color.primary.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? .red : .secondary)
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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    apiKeySection
                    behaviorSection
                    displaySection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 560, height: 640)
        .background {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .controlBackgroundColor).opacity(0.55)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .onAppear {
            apiKeyInput = settings.apiKey
            settings.refreshLaunchAtLoginStatus()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: zenmuxAppIcon())
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text("Quotax Settings")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text("Connect ZenMux, control refresh behavior, and tune the menu bar display.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .layoutPriority(0)

            Spacer(minLength: 16)

            statusPill
                .layoutPriority(1)
        }
    }

    private var statusPill: some View {
        Label(settings.trimmedAPIKey.isEmpty ? "Not connected" : "Connected", systemImage: settings.trimmedAPIKey.isEmpty ? "key.slash" : "checkmark.seal.fill")
            .font(.caption)
            .fontWeight(.semibold)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(settings.trimmedAPIKey.isEmpty ? Color.orange : Color.green)
            .frame(minWidth: 104, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule(style: .continuous)
                    .fill((settings.trimmedAPIKey.isEmpty ? Color.orange : Color.green).opacity(0.12))
            }
    }

    private var apiKeySection: some View {
        settingsCard(icon: "key.fill", title: "Management API", subtitle: "Used only to fetch your ZenMux quota and subscription data.") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    SecureField("Paste ZenMux Management API Key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)

                    Button("Save") {
                        onSaveAPIKey(apiKeyInput)
                        showKeySaved = !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if showKeySaved {
                        Label("API key saved. Quotax will refresh quota data automatically.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Your key is stored locally in macOS user defaults.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Link(destination: Self.managementPortalURL) {
                        Label("Get key", systemImage: "arrow.up.right")
                    }
                }
                .font(.caption)
            }
        }
    }

    private var behaviorSection: some View {
        settingsCard(icon: "arrow.triangle.2.circlepath", title: "Refresh behavior", subtitle: "Choose when Quotax updates subscription data.") {
            VStack(spacing: 0) {
                settingRow(
                    title: "Auto refresh",
                    subtitle: "Keep quota data updated while Quotax is running."
                ) {
                    Toggle("", isOn: $settings.alwaysRefresh)
                        .labelsHidden()
                        .accessibilityLabel("Auto refresh")
                        .help("Keep quota data updated while Quotax is running.")
                }

                rowDivider

                settingRow(
                    title: "Refresh interval",
                    subtitle: "How often Quotax requests fresh quota data."
                ) {
                    HStack(spacing: 6) {
                        TextField("refresh_interval", value: $settings.refreshInterval, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 82)
                        Text("sec")
                            .foregroundStyle(.secondary)
                    }
                }

                rowDivider

                settingRow(
                    title: "Launch at login",
                    subtitle: "Start Quotax automatically after you sign in."
                ) {
                    Toggle("", isOn: $settings.launchAtLogin)
                        .labelsHidden()
                        .accessibilityLabel("Launch at login")
                }

                if let launchAtLoginError = settings.launchAtLoginError {
                    Label("Launch at login: \(launchAtLoginError)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                }
            }
        }
    }

    private var displaySection: some View {
        settingsCard(icon: "menubar.rectangle", title: "Display", subtitle: "Decide how theme, quota, and time are shown in Quotax.") {
            VStack(spacing: 0) {
                settingRow(
                    title: "Theme",
                    subtitle: "Choose Auto to follow your macOS appearance."
                ) {
                    Picker("Theme", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Theme")
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                rowDivider

                settingRow(
                    title: "Status bar quota",
                    subtitle: "Switch between used and remaining quota percentages."
                ) {
                    Picker("Status bar quota", selection: $settings.statusBarQuotaDisplayMode) {
                        ForEach(StatusBarQuotaDisplayMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Status bar quota")
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                rowDivider

                settingRow(
                    title: "Time zone",
                    subtitle: "Used for expiration and quota reset times."
                ) {
                    Picker("Time zone", selection: $settings.timeZoneIdentifier) {
                        ForEach(SettingsManager.preferredTimeZoneIdentifiers, id: \.self) { identifier in
                            Text(identifier).tag(identifier)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Time zone")
                    .frame(minWidth: 280, idealWidth: 320)
                }
            }
        }
    }

    private var rowDivider: some View {
        Divider()
            .padding(.vertical, 12)
    }

    private func settingRow<Control: View>(title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)

            Spacer(minLength: 12)

            control()
                .frame(alignment: .trailing)
        }
    }

    private func settingsCard<Content: View>(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 30, height: 30)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
    }
}
