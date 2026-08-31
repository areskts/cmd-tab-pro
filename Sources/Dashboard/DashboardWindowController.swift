import AppKit
import ServiceManagement

enum InterfaceTheme: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

final class DashboardWindowController: NSWindowController {
    private let dashboardViewController: DashboardViewController
    private var hasCentered = false

    init(statistics: SwitchStatisticsStore, isReopenEnabled: @escaping () -> Bool,
         setReopenEnabled: @escaping (Bool) -> Void, loginStatus: @escaping () -> SMAppService.Status,
         setLoginEnabled: @escaping (Bool) throws -> Void, interfaceTheme: @escaping () -> InterfaceTheme,
         setInterfaceTheme: @escaping (InterfaceTheme) -> Void) {
        dashboardViewController = DashboardViewController(
            statistics: statistics, isReopenEnabled: isReopenEnabled, setReopenEnabled: setReopenEnabled,
            loginStatus: loginStatus, setLoginEnabled: setLoginEnabled, interfaceTheme: interfaceTheme,
            setInterfaceTheme: setInterfaceTheme
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        super.init(window: window)
        window.contentViewController = dashboardViewController
        window.setContentSize(NSSize(width: 760, height: 720))
        window.title = "Cmd Tab Pro"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) { nil }

    func showDashboard() {
        dashboardViewController.refresh()
        if !hasCentered {
            window?.center()
            hasCentered = true
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func refresh() {
        dashboardViewController.refresh()
    }
}

private final class DashboardViewController: NSViewController {
    private let statistics: SwitchStatisticsStore
    private let isReopenEnabled: () -> Bool
    private let setReopenEnabled: (Bool) -> Void
    private let loginStatus: () -> SMAppService.Status
    private let setLoginEnabled: (Bool) throws -> Void
    private let interfaceTheme: () -> InterfaceTheme
    private let setInterfaceTheme: (InterfaceTheme) -> Void
    private let todayValue = DashboardViewController.valueLabel()
    private let weekValue = DashboardViewController.valueLabel()
    private let chartView = WeeklySwitchChartView()
    private let topAppsStack = NSStackView()
    private let reopenSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let loginDescription = DashboardViewController.textLabel("", size: 12, color: .secondaryLabelColor)
    private let themePopUp = NSPopUpButton()

    init(statistics: SwitchStatisticsStore, isReopenEnabled: @escaping () -> Bool,
         setReopenEnabled: @escaping (Bool) -> Void, loginStatus: @escaping () -> SMAppService.Status,
         setLoginEnabled: @escaping (Bool) throws -> Void, interfaceTheme: @escaping () -> InterfaceTheme,
         setInterfaceTheme: @escaping (InterfaceTheme) -> Void) {
        self.statistics = statistics
        self.isReopenEnabled = isReopenEnabled
        self.setReopenEnabled = setReopenEnabled
        self.loginStatus = loginStatus
        self.setLoginEnabled = setLoginEnabled
        self.interfaceTheme = interfaceTheme
        self.setInterfaceTheme = setInterfaceTheme
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .followsWindowActiveState
        view = background
        buildLayout(in: background)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(
            self, selector: #selector(statisticsChanged), name: .switchStatisticsDidChange, object: statistics
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
        let enabled = isReopenEnabled()
        reopenSwitch.state = enabled ? .on : .off
        updateLoginStatus(loginStatus())
        themePopUp.selectItem(at: InterfaceTheme.allCases.firstIndex(of: interfaceTheme()) ?? 0)
    }

    private func buildLayout(in background: NSView) {
        let content = NSStackView()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 28),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -28),
            content.topAnchor.constraint(equalTo: background.topAnchor, constant: 42),
            content.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -24)
        ])
        let header = makeHeader()
        let metrics = makeMetrics()
        let details = makeDetails()
        let settings = makeSettings()
        content.addArrangedSubview(header)
        content.addArrangedSubview(metrics)
        content.addArrangedSubview(details)
        content.addArrangedSubview(settings)
        NSLayoutConstraint.activate([
            header.widthAnchor.constraint(equalTo: content.widthAnchor),
            metrics.widthAnchor.constraint(equalTo: content.widthAnchor),
            metrics.heightAnchor.constraint(equalToConstant: 92),
            details.widthAnchor.constraint(equalTo: content.widthAnchor),
            details.heightAnchor.constraint(equalToConstant: 230),
            settings.widthAnchor.constraint(equalTo: content.widthAnchor),
            settings.heightAnchor.constraint(equalToConstant: 176)
        ])
    }

    private func makeHeader() -> NSView {
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
        icon.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 54), icon.heightAnchor.constraint(equalToConstant: 54)])
        let title = Self.textLabel("Cmd Tab Pro", size: 26, weight: .semibold)
        let subtitle = Self.textLabel("增强系统原生 Cmd+Tab 功能，让你切换应用更加丝滑！", size: 13, color: .secondaryLabelColor)
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 3
        let header = NSStackView(views: [icon, labels])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        return header
    }

    private func makeMetrics() -> NSView {
        let row = NSStackView(views: [metricCard(title: "今日切换", value: todayValue), metricCard(title: "近 7 天合计", value: weekValue)])
        row.orientation = .horizontal
        row.distribution = .fillEqually
        row.spacing = 14
        return row
    }

    private func makeDetails() -> NSView {
        chartView.translatesAutoresizingMaskIntoConstraints = false
        let chartContent = NSStackView(views: [Self.sectionTitle("近 7 天趋势"), chartView])
        chartContent.orientation = .vertical
        chartContent.alignment = .leading
        chartContent.spacing = 10
        chartView.widthAnchor.constraint(equalTo: chartContent.widthAnchor).isActive = true
        let appContent = NSStackView(views: [Self.sectionTitle("切换最多的 App"), topAppsStack])
        appContent.orientation = .vertical
        appContent.alignment = .leading
        appContent.spacing = 10
        topAppsStack.orientation = .vertical
        topAppsStack.alignment = .leading
        topAppsStack.spacing = 6
        topAppsStack.widthAnchor.constraint(equalTo: appContent.widthAnchor).isActive = true
        let chartCard = card(chartContent)
        let appCard = card(appContent)
        let row = NSStackView(views: [chartCard, appCard])
        row.orientation = .horizontal
        row.alignment = .top
        row.distribution = .fillEqually
        row.spacing = 14
        NSLayoutConstraint.activate([
            chartCard.heightAnchor.constraint(equalTo: row.heightAnchor),
            appCard.heightAnchor.constraint(equalTo: row.heightAnchor)
        ])
        return row
    }

    private func makeSettings() -> NSView {
        reopenSwitch.target = self
        reopenSwitch.action = #selector(toggleReopen)
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        themePopUp.addItems(withTitles: InterfaceTheme.allCases.map(\.title))
        themePopUp.target = self
        themePopUp.action = #selector(changeTheme)
        themePopUp.widthAnchor.constraint(equalToConstant: 112).isActive = true
        let reopenRow = settingRow(
            title: "自动唤回窗口", description: "切换到无窗口应用时，自动重新打开窗口", control: reopenSwitch
        )
        let loginRow = settingRow(title: "登录时启动", descriptionLabel: loginDescription, control: loginSwitch)
        let themeRow = settingRow(title: "界面主题", description: "选择跟随系统、浅色或深色外观", control: themePopUp)
        let stack = NSStackView(views: [Self.sectionTitle("设置"), reopenRow, loginRow, themeRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        reopenRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        loginRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        themeRow.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return card(stack)
    }

    private func metricCard(title: String, value: NSTextField) -> NSView {
        let stack = NSStackView(views: [Self.textLabel(title, size: 12, color: .secondaryLabelColor), value])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 3
        return card(stack)
    }

    private func card(_ content: NSView) -> NSView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .followsWindowActiveState
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ])
        return card
    }

    private func settingRow(title: String, description: String, control: NSView) -> NSView {
        settingRow(title: title, descriptionLabel: Self.textLabel(description, size: 12, color: .secondaryLabelColor), control: control)
    }

    private func settingRow(title: String, descriptionLabel: NSTextField, control: NSView) -> NSView {
        let labels = NSStackView(views: [Self.textLabel(title, size: 13, weight: .medium), descriptionLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labels, spacer, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    private func updateTopApps(_ apps: [AppSwitchSummary]) {
        for view in topAppsStack.arrangedSubviews {
            topAppsStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !apps.isEmpty else {
            topAppsStack.addArrangedSubview(Self.textLabel("开始切换应用后，这里会显示近 7 天 Top 5。", size: 12, color: .secondaryLabelColor))
            return
        }
        for (index, app) in apps.enumerated() {
            let rank = Self.textLabel("\(index + 1)", size: 11, color: .tertiaryLabelColor)
            rank.alignment = .right
            rank.widthAnchor.constraint(equalToConstant: 14).isActive = true
            let icon = NSImageView(image: applicationIcon(for: app.bundleIdentifier))
            icon.imageScaling = .scaleProportionallyUpOrDown
            NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 22), icon.heightAnchor.constraint(equalToConstant: 22)])
            let name = Self.textLabel(app.displayName, size: 12)
            name.lineBreakMode = .byTruncatingTail
            let count = Self.textLabel(app.count.formatted(), size: 12, weight: .medium, color: .secondaryLabelColor)
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

    private func updateLoginStatus(_ status: SMAppService.Status) {
        loginSwitch.state = status == .enabled ? .on : .off
        loginSwitch.isEnabled = true
        switch status {
        case .enabled: loginDescription.stringValue = "已启用"
        case .requiresApproval: loginDescription.stringValue = "需要在系统设置的登录项中允许"
        case .notFound: loginDescription.stringValue = "未启用"
        case .notRegistered: loginDescription.stringValue = "未启用"
        @unknown default: loginDescription.stringValue = "状态未知"
        }
    }

    @objc private func statisticsChanged() {
        refresh()
    }

    @objc private func toggleReopen() {
        setReopenEnabled(reopenSwitch.state == .on)
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            try setLoginEnabled(loginSwitch.state == .on)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法修改登录项"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refresh()
    }

    @objc private func changeTheme() {
        guard InterfaceTheme.allCases.indices.contains(themePopUp.indexOfSelectedItem) else { return }
        setInterfaceTheme(InterfaceTheme.allCases[themePopUp.indexOfSelectedItem])
        refresh()
    }

    private static func valueLabel() -> NSTextField {
        textLabel("0", size: 30, weight: .semibold)
    }

    private static func sectionTitle(_ text: String) -> NSTextField {
        textLabel(text, size: 13, weight: .semibold)
    }

    private static func textLabel(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                                  color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
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

    override var intrinsicContentSize: NSSize { NSSize(width: 300, height: 165) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !days.isEmpty else { return }
        let plot = bounds.insetBy(dx: 8, dy: 26)
        let slotWidth = plot.width / CGFloat(days.count)
        let maximum = max(days.map(\.count).max() ?? 0, 1)
        for (index, day) in days.enumerated() {
            let barWidth = min(26, slotWidth * 0.52)
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
        guard index != days.count - 1 else { return "今天" }
        return Self.dayFormatter.string(from: date)
    }

    private func draw(_ text: String, centeredAt centerX: CGFloat, y: CGFloat, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: color]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: centerX - size.width / 2, y: y), withAttributes: attributes)
    }
}
