import AppKit
import ServiceManagement

final class GeneralViewController: NSViewController {
    private let isReopenEnabled: () -> Bool
    private let setReopenEnabled: (Bool) -> Void
    private let loginStatus: () -> SMAppService.Status
    private let setLoginEnabled: (Bool) throws -> Void
    private let interfaceTheme: () -> InterfaceTheme
    private let setInterfaceTheme: (InterfaceTheme) -> Void
    private let menuBarIconVisible: () -> Bool
    private let setMenuBarIconVisible: (Bool) -> Void
    private let appIconOption: () -> AppIconOption
    private let setAppIconOption: (AppIconOption) -> Void
    private let reopenMode: () -> ReopenMode
    private let setReopenMode: (ReopenMode) -> Void
    private let reopenSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let loginDescription = DashboardStyle.textLabel("", size: 12, color: .secondaryLabelColor)
    private let reopenModeDescription = DashboardStyle.textLabel("", size: 12, color: .secondaryLabelColor)
    private let reopenModePopUp = NSPopUpButton()
    private let themePopUp = NSPopUpButton()
    private let menuBarSwitch = NSSwitch()
    private var iconButtons = [NSButton]()

    init(isReopenEnabled: @escaping () -> Bool, setReopenEnabled: @escaping (Bool) -> Void,
         loginStatus: @escaping () -> SMAppService.Status, setLoginEnabled: @escaping (Bool) throws -> Void,
         interfaceTheme: @escaping () -> InterfaceTheme, setInterfaceTheme: @escaping (InterfaceTheme) -> Void,
         menuBarIconVisible: @escaping () -> Bool, setMenuBarIconVisible: @escaping (Bool) -> Void,
         appIconOption: @escaping () -> AppIconOption, setAppIconOption: @escaping (AppIconOption) -> Void,
         reopenMode: @escaping () -> ReopenMode, setReopenMode: @escaping (ReopenMode) -> Void) {
        self.isReopenEnabled = isReopenEnabled
        self.setReopenEnabled = setReopenEnabled
        self.loginStatus = loginStatus
        self.setLoginEnabled = setLoginEnabled
        self.interfaceTheme = interfaceTheme
        self.setInterfaceTheme = setInterfaceTheme
        self.menuBarIconVisible = menuBarIconVisible
        self.setMenuBarIconVisible = setMenuBarIconVisible
        self.appIconOption = appIconOption
        self.setAppIconOption = setAppIconOption
        self.reopenMode = reopenMode
        self.setReopenMode = setReopenMode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    override func loadView() {
        configureControls()
        let stack = NSStackView(views: [
            DashboardStyle.pageHeader("切换设置", subtitle: "设置窗口唤回、启动方式与应用外观。"),
            DashboardStyle.section("启动", content: makeStartupCard()),
            DashboardStyle.section("外观", content: makeAppearanceCard())
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        for item in stack.arrangedSubviews { item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        view = DashboardStyle.contentView(stack)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        refresh()
    }

    func refresh() {
        guard isViewLoaded else { return }
        reopenSwitch.state = isReopenEnabled() ? .on : .off
        let selectedMode = reopenMode()
        reopenModePopUp.selectItem(at: ReopenMode.allCases.firstIndex(of: selectedMode) ?? 0)
        reopenModeDescription.stringValue = selectedMode.description
        updateLoginStatus(loginStatus())
        themePopUp.selectItem(at: InterfaceTheme.allCases.firstIndex(of: interfaceTheme()) ?? 0)
        menuBarSwitch.state = menuBarIconVisible() ? .on : .off
        let selected = appIconOption()
        for button in iconButtons {
            let isSelected = AppIconOption.allCases[button.tag] == selected
            button.state = isSelected ? .on : .off
            button.layer?.borderWidth = isSelected ? 2 : 0
            button.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    private func configureControls() {
        DashboardStyle.configure(reopenSwitch)
        DashboardStyle.configure(loginSwitch)
        DashboardStyle.configure(reopenModePopUp)
        DashboardStyle.configure(themePopUp)
        DashboardStyle.configure(menuBarSwitch)
        reopenSwitch.target = self
        reopenSwitch.action = #selector(toggleReopen)
        reopenModePopUp.addItems(withTitles: ReopenMode.allCases.map(\.title))
        reopenModePopUp.target = self
        reopenModePopUp.action = #selector(changeReopenMode)
        reopenModePopUp.widthAnchor.constraint(equalToConstant: 160).isActive = true
        loginSwitch.target = self
        loginSwitch.action = #selector(toggleLogin)
        themePopUp.addItems(withTitles: InterfaceTheme.allCases.map(\.title))
        themePopUp.target = self
        themePopUp.action = #selector(changeTheme)
        themePopUp.widthAnchor.constraint(equalToConstant: 140).isActive = true
        menuBarSwitch.target = self
        menuBarSwitch.action = #selector(toggleMenuBarIcon)
    }

    private func makeStartupCard() -> NSView {
        let reopen = DashboardStyle.settingRow(
            title: "自动唤回窗口", description: "切换到无窗口应用时，自动重新打开窗口", control: reopenSwitch
        )
        let mode = DashboardStyle.settingRow(title: "唤回模式", descriptionLabel: reopenModeDescription, control: reopenModePopUp)
        let login = DashboardStyle.settingRow(title: "开机自启动", descriptionLabel: loginDescription, control: loginSwitch)
        return DashboardStyle.group([reopen, mode, login])
    }

    private func makeAppearanceCard() -> NSView {
        let theme = DashboardStyle.settingRow(
            title: "界面主题", description: "选择跟随系统、浅色或深色外观", control: themePopUp
        )
        let menuBar = DashboardStyle.settingRow(
            title: "显示菜单栏图标", description: "关闭后仍可重新打开 App 进入主页面", control: menuBarSwitch
        )
        let iconRow = NSStackView(views: AppIconOption.allCases.enumerated().map(makeIconButton))
        iconRow.orientation = .horizontal
        iconRow.alignment = .centerY
        iconRow.spacing = 12
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let icons = NSStackView(views: [DashboardStyle.textLabel("应用图标", size: 14, weight: .medium), spacer, iconRow])
        icons.orientation = .horizontal
        icons.alignment = .centerY
        return DashboardStyle.group([theme, menuBar, icons])
    }

    private func makeIconButton(index: Int, option: AppIconOption) -> NSButton {
        let button = NSButton(image: option.image, target: self, action: #selector(changeAppIcon(_:)))
        button.tag = index
        button.toolTip = option.title
        button.setAccessibilityLabel(option.title)
        button.setButtonType(.toggle)
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 12
        button.imageScaling = .scaleProportionallyUpOrDown
        NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: 52), button.heightAnchor.constraint(equalToConstant: 52)])
        iconButtons.append(button)
        return button
    }

    private func updateLoginStatus(_ status: SMAppService.Status) {
        loginSwitch.state = status == .enabled ? .on : .off
        loginSwitch.isEnabled = true
        switch status {
        case .enabled: loginDescription.stringValue = "已启用"
        case .requiresApproval: loginDescription.stringValue = "需要在系统设置的登录项中允许"
        case .notFound, .notRegistered: loginDescription.stringValue = "未启用"
        @unknown default: loginDescription.stringValue = "状态未知"
        }
    }

    @objc private func toggleReopen() {
        setReopenEnabled(reopenSwitch.state == .on)
        refresh()
    }

    @objc private func changeReopenMode() {
        guard ReopenMode.allCases.indices.contains(reopenModePopUp.indexOfSelectedItem) else { return }
        setReopenMode(ReopenMode.allCases[reopenModePopUp.indexOfSelectedItem])
        refresh()
    }

    @objc private func toggleLogin() {
        do {
            try setLoginEnabled(loginSwitch.state == .on)
        } catch {
            showError("无法修改登录项", error.localizedDescription)
        }
        refresh()
    }

    @objc private func changeTheme() {
        guard InterfaceTheme.allCases.indices.contains(themePopUp.indexOfSelectedItem) else { return }
        setInterfaceTheme(InterfaceTheme.allCases[themePopUp.indexOfSelectedItem])
        refresh()
    }

    @objc private func toggleMenuBarIcon() {
        setMenuBarIconVisible(menuBarSwitch.state == .on)
        refresh()
    }

    @objc private func changeAppIcon(_ sender: NSButton) {
        guard AppIconOption.allCases.indices.contains(sender.tag) else { return }
        let option = AppIconOption.allCases[sender.tag]
        guard option != appIconOption() else { refresh(); return }
        let alert = NSAlert()
        alert.messageText = "切换应用图标？"
        alert.informativeText = "Cmd Tab Pro 将重新签名并重启。"
        alert.addButton(withTitle: "切换")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { refresh(); return }
        setAppIconOption(option)
    }

    private func showError(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
