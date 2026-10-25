import AppKit
import ApplicationServices
import os

private let logger = Logger(subsystem: "com.ares.cmd.tab", category: "reopen")

func shouldAttemptReopen(enabled: Bool, regular: Bool, terminated: Bool,
                                 ownProcess: Bool, frontmost: Bool, coolingDown: Bool,
                                 excluded: Bool = false) -> Bool {
    enabled && regular && !terminated && !ownProcess && frontmost && !coolingDown && !excluded
}

func shouldSkipFinderReopen(bundleIdentifier: String?, fromCmdTab: Bool) -> Bool {
    // Desktop clicks activate Finder too; activation alone cannot justify opening a window.
    bundleIdentifier == "com.apple.finder" && !fromCmdTab
}

func isTopLevelWindow(_ window: [String: Any], processIdentifier: pid_t) -> Bool {
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t, ownerPID == processIdentifier,
          (window[kCGWindowLayer as String] as? Int) == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? CGFloat, let height = bounds["Height"] as? CGFloat else { return false }
    return width > 0 && height > 0
}

private func hasTopLevelWindow(for processIdentifier: pid_t) -> Bool? {
    guard let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    return windows.contains { window in
        isTopLevelWindow(window, processIdentifier: processIdentifier)
    }
}

final class ReopenController {
    private let workspace = NSWorkspace.shared
    private let ownPid = ProcessInfo.processInfo.processIdentifier
    private let statistics: SwitchStatisticsStore
    private let defaults: UserDefaults
    private let access: WindowAccess
    private let enhancements: EnhancementSettings
    private var observer: NSObjectProtocol?
    private var cooldownUntil = [pid_t: TimeInterval]()
    private var countedUntil = [pid_t: TimeInterval]()
    private var generation = 0
    private var pending: DispatchWorkItem?
    private var pendingPID: pid_t?
    private lazy var cmdTabMonitor = CmdTabMonitor(
        onCompleted: { [weak self] in self?.cmdTabCompleted() },
        onInterrupted: { [weak self] in self?.cancelPending() }
    )
    private(set) var isEnabled: Bool
    private(set) var mode: ReopenMode

    init(statistics: SwitchStatisticsStore, access: WindowAccess, enhancements: EnhancementSettings,
         defaults: UserDefaults = .standard) {
        self.statistics = statistics
        self.defaults = defaults
        self.access = access
        self.enhancements = enhancements
        isEnabled = defaults.object(forKey: "reopenEnabled") as? Bool ?? true
        mode = ReopenMode(rawValue: defaults.string(forKey: "reopenMode") ?? ReopenMode.automatic.rawValue) ?? .automatic
    }

    func start() {
        observer = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.applicationActivated(app)
        }
        guard isEnabled, mode == .automatic else { return }
        if cmdTabMonitor.start() {
            logger.info("automatic mode active")
        } else {
            logger.error("automatic mode unavailable: input monitoring permission is missing")
            mode = .compatible
            defaults.set(mode.rawValue, forKey: "reopenMode")
        }
    }

    func applicationActivated(_ app: NSRunningApplication) {
        if isEnabled && EnhancementFeature.allCases.contains(where: enhancements.enabled) {
            access.observeFocus(of: app)
        }
        if let pendingPID, pendingPID != app.processIdentifier { cancelPending() }
        guard app.activationPolicy == .regular, !app.isTerminated, app.processIdentifier != ownPid else { return }
        recordSwitch(app)
        guard isEnabled, mode == .compatible else { return }
        schedule(app, fromCmdTab: false)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        defaults.set(enabled, forKey: "reopenEnabled")
        cancelPending()
        if !enabled {
            cmdTabMonitor.stop()
        } else if mode == .automatic, !cmdTabMonitor.start() {
            mode = .compatible
            defaults.set(mode.rawValue, forKey: "reopenMode")
        }
    }

    func setMode(_ mode: ReopenMode) -> Bool {
        if mode == .automatic, isEnabled {
            guard cmdTabMonitor.start() else {
                enhancements.requestInputMonitoring()
                return false
            }
        } else {
            cmdTabMonitor.stop()
        }
        self.mode = mode
        defaults.set(mode.rawValue, forKey: "reopenMode")
        cancelPending()
        return true
    }

    func cmdTabCompleted() {
        guard isEnabled, mode == .automatic else { return }
        schedule(nil, fromCmdTab: true)
    }

    func cancelPending() {
        generation += 1
        pending?.cancel()
        pending = nil
        pendingPID = nil
    }

    func suppressWindowAction(pid: pid_t) {
        cancelPending()
        cooldownUntil[pid] = ProcessInfo.processInfo.systemUptime + 0.8
    }

    private func schedule(_ app: NSRunningApplication?, fromCmdTab: Bool) {
        cancelPending()
        let request = generation
        pendingPID = app?.processIdentifier
        let work = DispatchWorkItem { [weak self] in
            guard let self, request == self.generation, self.mode == (fromCmdTab ? .automatic : .compatible),
                  let app = app ?? self.workspace.frontmostApplication else { return }
            self.pendingPID = app.processIdentifier
            self.reopenIfNeeded(app, fromCmdTab: fromCmdTab, request: request)
        }
        pending = work
        // Native Cmd+Tab activates its selection after Command release; resolve the target after settling.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: work)
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

    private func canAct(_ app: NSRunningApplication, fromCmdTab: Bool) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        cooldownUntil = cooldownUntil.filter { $0.value > now }
        let pid = app.processIdentifier
        return shouldAttemptReopen(
            enabled: isEnabled, regular: app.activationPolicy == .regular,
            terminated: app.isTerminated, ownProcess: pid == ownPid,
            frontmost: workspace.frontmostApplication?.processIdentifier == pid,
            coolingDown: (cooldownUntil[pid] ?? 0) > now,
            excluded: shouldSkipFinderReopen(bundleIdentifier: app.bundleIdentifier, fromCmdTab: fromCmdTab)
        )
    }

    private func reopenIfNeeded(_ app: NSRunningApplication, fromCmdTab: Bool, request: Int) {
        guard canAct(app, fromCmdTab: fromCmdTab) else { return }
        guard enhancements.enabled(.windowRecovery), enhancements.accessibilityGranted else {
            if fromCmdTab { guard hasTopLevelWindow(for: app.processIdentifier) == false else { return } }
            requestReopen(app)
            return
        }
        access.snapshot(pid: app.processIdentifier) { [weak self] snapshot in
            guard let self, request == self.generation, self.canAct(app, fromCmdTab: fromCmdTab) else { return }
            switch WindowPolicy.recovery(windows: snapshot?.states, hidden: app.isHidden) {
            case .none: return
            case .reopen: self.requestReopen(app)
            case .focus(let id), .restore(let id):
                guard let window = snapshot?.windows.first(where: { $0.state.id == id }) else { return }
                self.suppressWindowAction(pid: app.processIdentifier)
                self.access.restore(window) { success in
                    if !success { logger.error("window restore failed pid=\(app.processIdentifier, privacy: .public)") }
                }
            }
        }
    }

    private func requestReopen(_ app: NSRunningApplication) {
        guard let bundleURL = app.bundleURL else { return }
        let pid = app.processIdentifier
        cooldownUntil[pid] = ProcessInfo.processInfo.systemUptime + 0.5
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
