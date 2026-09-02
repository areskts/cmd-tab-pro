import AppKit
import Darwin
import ServiceManagement
import os

private let bundleIdentifier = "com.ares.cmd.tab"
private let logger = Logger(subsystem: bundleIdentifier, category: "reopen")
private let releasesURL = URL(string: "https://github.com/areskts/cmd-tab-pro/releases/latest")!

private func shouldAttemptReopen(enabled: Bool, regular: Bool, terminated: Bool,
                                 ownProcess: Bool, frontmost: Bool, coolingDown: Bool,
                                 excluded: Bool = false) -> Bool {
    enabled && regular && !terminated && !ownProcess && frontmost && !coolingDown && !excluded
}

private func shouldShowDashboard(defaultLaunch: Bool?) -> Bool {
    defaultLaunch ?? true
}

private func runSelfTest() {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("self-test failed: \(message)\n", stderr)
            exit(1)
        }
    }
    let ready = (enabled: true, regular: true, terminated: false,
                 ownProcess: false, frontmost: true, coolingDown: false)
    expect(shouldAttemptReopen(enabled: ready.enabled, regular: ready.regular,
                               terminated: ready.terminated, ownProcess: ready.ownProcess,
                               frontmost: ready.frontmost, coolingDown: ready.coolingDown),
           "foreground app should receive reopen")
    expect(!shouldAttemptReopen(enabled: ready.enabled, regular: ready.regular,
                                terminated: ready.terminated, ownProcess: ready.ownProcess,
                                frontmost: false, coolingDown: ready.coolingDown),
           "background app must not reopen")
    expect(!shouldAttemptReopen(enabled: ready.enabled, regular: ready.regular,
                                terminated: ready.terminated, ownProcess: ready.ownProcess,
                                frontmost: ready.frontmost, coolingDown: true),
           "cooldown must prevent duplicate reopen")
    expect(!shouldAttemptReopen(enabled: ready.enabled, regular: ready.regular,
                                terminated: ready.terminated, ownProcess: ready.ownProcess,
                                frontmost: ready.frontmost, coolingDown: false, excluded: true),
           "excluded apps must not reopen")
    expect(shouldShowDashboard(defaultLaunch: true), "normal launch should show dashboard")
    expect(!shouldShowDashboard(defaultLaunch: false), "background launch must stay quiet")
    print("self-test passed")
}

private final class ReopenController {
    private let workspace = NSWorkspace.shared
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private let statistics: SwitchStatisticsStore
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?
    private var cooldownUntil = [pid_t: TimeInterval]()
    private var countedUntil = [pid_t: TimeInterval]()
    private(set) var isEnabled: Bool

    init(statistics: SwitchStatisticsStore, defaults: UserDefaults = .standard) {
        self.statistics = statistics
        self.defaults = defaults
        isEnabled = defaults.object(forKey: "reopenEnabled") as? Bool ?? true
    }

    func start() {
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationActivated(app)
        }
    }

    private func applicationActivated(_ app: NSRunningApplication) {
        guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != ownPid else { return }
        recordSwitch(app)
        guard isEnabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            self?.reopenIfNeeded(app)
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "reopenEnabled")
    }

    private func recordSwitch(_ app: NSRunningApplication) {
        let now = ProcessInfo.processInfo.systemUptime
        countedUntil = countedUntil.filter { $0.value > now }
        let pid = app.processIdentifier
        guard (countedUntil[pid] ?? 0) <= now else { return }
        countedUntil[pid] = now + 0.5
        let name = app.localizedName ?? "未知应用"
        statistics.record(bundleIdentifier: app.bundleIdentifier ?? "name:\(name)", displayName: name)
    }

    private func reopenIfNeeded(_ app: NSRunningApplication) {
        let now = ProcessInfo.processInfo.systemUptime
        cooldownUntil = cooldownUntil.filter { $0.value > now }
        let pid = app.processIdentifier
        let coolingDown = (cooldownUntil[pid] ?? 0) > now
        let frontmost = workspace.frontmostApplication?.processIdentifier == pid
        guard shouldAttemptReopen(
            enabled: isEnabled, regular: app.activationPolicy == .regular,
            terminated: app.isTerminated, ownProcess: pid == ownPid, frontmost: frontmost,
            coolingDown: coolingDown, excluded: app.bundleIdentifier == "com.apple.finder"
        ), let bundleURL = app.bundleURL else { return }
        cooldownUntil[pid] = now + 0.5
        do {
            // 2026-08-31 / macOS 26.5.2：现代 openApplication 和 /usr/bin/open 对已经前台的
            // 无窗口应用只返回成功，不投递 reopen；这个旧入口会投递，AltTab 也依赖同一路径。
            _ = try workspace.launchApplication(at: bundleURL, configuration: [:])
            logger.info("reopen requested pid=\(pid, privacy: .public)")
        } catch {
            logger.error("reopen failed pid=\(pid, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statistics = SwitchStatisticsStore()
    private lazy var controller = ReopenController(statistics: statistics)
    private lazy var cachedAppIconOption = AppIconOption.current()
    private lazy var dashboard = DashboardWindowController(
        statistics: statistics,
        isReopenEnabled: { [weak self] in self?.controller.isEnabled ?? false },
        setReopenEnabled: { [weak self] enabled in self?.setReopenEnabled(enabled) },
        loginStatus: { SMAppService.mainApp.status },
        setLoginEnabled: { [weak self] enabled in try self?.setLoginEnabled(enabled) },
        interfaceTheme: { [weak self] in self?.interfaceTheme() ?? .system },
        setInterfaceTheme: { [weak self] theme in self?.setInterfaceTheme(theme) },
        menuBarIconVisible: { [weak self] in self?.menuBarIconVisible() ?? false },
        setMenuBarIconVisible: { [weak self] visible in self?.setMenuBarIconVisible(visible) },
        appIconOption: { [weak self] in self?.currentAppIconOption() ?? .option2 },
        setAppIconOption: { [weak self] option in self?.setAppIconOption(option) },
        diagnosticText: { [weak self] in self?.diagnosticText() ?? "" },
        openReleases: { [weak self] in self?.openReleases() }
    )
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let openMenuItem = NSMenuItem(title: "打开应用", action: #selector(openDashboard), keyEquivalent: ",")
    private let aboutMenuItem = NSMenuItem(title: "关于 Cmd Tab Pro…", action: #selector(openAbout), keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "自动唤回窗口", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let hideMenuItem = NSMenuItem(title: "隐藏菜单栏图标…", action: #selector(hideStatusItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        applyInterfaceTheme(interfaceTheme())
        setupMainMenu()
        setupMenu()
        statusItem.isVisible = menuBarIconVisible()
        controller.start()
        let defaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        logger.info("launch default=\(defaultLaunch ?? true, privacy: .public)")
        if shouldShowDashboard(defaultLaunch: defaultLaunch) { dashboard.showDashboard() }
        showPendingIconSwitchError()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem(title: "Cmd Tab Pro", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Cmd Tab Pro")
        let quit = NSMenuItem(title: "退出 Cmd Tab Pro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        let windowMenuItem = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        let windowMenu = NSMenu(title: "窗口")
        windowMenu.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)
        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private func setupMenu() {
        let image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Cmd Tab Pro")
        statusItem.button?.image = image?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        statusItem.button?.toolTip = "Cmd Tab Pro"
        openMenuItem.target = self
        aboutMenuItem.target = self
        enabledMenuItem.target = self
        loginMenuItem.target = self
        hideMenuItem.target = self
        menu.delegate = self
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(openMenuItem)
        menu.addItem(.separator())
        menu.addItem(enabledMenuItem)
        menu.addItem(loginMenuItem)
        menu.addItem(hideMenuItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.addItem(.separator())
        menu.addItem(aboutMenuItem)
        statusItem.menu = menu
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        statusMenuItem.title = controller.isEnabled ? "窗口唤回：已开启" : "窗口唤回：已暂停"
        statusMenuItem.image = NSImage(
            systemSymbolName: controller.isEnabled ? "checkmark.circle.fill" : "pause.circle",
            accessibilityDescription: statusMenuItem.title
        )
        statusItem.button?.alphaValue = controller.isEnabled ? 1 : 0.45
        enabledMenuItem.state = controller.isEnabled ? .on : .off
        let loginStatus = SMAppService.mainApp.status
        loginMenuItem.state = loginStatus == .enabled ? .on : .off
        loginMenuItem.title = loginStatus == .requiresApproval ? "登录时启动（需要系统确认）" : "登录时启动"
    }

    @objc private func toggleEnabled() {
        setReopenEnabled(!controller.isEnabled)
    }

    @objc private func toggleLoginItem() {
        do {
            try setLoginEnabled(SMAppService.mainApp.status != .enabled)
        } catch {
            showError("无法修改登录项", error.localizedDescription)
        }
    }

    @objc private func openDashboard() {
        dashboard.showDashboard()
    }

    @objc private func openAbout() {
        dashboard.showAbout()
    }

    @objc private func hideStatusItem() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "隐藏菜单栏图标？"
        alert.informativeText = "隐藏后，可重新打开 CmdTabPro.app 进入主页面并再次开启。"
        alert.addButton(withTitle: "隐藏")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        setMenuBarIconVisible(false)
        NSApp.hide(nil)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusItem.isVisible = menuBarIconVisible()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // LSUIElement 的 reopen 行为因启动入口而异，激活与 reopen 两条路径都恢复控制入口。
        dashboard.showDashboard()
        return false
    }

    private func setReopenEnabled(_ enabled: Bool) {
        controller.setEnabled(enabled)
        refreshMenu()
        dashboard.refresh()
    }

    private func setLoginEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            } else if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
        refreshMenu()
        dashboard.refresh()
    }

    private func interfaceTheme() -> InterfaceTheme {
        guard let value = UserDefaults.standard.string(forKey: "interfaceTheme") else { return .system }
        return InterfaceTheme(rawValue: value) ?? .system
    }

    private func setInterfaceTheme(_ theme: InterfaceTheme) {
        UserDefaults.standard.set(theme.rawValue, forKey: "interfaceTheme")
        applyInterfaceTheme(theme)
    }

    private func applyInterfaceTheme(_ theme: InterfaceTheme) {
        NSApp.appearance = theme.appearance
    }

    private func menuBarIconVisible() -> Bool {
        guard UserDefaults.standard.object(forKey: "menuBarIconVisible") != nil else { return false }
        return UserDefaults.standard.bool(forKey: "menuBarIconVisible")
    }

    private func setMenuBarIconVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: "menuBarIconVisible")
        statusItem.isVisible = visible
        dashboard.refresh()
    }

    private func currentAppIconOption() -> AppIconOption {
        cachedAppIconOption
    }

    private func setAppIconOption(_ option: AppIconOption) {
        guard let sourceIcon = option.resourceURL else {
            showError("无法切换应用图标", "图标资源不存在。")
            return
        }
        let destinationIcon = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let appParent = Bundle.main.bundleURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: destinationIcon.path),
              FileManager.default.isWritableFile(atPath: appParent.path) else {
            showError("无法切换应用图标", "CmdTabPro.app 当前不可写，请确认它位于可写的 Applications 目录。")
            return
        }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/CmdTabProIconSwitcher")
        let temporaryHelper = FileManager.default.temporaryDirectory
            .appendingPathComponent("CmdTabProIconSwitcher-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: helper, to: temporaryHelper)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporaryHelper.path)
            let process = Process()
            process.executableURL = temporaryHelper
            process.arguments = [
                String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath,
                sourceIcon.path, option.rawValue
            ]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: temporaryHelper)
            showError("无法切换应用图标", error.localizedDescription)
        }
    }

    private func showPendingIconSwitchError() {
        guard let message = UserDefaults.standard.string(forKey: "appIconSwitchError") else { return }
        UserDefaults.standard.removeObject(forKey: "appIconSwitchError")
        DispatchQueue.main.async { [weak self] in self?.showError("应用图标切换失败", message) }
    }

    private func diagnosticText() -> String {
        [
            "Cmd Tab Pro \(versionDescription())",
            ProcessInfo.processInfo.operatingSystemVersionString,
            "Architecture: arm64",
            "Bundle ID: \(bundleIdentifier)",
            "Window reopen: \(controller.isEnabled ? "enabled" : "paused")",
            "Launch at login: \(loginStatusDescription(SMAppService.mainApp.status))",
            "Menu bar icon: \(menuBarIconVisible() ? "visible" : "hidden")",
            "Interface theme: \(interfaceTheme().rawValue)",
            "App icon: \(currentAppIconOption().rawValue)"
        ].joined(separator: "\n")
    }

    private func versionDescription() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "未知"
        return "\(version) (\(build))"
    }

    private func loginStatusDescription(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: return "enabled"
        case .requiresApproval: return "requires approval"
        case .notFound: return "not found"
        case .notRegistered: return "disabled"
        @unknown default: return "unknown"
        }
    }

    private func openReleases() {
        guard NSWorkspace.shared.open(releasesURL) else {
            showError("无法打开下载页面", releasesURL.absoluteString)
            return
        }
    }

    private func showError(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

if CommandLine.arguments.contains("--self-test") {
    runSelfTest()
    exit(0)
}
if CommandLine.arguments.contains("--terminate-running") {
    let ownPid = ProcessInfo.processInfo.processIdentifier
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        .filter { $0.processIdentifier != ownPid }
    let success = running.allSatisfy { $0.terminate() }
    exit(success ? 0 : 1)
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
