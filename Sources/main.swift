import AppKit
import ApplicationServices
import CoreGraphics
import CoreServices
import Darwin
import ServiceManagement
import os

private let bundleIdentifier = "com.ares.cmd.tab"
private let logger = Logger(subsystem: bundleIdentifier, category: "reopen")
private let releasesURL = URL(string: "https://github.com/areskts/cmd-tab-pro/releases/latest")!

private func shouldShowDashboardOnLaunch(defaultLaunch: Bool?, event: NSAppleEventDescriptor?) -> Bool {
    guard defaultLaunch ?? true else { return false }
    guard let event, event.eventClass == kCoreEventClass, event.eventID == kAEOpenApplication else { return true }
    // Login-item launches carry their origin in the open-application Apple event.
    return event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue != keyAELaunchedAsLogInItem
}

private func runSelfTest() {
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("self-test failed: \(message)\n", stderr)
            exit(1)
        }
    }
    let launchEvent = NSAppleEventDescriptor.appleEvent(
        withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
        transactionID: AETransactionID(kAnyTransactionID)
    )
    expect(shouldShowDashboardOnLaunch(defaultLaunch: true, event: launchEvent),
           "manual launch should show dashboard")
    expect(shouldShowDashboardOnLaunch(defaultLaunch: nil, event: nil),
           "launch without metadata should show dashboard")
    expect(!shouldShowDashboardOnLaunch(defaultLaunch: false, event: launchEvent),
           "non-default launch must stay in background")
    launchEvent.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: keyAEPropData)
    expect(!shouldShowDashboardOnLaunch(defaultLaunch: true, event: launchEvent),
           "login-item launch must stay in background even when marked as default")
    expect(!shouldShowDashboardOnLaunch(defaultLaunch: nil, event: launchEvent),
           "login-item launch must stay in background without default-launch metadata")
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
    expect(shouldSkipFinderReopen(bundleIdentifier: "com.apple.finder", fromCmdTab: false),
           "desktop activation must not open a Finder window in compatible mode")
    expect(!shouldSkipFinderReopen(bundleIdentifier: "com.apple.finder", fromCmdTab: true),
           "Cmd+Tab must still allow windowless Finder to reopen")
    expect(!shouldSkipFinderReopen(bundleIdentifier: "com.example.app", fromCmdTab: false),
           "compatible mode must still allow other apps to reopen")
    expect(!shouldSkipFinderReopen(bundleIdentifier: "com.example.app", fromCmdTab: true),
           "automatic mode must still allow other apps to reopen")
    let hiddenWindow: [String: Any] = [
        kCGWindowOwnerPID as String: pid_t(7), kCGWindowLayer as String: 0,
        kCGWindowIsOnscreen as String: false,
        kCGWindowBounds as String: ["Width": CGFloat(100), "Height": CGFloat(100)]
    ]
    expect(isTopLevelWindow(hiddenWindow, processIdentifier: 7),
           "an existing off-screen window must prevent creating a duplicate window")
    var visibleWindow = hiddenWindow
    visibleWindow[kCGWindowIsOnscreen as String] = true
    expect(isTopLevelWindow(visibleWindow, processIdentifier: 7),
           "visible top-level windows must block duplicate reopen")
    visibleWindow[kCGWindowBounds as String] = ["Width": CGFloat(0), "Height": CGFloat(0)]
    expect(!isTopLevelWindow(visibleWindow, processIdentifier: 7), "zero-size placeholders are not ordinary windows")
    print("self-test passed")
}

private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statistics = SwitchStatisticsStore()
    private let access = WindowAccess()
    private let enhancements = EnhancementSettings()
    private lazy var controller = ReopenController(statistics: statistics, access: access, enhancements: enhancements)
    private lazy var dock = DockController(access: access, settings: enhancements) { [weak self] pid in
        self?.controller.suppressWindowAction(pid: pid)
    }
    private lazy var cachedAppIconOption = AppIconOption.current()
    private lazy var dashboard = DashboardWindowController(
        statistics: statistics,
        enhancements: enhancements,
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
        openReleases: { [weak self] in self?.openReleases() },
        reopenMode: { [weak self] in self?.controller.mode ?? .compatible },
        setReopenMode: { [weak self] mode in self?.setReopenMode(mode) },
        restoreDefaults: { [weak self] in self?.restoreDefaults() }
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
        enhancements.onChange = { [weak self] in self?.configureEnhancements() }
        controller.start()
        configureEnhancements()
        let defaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool
        let showDashboard = shouldShowDashboardOnLaunch(
            defaultLaunch: defaultLaunch, event: NSAppleEventManager.shared().currentAppleEvent
        )
        logger.info("launch showDashboard=\(showDashboard, privacy: .public)")
        if showDashboard { dashboard.showDashboard() }
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
        configureEnhancements()
        dashboard.refresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        dock.stop()
        controller.cancelPending()
    }

    private func configureEnhancements() {
        controller.cancelPending()
        let active = controller.isEnabled && EnhancementFeature.allCases.contains(where: enhancements.enabled)
        access.observeFocus(of: active ? NSWorkspace.shared.frontmostApplication : nil)
        dock.configure(active: controller.isEnabled)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        dashboard.showDashboard()
        return false
    }

    private func setReopenEnabled(_ enabled: Bool) {
        controller.setEnabled(enabled)
        configureEnhancements()
        refreshMenu()
        dashboard.refresh()
    }

    private func setReopenMode(_ mode: ReopenMode) {
        guard controller.setMode(mode) else {
            showError("无法启用增强自动模式", "请在系统设置的隐私与安全性中允许 Cmd Tab Pro 使用输入监控，然后再次选择增强自动模式。")
            dashboard.refresh()
            return
        }
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

    private func restoreDefaults() {
        setReopenEnabled(true)
        setMenuBarIconVisible(false)
        setInterfaceTheme(.system)
        dashboard.refresh()
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
            "Signing identity: \(CodeSignature(Bundle.main.bundleURL)?.identity ?? "unavailable")",
            "Window reopen: \(controller.isEnabled ? "enabled" : "paused")",
            "Reopen mode: \(controller.mode.rawValue)",
            "Window recovery: \(enhancements.enabled(.windowRecovery))",
            "Dock preview: \(enhancements.enabled(.dockPreview))",
            "Dock click minimize: \(enhancements.enabled(.dockClickMinimize))",
            "Accessibility: \(enhancements.accessibilityGranted)",
            "Dock observer: \(enhancements.dockObserverAvailable)",
            "Dock display style: \(enhancements.dockDisplayStyle.rawValue)",
            "Screen capture: \(enhancements.screenCaptureGranted)",
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
