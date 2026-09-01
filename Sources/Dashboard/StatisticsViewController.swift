import AppKit

final class StatisticsViewController: NSViewController {
    private let statistics: SwitchStatisticsStore
    private let todayValue = valueLabel()
    private let weekValue = valueLabel()
    private let chartView = WeeklySwitchChartView()
    private let topAppsStack = NSStackView()

    init(statistics: SwitchStatisticsStore) {
        self.statistics = statistics
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let metrics = makeMetrics()
        let chart = DashboardStyle.section("近 7 天趋势", content: makeChart())
        let ranking = DashboardStyle.section("切换 App 排行", content: makeRanking())
        let stack = NSStackView(views: [metrics, chart, ranking])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        metrics.heightAnchor.constraint(equalToConstant: 70).isActive = true
        chart.heightAnchor.constraint(equalToConstant: 158).isActive = true
        ranking.heightAnchor.constraint(equalToConstant: 164).isActive = true
        view = DashboardStyle.contentView(stack)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(statisticsChanged), name: .switchStatisticsDidChange, object: statistics
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(applicationBecameActive), name: NSApplication.didBecomeActiveNotification, object: nil
        )
        refresh()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func refresh() {
        guard isViewLoaded else { return }
        let snapshot = statistics.snapshot()
        todayValue.stringValue = snapshot.todayCount.formatted()
        weekValue.stringValue = snapshot.sevenDayCount.formatted()
        chartView.days = snapshot.days
        updateTopApps(snapshot.topApps)
    }

    private func makeMetrics() -> NSView {
        let row = NSStackView(views: [
            metricCard(title: "今日切换", value: todayValue),
            metricCard(title: "近 7 天合计", value: weekValue)
        ])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 12
        return row
    }

    private func makeChart() -> NSView {
        chartView.translatesAutoresizingMaskIntoConstraints = false
        return DashboardStyle.card(chartView)
    }

    private func makeRanking() -> NSView {
        topAppsStack.orientation = .vertical
        topAppsStack.alignment = .leading
        topAppsStack.spacing = 4
        return DashboardStyle.card(topAppsStack)
    }

    private func metricCard(title: String, value: NSTextField) -> NSView {
        let stack = NSStackView(views: [DashboardStyle.textLabel(title, size: 12, color: .secondaryLabelColor), value])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return DashboardStyle.card(stack)
    }

    private func updateTopApps(_ apps: [AppSwitchSummary]) {
        for view in topAppsStack.arrangedSubviews {
            topAppsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !apps.isEmpty else {
            topAppsStack.addArrangedSubview(
                DashboardStyle.textLabel("开始切换应用后，这里会显示近 7 天 Top 5。", size: 12, color: .secondaryLabelColor)
            )
            return
        }
        for (index, app) in apps.enumerated() {
            let rank = DashboardStyle.textLabel("\(index + 1)", size: 11, color: .tertiaryLabelColor)
            rank.alignment = .right
            rank.widthAnchor.constraint(equalToConstant: 14).isActive = true
            let icon = NSImageView(image: applicationIcon(for: app.bundleIdentifier))
            icon.imageScaling = .scaleProportionallyUpOrDown
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 20), icon.heightAnchor.constraint(equalToConstant: 20)])
            let name = DashboardStyle.textLabel(app.displayName, size: 12)
            name.lineBreakMode = .byTruncatingTail
            let count = DashboardStyle.textLabel(app.count.formatted(), size: 12, weight: .medium, color: .secondaryLabelColor)
            count.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            count.alignment = .right
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [rank, icon, name, spacer, count])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 7
            topAppsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: topAppsStack.widthAnchor).isActive = true
        }
    }

    private func applicationIcon(for bundleIdentifier: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    @objc private func statisticsChanged() {
        guard NSApp.isActive else { return }
        refresh()
    }

    @objc private func applicationBecameActive() {
        refresh()
    }

    private static func valueLabel() -> NSTextField {
        let label = DashboardStyle.textLabel("0", size: 24, weight: .semibold)
        label.font = .monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        return label
    }
}

private final class WeeklySwitchChartView: NSView {
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
    var days = [DailySwitchSummary]() { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 110) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !days.isEmpty else { return }
        let plot = bounds.insetBy(dx: 8, dy: 26)
        let slotWidth = plot.width / CGFloat(days.count)
        let maximum = max(days.map(\.count).max() ?? 0, 1)
        for (index, day) in days.enumerated() {
            let barWidth = min(24, slotWidth * 0.5)
            let barHeight = max(3, plot.height * CGFloat(day.count) / CGFloat(maximum))
            let x = plot.minX + slotWidth * CGFloat(index) + (slotWidth - barWidth) / 2
            let bar = NSRect(x: x, y: plot.minY, width: barWidth, height: barHeight)
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bar, xRadius: 5, yRadius: 5).fill()
            draw(dayLabel(for: day.date, index: index), centeredAt: x + barWidth / 2, y: 4, color: .secondaryLabelColor)
            if day.count > 0 {
                draw(day.count.formatted(), centeredAt: x + barWidth / 2, y: min(bar.maxY + 4, bounds.maxY - 16), color: .secondaryLabelColor)
            }
        }
    }

    private func dayLabel(for date: Date, index: Int) -> String {
        index == days.count - 1 ? "今天" : Self.dayFormatter.string(from: date)
    }

    private func draw(_ text: String, centeredAt centerX: CGFloat, y: CGFloat, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: color
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: centerX - size.width / 2, y: y), withAttributes: attributes)
    }
}
