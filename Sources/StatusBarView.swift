import AppKit
import Combine

@MainActor
public final class StatusBarView: NSView {
    public var apiService: ZenmuxAPIService? {
        didSet { bindService() }
    }

    private var cancellables: Set<AnyCancellable> = []

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 104, height: NSStatusBar.system.thickness)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    private func bindService() {
        cancellables.removeAll()
        apiService?.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.needsDisplay = true }
        }.store(in: &cancellables)
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bounds = self.bounds
        if shouldDrawAppIcon {
            drawAppIcon(in: bounds)
            return
        }

        let text = statusText
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingTail

        let color: NSColor
        if apiService?.isPaused == true {
            color = .secondaryLabelColor
        } else if apiService?.lastError != nil {
            color = .systemRed
        } else {
            color = .labelColor
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let rect = NSRect(x: 0, y: (bounds.height - 16) / 2, width: bounds.width, height: 16)
        attributed.draw(in: rect)
    }

    private var shouldDrawAppIcon: Bool {
        guard let apiService else { return true }
        if apiService.isRefreshing { return false }
        if apiService.lastError?.type == .noAPIKey { return true }
        return apiService.subscriptionData?.quota5Hour?.remainingFlows == nil
    }

    private func drawAppIcon(in bounds: NSRect) {
        let image = zenmuxAppIcon()
        let side = min(bounds.height - 4, 18)
        let rect = NSRect(
            x: (bounds.width - side) / 2,
            y: (bounds.height - side) / 2,
            width: side,
            height: side
        )
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }

    private var statusText: String {
        guard let apiService else { return "" }
        if apiService.isRefreshing { return "Quotax …" }
        if apiService.isPaused { return "Quotax ⏸" }
        if apiService.lastError != nil { return "Quotax !" }
        if let remaining = apiService.subscriptionData?.quota5Hour?.remainingFlows {
            return "Q \(formatNumber(remaining))"
        }
        return ""
    }

    private func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = value >= 100 ? 0 : 1
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
