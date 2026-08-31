import AppKit
import Darwin
import ServiceManagement
import os

private let bundleIdentifier = "com.ares.cmd.tab"
private let managedBundleIdentifiers = [bundleIdentifier, "com.wujunjie.cmd-tab-pro", "com.wujunjie.cmd-tab-reopener"]
private let logger = Logger(subsystem: bundleIdentifier, category: "reopen")

private func shouldAttemptReopen(enabled: Bool, regular: Bool, terminated: Bool,
                                 ownProcess: Bool, frontmost: Bool, coolingDown: Bool) -> Bool {
    enabled && regular && !terminated && !ownProcess && frontmost && !coolingDown
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
    print("self-test passed")
}

private final class ReopenController {
    private let workspace = NSWorkspace.shared
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private var observer: NSObjectProtocol?
    private var cooldownUntil = [pid_t: TimeInterval]()
    var isEnabled = true

    func start() {
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationActivated(app)
        }
    }

    private func applicationActivated(_ app: NSRunningApplication) {
        guard isEnabled, app.activationPolicy == .regular,
              !app.isTerminated, app.processIdentifier != ownPid else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150)) { [weak self] in
            self?.reopenIfNeeded(app)
        }
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
            coolingDown: coolingDown
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
    private let controller = ReopenController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "启用", action: #selector(toggleEnabled), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "")
    private let hideMenuItem = NSMenuItem(title: "隐藏菜单栏图标…", action: #selector(hideStatusItem), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMenu()
        controller.start()
    }

    private func setupMenu() {
        let image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "Cmd Tab Pro")
        statusItem.button?.image = image?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        statusItem.button?.toolTip = "Cmd Tab Pro"
        enabledMenuItem.target = self
        loginMenuItem.target = self
        hideMenuItem.target = self
        menu.delegate = self
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        menu.addItem(enabledMenuItem)
        menu.addItem(loginMenuItem)
        menu.addItem(hideMenuItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        refreshMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        statusMenuItem.title = controller.isEnabled ? "状态：已启用" : "状态：已暂停"
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
        controller.isEnabled.toggle()
        refreshMenu()
    }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("无法修改登录项", error.localizedDescription)
        }
        refreshMenu()
    }

    @objc private func hideStatusItem() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "隐藏菜单栏图标？"
        alert.informativeText = "隐藏后，重新打开 Cmd Tab Pro 即可恢复图标。"
        alert.addButton(withTitle: "隐藏")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        statusItem.isVisible = false
        NSApp.hide(nil)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        statusItem.isVisible = true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // LSUIElement 的 reopen 行为因启动入口而异，激活与 reopen 两条路径都恢复控制入口。
        statusItem.isVisible = true
        return false
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
    let running = managedBundleIdentifiers.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }
        .filter { $0.processIdentifier != ownPid }
    let success = running.allSatisfy { $0.terminate() }
    exit(success ? 0 : 1)
}

let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
