import AppKit

final class AboutViewController: NSViewController {
    private let statistics: SwitchStatisticsStore
    private let appIconOption: () -> AppIconOption
    private let diagnosticText: () -> String
    private let openReleases: () -> Void
    private let restoreDefaults: () -> Void
    private let iconView = NSImageView()
    private let clearButton = NSButton()

    init(statistics: SwitchStatisticsStore, appIconOption: @escaping () -> AppIconOption,
         diagnosticText: @escaping () -> String, openReleases: @escaping () -> Void, restoreDefaults: @escaping () -> Void) {
        self.statistics = statistics
        self.appIconOption = appIconOption
        self.diagnosticText = diagnosticText
        self.openReleases = openReleases
        self.restoreDefaults = restoreDefaults
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let stack = NSStackView(views: [
            DashboardStyle.section("关于", content: makeAboutCard()),
            DashboardStyle.section("工具", content: makeActionsCard())
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        view = DashboardStyle.contentView(stack)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
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
        if iconView.image == nil { iconView.image = appIconOption().image }
        refreshStatistics()
    }

    private func refreshStatistics() {
        clearButton.isEnabled = statistics.snapshot().sevenDayCount > 0
    }

    private func makeAboutCard() -> NSView {
        iconView.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([iconView.widthAnchor.constraint(equalToConstant: 76), iconView.heightAnchor.constraint(equalToConstant: 76)])
        let title = DashboardStyle.textLabel("Cmd Tab Pro", size: 22, weight: .semibold)
        let subtitle = DashboardStyle.textLabel(
            "增强系统原生 Cmd+Tab 功能，让应用切换更顺畅。", size: 13, color: .secondaryLabelColor
        )
        subtitle.maximumNumberOfLines = 2
        subtitle.lineBreakMode = .byWordWrapping
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let version = DashboardStyle.textLabel("版本 \(versionDescription())", size: 12, color: .secondaryLabelColor)
        let bundle = DashboardStyle.textLabel("Bundle ID：com.ares.cmd.tab", size: 12, color: .secondaryLabelColor)
        let labels = NSStackView(views: [title, subtitle, version, bundle])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [iconView, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 18
        return DashboardStyle.card(row)
    }

    private func makeActionsCard() -> NSView {
        let copyButton = NSButton(title: "复制诊断信息", target: self, action: #selector(copyDiagnostics))
        clearButton.title = "清除统计…"
        clearButton.target = self
        clearButton.action = #selector(clearStatistics)
        clearButton.contentTintColor = .systemRed
        let updateButton = NSButton(title: "检查更新…", target: self, action: #selector(checkForUpdates))
        let restoreButton = NSButton(title: "恢复默认设置…", target: self, action: #selector(restoreDefaultSettings))
        DashboardStyle.compact(copyButton)
        DashboardStyle.compact(clearButton)
        DashboardStyle.compact(updateButton)
        DashboardStyle.compact(restoreButton)
        let copy = DashboardStyle.settingRow(
            title: "诊断信息", description: "复制版本、系统和功能状态，不包含使用记录", control: copyButton
        )
        let clear = DashboardStyle.settingRow(
            title: "清除统计", description: "删除最近 7 天的应用切换统计", control: clearButton
        )
        let update = DashboardStyle.settingRow(
            title: "检查更新", description: "打开 GitHub Releases 查看最新版本", control: updateButton
        )
        let restore = DashboardStyle.settingRow(
            title: "恢复默认设置", description: "恢复自动唤回、菜单栏图标和界面主题", control: restoreButton
        )
        return DashboardStyle.group([copy, clear, update, restore])
    }

    @objc private func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(diagnosticText(), forType: .string) else {
            showError("无法复制诊断信息", "系统剪贴板当前不可用。")
            return
        }
    }

    @objc private func clearStatistics() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "清除统计数据？"
        alert.informativeText = "将删除最近 7 天的应用切换统计，此操作无法撤销。"
        alert.addButton(withTitle: "清除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        statistics.clear()
        refreshStatistics()
    }

    @objc private func checkForUpdates() {
        openReleases()
    }

    @objc private func restoreDefaultSettings() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "恢复默认设置？"
        alert.informativeText = "将恢复自动唤回、菜单栏图标和界面主题。统计数据、登录时启动和应用图标不会改变。"
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        restoreDefaults()
    }

    @objc private func applicationBecameActive() {
        refreshStatistics()
    }

    private func versionDescription() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "\(version) (\(build))"
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
