import AppKit

final class EnhancementsViewController: NSViewController {
    private let settings: EnhancementSettings
    private var switches = [NSSwitch]()
    private let permissionStatus = NSGridView(views: ["窗口控制：", "屏幕录制：", "输入监控："].map {
        [DashboardStyle.textLabel($0, size: 12, color: .secondaryLabelColor), NSView()]
    })
    private let accessibilityButton = NSButton(title: "授权窗口控制", target: nil, action: nil)
    private let captureButton = NSButton(title: "授权缩略图", target: nil, action: nil)
    private let inputMonitoringButton = NSButton(title: "授权输入监控", target: nil, action: nil)
    private let displayStyle = NSPopUpButton()

    init(settings: EnhancementSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    override func loadView() {
        let descriptions = ["恢复已有窗口，全部关闭时才重新打开", "停留在应用图标上，选择该 App 的窗口", "再次点击前台窗口时将其最小化"]
        var rows = EnhancementFeature.allCases.enumerated().map { index, feature -> NSView in
            let toggle = NSSwitch()
            DashboardStyle.configure(toggle)
            toggle.tag = index
            toggle.target = self
            toggle.action = #selector(toggleFeature(_:))
            toggle.setAccessibilityLabel(feature.title)
            switches.append(toggle)
            return DashboardStyle.settingRow(title: feature.title, description: descriptions[index], control: toggle)
        }
        displayStyle.addItems(withTitles: DockDisplayStyle.allCases.map(\.title))
        displayStyle.target = self
        displayStyle.action = #selector(changeDisplayStyle)
        DashboardStyle.configure(displayStyle)
        rows.insert(DashboardStyle.settingRow(title: "Dock 显示方式", description: "仅缩略图模式需要屏幕录制权限", control: displayStyle), at: 2)
        permissionStatus.columnSpacing = 8
        permissionStatus.rowSpacing = 3
        permissionStatus.xPlacement = .leading
        permissionStatus.yPlacement = .center
        permissionStatus.column(at: 0).width = (0..<permissionStatus.numberOfRows).compactMap {
            permissionStatus.cell(atColumnIndex: 0, rowIndex: $0).contentView?.fittingSize.width
        }.max() ?? 0
        accessibilityButton.target = self
        accessibilityButton.action = #selector(requestAccessibility)
        accessibilityButton.toolTip = "系统设置的辅助功能权限；部分系统版本显示为设备控制和数据访问"
        captureButton.target = self
        captureButton.action = #selector(requestCapture)
        inputMonitoringButton.target = self
        inputMonitoringButton.action = #selector(requestInputMonitoring)
        inputMonitoringButton.toolTip = "仅增强自动模式需要，用于被动识别原生 Cmd+Tab"
        let refreshButton = NSButton(title: "刷新状态", target: self, action: #selector(refreshPermissions))
        for button in [accessibilityButton, captureButton, inputMonitoringButton, refreshButton] { DashboardStyle.configure(button) }
        let buttons = NSStackView(views: [accessibilityButton, captureButton, inputMonitoringButton, refreshButton])
        buttons.spacing = 8
        let permissions = NSStackView(views: [permissionStatus, buttons])
        permissions.orientation = .vertical
        permissions.alignment = .leading
        permissions.spacing = 10
        let note = DashboardStyle.textLabel("输入监控仅增强自动模式需要。标签不截屏；缩略图仅本机处理。暂停后 Dock 增强停止。", size: 12, color: .secondaryLabelColor)
        note.maximumNumberOfLines = 2
        note.lineBreakMode = .byWordWrapping
        let stack = NSStackView(views: [
            DashboardStyle.pageHeader("Dock 预览", subtitle: "管理窗口恢复、Dock 面板与相关权限。"),
            DashboardStyle.section("窗口与 Dock", content: DashboardStyle.group(rows)),
            DashboardStyle.section("授权状态", content: DashboardStyle.card(permissions)), note
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        view = DashboardStyle.contentView(stack)
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        for (index, toggle) in switches.enumerated() { toggle.state = settings.enabled(EnhancementFeature.allCases[index]) ? .on : .off }
        displayStyle.selectItem(at: DockDisplayStyle.allCases.firstIndex(of: settings.dockDisplayStyle) ?? 0)
        let accessibility = settings.accessibilityGranted ? "已授权" : "未授权，窗口增强暂不可用"
        let capture = settings.dockDisplayStyle == .titles ? "标签模式无需录屏" : (settings.screenCaptureGranted ? "已授权" : "未授权，显示图标和标题")
        let input = settings.inputMonitoringGranted ? "已授权" : "未授权，仅增强自动模式需要"
        for (index, text) in [accessibility, capture, input].enumerated() {
            let cell = permissionStatus.cell(atColumnIndex: 1, rowIndex: index)
            // NSGridCell leaves replaced views attached to the grid.
            cell.contentView?.removeFromSuperview()
            let status = statusView(text)
            let title = (permissionStatus.cell(atColumnIndex: 0, rowIndex: index).contentView as? NSTextField)?.stringValue ?? ""
            status.setAccessibilityLabel(title + text)
            cell.contentView = status
        }
        accessibilityButton.isEnabled = !settings.accessibilityGranted
        captureButton.isEnabled = settings.dockDisplayStyle == .thumbnails && !settings.screenCaptureGranted
        inputMonitoringButton.isEnabled = !settings.inputMonitoringGranted
    }

    private func statusView(_ text: String) -> NSView {
        guard text == "已授权",
              let image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: text) else {
            return DashboardStyle.textLabel(text, size: 12, color: .secondaryLabelColor)
        }
        let icon = NSImageView(image: image)
        icon.contentTintColor = .systemGreen
        icon.toolTip = text
        icon.setAccessibilityElement(true)
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 14), icon.heightAnchor.constraint(equalToConstant: 14)])
        return icon
    }

    @objc private func toggleFeature(_ sender: NSSwitch) {
        let feature = EnhancementFeature.allCases[sender.tag]
        let enabled = sender.state == .on
        settings.set(feature, enabled: enabled)
        if enabled, !settings.accessibilityGranted { settings.requestAccessibility() }
        if enabled, feature == .dockPreview, settings.dockDisplayStyle == .thumbnails { settings.requestScreenCapture() }
        refresh()
    }

    @objc private func changeDisplayStyle() {
        settings.setDisplayStyle(DockDisplayStyle.allCases[displayStyle.indexOfSelectedItem])
        if settings.enabled(.dockPreview), settings.dockDisplayStyle == .thumbnails { settings.requestScreenCapture() }
        refresh()
    }

    @objc private func requestCapture() {
        settings.requestScreenCapture()
        refresh()
    }

    @objc private func requestAccessibility() {
        settings.requestAccessibility()
        refresh()
    }

    @objc private func requestInputMonitoring() {
        settings.requestInputMonitoring()
        refresh()
    }

    @objc private func refreshPermissions() {
        settings.onChange()
        refresh()
    }
}
