import AppKit
import ApplicationServices

private final class ReopenWindowAccess: WindowAccess {
    var queriedPIDs = [pid_t]()

    override func snapshot(pid: pid_t, completion: @escaping (WindowSnapshot?) -> Void) {
        queriedPIDs.append(pid)
        completion(nil)
    }
}

private final class CancellationWindowAccess: WindowAccess {
    let window: AppWindow

    init(pid: pid_t) {
        window = AppWindow(element: AXUIElementCreateApplication(pid), pid: pid,
                           state: WindowState(id: 1, onScreen: true), title: "Cancellation fixture", frame: .zero)
        super.init()
    }

    override func snapshot(pid: pid_t, completion: @escaping (WindowSnapshot?) -> Void) {
        queue.async { [window] in
            DispatchQueue.main.async { completion(WindowSnapshot(windows: [window], focusedID: window.state.id)) }
        }
    }

    override func restore(_ window: AppWindow, completion: @escaping (Bool) -> Void) { completion(true) }
}

@main
private enum WindowIntegrationTests {
    @MainActor private static var checks = 0

    static func main() {
        _ = NSApplication.shared
        Task { @MainActor in
            do { try await run(); exit(0) }
            catch { fputs("window integration failed: \(error)\n", stderr); exit(1) }
        }
        RunLoop.main.run()
    }

    @MainActor private static func run() async throws {
        let controllerOnly = CommandLine.arguments.contains("--controller-only")
        let reopenOnly = CommandLine.arguments.contains("--reopen-only")
        guard controllerOnly || AXIsProcessTrusted() else { fputs("window integration requires Accessibility permission\n", stderr); exit(77) }
        if CommandLine.arguments.contains("--finder-only") {
            try await finderRecoveryChecks()
            print("Finder recovery tests passed (\(checks) checks)")
            return
        }
        guard CommandLine.arguments.count >= 2 else { throw Failure.message("fixture executable argument required") }
        let prefix = NSTemporaryDirectory() + "cmd-tab-integration-" + UUID().uuidString
        let executable = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--multiple-windows"]
        configuration.environment = ["CMD_TAB_PRO_FIXTURE_PREFIX": prefix]
        let application: NSRunningApplication = try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.openApplication(at: app, configuration: configuration) { application, error in
                if let application { continuation.resume(returning: application) }
                else { continuation.resume(throwing: error ?? Failure.message("fixture launch failed")) }
            }
        }
        defer {
            if !application.isTerminated { application.forceTerminate() }
            for suffix in ["-state", "-ready", "-visible-reopen"] { try? FileManager.default.removeItem(atPath: prefix + suffix) }
        }
        try await wait("fixture launch") { FileManager.default.fileExists(atPath: prefix + "-ready") }
        application.activate(options: [])
        if reopenOnly {
            try await reopenTimingChecks(application: application)
            print("reopen timing tests passed (\(checks) checks)")
            return
        }
        try await dockCancellationChecks(application: application)
        if controllerOnly { print("Dock cancellation tests passed (\(checks) timing cases)"); return }
        let access = WindowAccess()
        let pid = application.processIdentifier
        let initial = try await snapshot(access, pid: pid)
        try expect(initial.windows.count == 2, "discover both real AX windows")
        let ids = Set(initial.windows.map { $0.state.id })
        try dockChecks(access: access, application: application, snapshot: initial)
        var changes = 0
        let observation = WindowObservation(pid: pid, windows: initial.windows) { changes += 1 }
        try expect(observation != nil, "install AX event observation")
        for window in initial.windows {
            try expect(await minimize(access, window), "minimize actual fixture window")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let minimized = try await snapshot(access, pid: pid)
        try expect(minimized.windows.filter { $0.state.minimized }.count == 2, "both original windows remain present when minimized")
        try expect(changes > 0, "window changes arrive through AX notifications")
        guard let target = minimized.windows.first else { throw Failure.message("missing minimized target") }
        try expect(await restore(access, target), "restore minimized original window")
        let restored = try await snapshot(access, pid: pid)
        try expect(restored.windows.filter { !$0.state.minimized }.count == 1, "restore only one window")
        try expect(Set(restored.windows.map { $0.state.id }) == ids, "restoring must not create a new window")
        try expect(WindowPolicy.recovery(windows: restored.states, hidden: false) == .none, "visible plus minimized needs no further recovery")
        application.hide()
        try await wait("hide fixture") { application.isHidden }
        guard let visible = restored.windows.first(where: { !$0.state.minimized }) else { throw Failure.message("missing visible target") }
        try expect(await restore(access, visible), "unhide and raise original window")
        try await wait("unhide fixture") { !application.isHidden }
        let unhidden = try await snapshot(access, pid: pid)
        try expect(Set(unhidden.windows.map { $0.state.id }) == ids, "unhide preserves window identity")
        try expect(unhidden.windows.filter { $0.state.minimized }.count == 1, "unhide preserves other minimized windows")
        if CommandLine.arguments.contains("--installed-recovery") {
            try await installedRecovery(access: access, application: application, windows: unhidden.windows)
        }
        if CGPreflightScreenCaptureAccess() {
            let capture = WindowPreviewCapture()
            var captured: CGWindowID?
            var image: NSImage?
            capture.load([visible]) { id, thumbnail in captured = id; image = thumbnail }
            try await wait("capture fixture thumbnail", attempts: 50) { captured != nil }
            try expect(captured == visible.state.id, "capture targets exact fixture window")
            try expect(capture.cached(visible) != nil, "thumbnail is cached in memory")
            if let image {
                try expect(abs(image.size.width / image.size.height - visible.frame.width / visible.frame.height) < 0.03,
                       "captured thumbnail preserves original window proportions")
            }
            capture.stop()
        } else {
            print("SKIP: thumbnail capture requires Screen Recording permission")
        }
        for window in unhidden.windows {
            guard let close: AXUIElement = AXRead.value(window.element, kAXCloseButtonAttribute) else { throw Failure.message("fixture close button missing") }
            try expect(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success, "close fixture window through its normal control")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let closed = try await snapshot(access, pid: pid)
        try expect(closed.windows.isEmpty, "closed windows disappear from AX inventory")
        try expect(WindowPolicy.recovery(windows: closed.states, hidden: false) == .reopen, "only closed-window app requests reopen")
        if CommandLine.arguments.contains("--installed-recovery"),
           let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
            finder.activate(options: [])
            try await Task.sleep(nanoseconds: 300_000_000)
            application.activate(options: [])
            try await Task.sleep(nanoseconds: 30_000_000)
            finder.activate(options: [])
            try await Task.sleep(nanoseconds: 600_000_000)
            let cancelled = try await snapshot(access, pid: pid)
            try expect(cancelled.windows.isEmpty, "switching away before delayed recovery cancels reopening the background app")
            application.activate(options: [])
            try await Task.sleep(nanoseconds: 800_000_000)
            let reopened = try await snapshot(access, pid: pid)
            try expect(reopened.windows.count == 1, "confirmed foreground windowless app still receives reopen after cancellation")
        }
        try expect(!(await minimize(access, visible)), "stale window cannot be minimized")
        withExtendedLifetime(observation) {}
        try await reopenTimingChecks(application: application)
        try await finderRecoveryChecks()
        print("window integration tests passed (\(checks) checks)")
    }

    @MainActor private static func installedRecovery(access: WindowAccess, application: NSRunningApplication, windows: [AppWindow]) async throws {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw Failure.message("Finder not running")
        }
        for window in windows { try expect(await minimize(access, window), "prepare minimized windows for installed app recovery") }
        finder.activate(options: [])
        try await Task.sleep(nanoseconds: 600_000_000)
        application.activate(options: [])
        try await Task.sleep(nanoseconds: 800_000_000)
        let restored = try await snapshot(access, pid: application.processIdentifier)
        try expect(restored.windows.filter { !$0.state.minimized }.count == 1, "installed recovery restores one minimized window after activation")
        try expect(Set(restored.windows.map { $0.state.id }) == Set(windows.map { $0.state.id }), "installed recovery preserves original window identities")
        finder.activate(options: [])
        try await Task.sleep(nanoseconds: 600_000_000)
        application.activate(options: [])
        try await Task.sleep(nanoseconds: 800_000_000)
        let partial = try await snapshot(access, pid: application.processIdentifier)
        try expect(partial.windows.filter { $0.state.minimized }.count == 1, "installed recovery preserves the other intentionally minimized window")
        application.hide()
        try await Task.sleep(nanoseconds: 300_000_000)
        finder.activate(options: [])
        try await Task.sleep(nanoseconds: 300_000_000)
        application.activate(options: [])
        try await Task.sleep(nanoseconds: 800_000_000)
        let unhidden = try await snapshot(access, pid: application.processIdentifier)
        try expect(!application.isHidden && unhidden.windows.count == windows.count, "installed recovery unhides existing windows without duplicates")
    }

    @MainActor private static func dockChecks(access: WindowAccess, application: NSRunningApplication, snapshot: WindowSnapshot) throws {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let children: [AXUIElement] = AXRead.value(AXUIElementCreateApplication(dock.processIdentifier), kAXChildrenAttribute),
              let list = children.first, let items: [AXUIElement] = AXRead.value(list, kAXChildrenAttribute) else {
            throw Failure.message("Dock accessibility list unavailable")
        }
        guard let finderItem = items.first(where: { (AXRead.value($0, kAXURLAttribute) as URL?)?.lastPathComponent == "Finder.app" }),
              let frame = AXRead.frame(finderItem),
              let target = DockController.dockTarget(at: CGPoint(x: frame.midX, y: frame.midY)) else {
            throw Failure.message("Dock application hit testing unavailable")
        }
        try expect(target.app.bundleIdentifier == "com.apple.finder", "Dock hit testing resolves the actual application URL")
        try expect(DockController.dockTarget(at: CGPoint(x: -10000, y: -10000)) == nil, "outside-Dock coordinates are ignored")
        if let trash = items.first(where: { (AXRead.value($0, kAXSubroleAttribute) as String?) == "AXTrashDockItem" }), let frame = AXRead.frame(trash) {
            try expect(DockController.dockTarget(at: CGPoint(x: frame.midX, y: frame.midY)) == nil, "Trash is not treated as an application")
        }
        let capture = WindowPreviewCapture()
        let panel = DockPreviewPanel()
        let screen = NSScreen.screens.first!
        let anchor = CGRect(x: screen.frame.midX, y: screen.frame.minY, width: 50, height: 50)
        let previousPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        panel.show(app: application, windows: snapshot.windows, anchor: anchor, screen: screen, style: .titles) { _ in }
        try expect(panel.isVisible, "Dock preview panel can display actual fixture windows")
        try expect(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousPID, "hover preview must not activate the target application")
        try expect(screen.visibleFrame.contains(panel.frame), "Dock preview stays within current display")
        let titleHeight = panel.frame.height
        try checkPanelLayout(horizontal: false)
        savePanel("dock-titles")
        var selected: CGWindowID?
        panel.show(app: application, windows: snapshot.windows, anchor: anchor, screen: screen, style: .thumbnails, capture: capture) { selected = $0.state.id }
        try expect(panel.frame.height > titleHeight, "thumbnail mode uses a separate visual layout from title tags")
        let image = NSImage(size: NSSize(width: 500, height: 100), flipped: false) { rect in
            NSColor.systemBlue.setFill()
            NSBezierPath(rect: rect).fill()
            return true
        }
        panel.setImage(image, for: snapshot.windows[0].state.id)
        try checkPanelLayout(horizontal: true)
        if let content = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })?.contentView as? NSGlassEffectView,
           let scroll = content.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first,
           let row = scroll.documentView as? NSStackView,
           let button = row.arrangedSubviews.first as? NSButton,
           let preview = button.subviews.first(where: { $0.layer?.contentsGravity == .resizeAspectFill }) {
            try expect(preview.layer?.contents != nil, "asynchronous screenshots update the full thumbnail surface")
            try expect(preview.subviews.compactMap { $0 as? NSImageView }.allSatisfy(\.isHidden), "captured preview hides the placeholder icon")
            button.performClick(nil)
            try expect(selected == snapshot.windows[0].state.id, "filled thumbnail preserves the window selection action")
        } else {
            try expect(false, "thumbnail surface is available for captured images")
        }
        savePanel("dock-thumbnails")
        panel.show(app: application, windows: Array(repeating: snapshot.windows[0], count: 5), anchor: anchor,
                   screen: screen, style: .thumbnails, capture: capture) { _ in }
        try checkPanelLayout(horizontal: true)
        panel.hide()
        try expect(!panel.isVisible, "Dock preview dismisses without retaining visible UI")
        let suite = "com.ares.cmd.tab.dock.integration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = EnhancementSettings(defaults: defaults)
        settings.set(.dockPreview, enabled: true)
        let controller = DockController(access: access, settings: settings) { _ in }
        controller.configure(active: true)
        try expect(settings.dockObserverAvailable, "preview installs a passive mouse-movement tap before any click")
        try expect(!settings.dockTapAvailable, "preview-only feature must not install an intercepting mouse tap")
        settings.set(.dockClickMinimize, enabled: true)
        controller.configure(active: true)
        try expect(settings.dockTapAvailable, "click-minimize mouse tap installs with existing Accessibility permission")
        controller.configure(active: false)
        try expect(!settings.dockTapAvailable, "pause removes mouse interception")
        try expect(!settings.dockObserverAvailable, "pause removes hover observation")
        controller.configure(active: true)
        try expect(settings.dockTapAvailable, "mouse interception can resume after pause")
        controller.stop()
    }

    @MainActor private static func finderRecoveryChecks() async throws {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw Failure.message("Finder not running")
        }
        let access = WindowAccess()
        let pid = finder.processIdentifier
        let initial = try await snapshot(access, pid: pid)
        guard initial.windows.isEmpty else { print("SKIP: Finder desktop-only checks require no existing Finder windows"); return }
        let previous = NSWorkspace.shared.frontmostApplication
        var created: AppWindow?
        defer {
            if let created, let close: AXUIElement = AXRead.value(created.element, kAXCloseButtonAttribute) {
                _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
            }
            previous?.activate(options: [])
        }
        let suite = "com.ares.cmd.tab.finder.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = EnhancementSettings(defaults: defaults)
        settings.set(.windowRecovery, enabled: true)
        defaults.set(ReopenMode.compatible.rawValue, forKey: "reopenMode")
        let compatible = ReopenController(statistics: SwitchStatisticsStore(defaults: defaults), access: access,
                                          enhancements: settings, defaults: defaults)
        finder.activate(options: [])
        try await wait("Finder activation") { NSWorkspace.shared.frontmostApplication?.processIdentifier == pid }
        compatible.applicationActivated(finder)
        try await Task.sleep(nanoseconds: 300_000_000)
        let desktop = try await snapshot(access, pid: pid)
        try expect(desktop.windows.isEmpty, "compatible desktop activation does not open a Finder window")
        compatible.cancelPending()
        defaults.set(ReopenMode.automatic.rawValue, forKey: "reopenMode")
        let automatic = ReopenController(statistics: SwitchStatisticsStore(defaults: defaults), access: access,
                                         enhancements: settings, defaults: defaults)
        automatic.cmdTabCompleted()
        try await Task.sleep(nanoseconds: 700_000_000)
        let reopened = try await snapshot(access, pid: pid)
        created = reopened.windows.first
        try expect(reopened.windows.count == 1, "explicit Cmd+Tab to desktop-only Finder opens one window")
        automatic.cmdTabCompleted()
        try await Task.sleep(nanoseconds: 700_000_000)
        let existing = try await snapshot(access, pid: pid)
        try expect(existing.windows.map { $0.state.id } == reopened.windows.map { $0.state.id }, "Finder windows remain recognizable alongside its desktop without duplicate reopen")
        guard let createdWindow = created, let close: AXUIElement = AXRead.value(createdWindow.element, kAXCloseButtonAttribute) else {
            throw Failure.message("created Finder window close button missing")
        }
        try expect(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success, "close only the Finder window created by this test")
        automatic.applicationActivated(finder)
        try await Task.sleep(nanoseconds: 300_000_000)
        let closed = try await snapshot(access, pid: pid)
        try expect(closed.windows.isEmpty, "automatic desktop activation without Cmd+Tab does not reopen Finder")
        created = nil
        automatic.cancelPending()
    }

    @MainActor private static func reopenTimingChecks(application: NSRunningApplication) async throws {
        guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
            throw Failure.message("Finder not running")
        }
        let previous = NSWorkspace.shared.frontmostApplication
        defer { previous?.activate(options: []) }
        let suite = "com.ares.cmd.tab.reopen.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(ReopenMode.automatic.rawValue, forKey: "reopenMode")
        let settings = EnhancementSettings(defaults: defaults)
        settings.set(.windowRecovery, enabled: true)
        let access = ReopenWindowAccess()
        let controller = ReopenController(statistics: SwitchStatisticsStore(defaults: defaults), access: access,
                                          enhancements: settings, defaults: defaults)
        func activate(_ app: NSRunningApplication) async throws {
            app.activate(options: [])
            try await wait("foreground app") { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier }
        }
        try await activate(application)
        controller.cmdTabCompleted()
        try await Task.sleep(nanoseconds: 300_000_000)
        try expect(access.queriedPIDs == [application.processIdentifier], "already-frontmost selection still recovers")
        access.queriedPIDs.removeAll()
        try await activate(finder)
        controller.cmdTabCompleted()
        // Let the next main-queue turn run while the old app is still foreground.
        try await Task.sleep(nanoseconds: 50_000_000)
        try await activate(application)
        controller.applicationActivated(application)
        try await Task.sleep(nanoseconds: 300_000_000)
        try expect(access.queriedPIDs == [application.processIdentifier], "activation after Command release recovers the selected app")
        access.queriedPIDs.removeAll()
        controller.cmdTabCompleted()
        controller.cancelPending()
        try await Task.sleep(nanoseconds: 300_000_000)
        try expect(access.queriedPIDs.isEmpty, "new input still cancels unresolved Cmd+Tab recovery")
        _ = controller.setMode(.compatible)
        controller.applicationActivated(application)
        try await Task.sleep(nanoseconds: 300_000_000)
        try expect(access.queriedPIDs == [application.processIdentifier], "compatible activation still recovers its explicit target")
        controller.cancelPending()
        let realAccess = WindowAccess()
        let windows = try await snapshot(realAccess, pid: application.processIdentifier)
        for window in windows.windows {
            guard let close: AXUIElement = AXRead.value(window.element, kAXCloseButtonAttribute) else {
                throw Failure.message("reopen fixture close button missing")
            }
            try expect(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success, "close recovery fixture windows")
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let closed = try await snapshot(realAccess, pid: application.processIdentifier)
        try expect(closed.windows.isEmpty, "recovery fixture process stays alive without windows")
        defaults.set(ReopenMode.automatic.rawValue, forKey: "reopenMode")
        let realController = ReopenController(statistics: SwitchStatisticsStore(defaults: defaults), access: realAccess,
                                              enhancements: settings, defaults: defaults)
        try await activate(finder)
        realController.cmdTabCompleted()
        try await Task.sleep(nanoseconds: 50_000_000)
        try await activate(application)
        realController.applicationActivated(application)
        try await Task.sleep(nanoseconds: 600_000_000)
        let reopened = try await snapshot(realAccess, pid: application.processIdentifier)
        try expect(reopened.windows.count == 1, "late activation of a windowless app reopens exactly one real window")
        realController.cancelPending()
    }

    @MainActor private static func dockCancellationChecks(application: NSRunningApplication) async throws {
        let suite = "com.ares.cmd.tab.dock.cancellation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = EnhancementSettings(defaults: defaults)
        settings.set(.dockPreview, enabled: true)
        let access = CancellationWindowAccess(pid: application.processIdentifier)
        var actions = 0
        let screen = NSScreen.screens.first!.frame
        let x = NSEvent.mouseLocation.x < screen.midX ? screen.maxX - 60 : screen.minX + 10
        let anchor = CGRect(x: x, y: screen.minY, width: 50, height: 50)
        let target = DockTarget(app: application, frame: DockPolicy.appKitFrame(anchor, desktopTop: screen.maxY))
        let controller = DockController(access: access, settings: settings,
                                        targetAtPoint: { target.frame.contains($0) ? target : nil }) { _ in actions += 1 }
        defer { controller.stop() }
        let outside = CGPoint(x: screen.midX, y: screen.midY)
        func visible() -> Bool { NSApp.windows.contains { $0 is NSPanel && $0.isVisible } }
        func drain() async {
            await withCheckedContinuation { continuation in
                access.queue.async { DispatchQueue.main.async { continuation.resume() } }
            }
        }
        func show() async throws {
            controller.hover(target)
            try await wait("controller preview", condition: visible)
        }
        let query = DispatchSemaphore(value: 0)
        access.queue.async { _ = query.wait(timeout: .now() + 2) }
        controller.hover(target)
        controller.handle(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        query.signal()
        await drain()
        try await Task.sleep(nanoseconds: 350_000_000)
        try expect(!visible(), "outside click cancels an in-flight preview query")
        try await show()
        for _ in 0..<5 {
            controller.pointerMoved(to: outside)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try expect(!visible(), "continuous pointer movement does not postpone preview dismissal")
        try await show()
        guard let glass = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })?.contentView as? NSGlassEffectView,
              let scroll = glass.contentView?.subviews.compactMap({ $0 as? NSScrollView }).first,
              let row = scroll.documentView as? NSStackView, let button = row.arrangedSubviews.first as? NSButton else {
            throw Failure.message("controller preview button unavailable")
        }
        let selection = DispatchSemaphore(value: 0)
        access.queue.async { _ = selection.wait(timeout: .now() + 2) }
        button.performClick(nil)
        controller.handle(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                         windowNumber: 0, context: nil, characters: "w", charactersIgnoringModifiers: "w",
                                         isARepeat: false, keyCode: 13)!)
        selection.signal()
        await drain()
        try expect(actions == 0, "new keyboard input cancels deferred preview selection")
        controller.stop()
        let paused = DispatchSemaphore(value: 0)
        access.queue.async { _ = paused.wait(timeout: .now() + 2) }
        controller.hover(target)
        controller.stop()
        paused.signal()
        await drain()
        try await Task.sleep(nanoseconds: 350_000_000)
        try expect(!visible(), "pause cancels deferred preview work")
        controller.pointerMoved(to: CGPoint(x: target.frame.midX, y: target.frame.midY))
        try finishDockHitBeforeMainCallback(access)
        controller.pointerMoved(to: outside)
        await drain()
        try await Task.sleep(nanoseconds: 350_000_000)
        try expect(!visible(), "an older Dock hit cannot reopen a preview after the pointer leaves")
    }

    @MainActor private static func finishDockHitBeforeMainCallback(_ access: WindowAccess) throws {
        // Hold the main callback until the test supplies the next pointer position.
        let hit = DispatchSemaphore(value: 0)
        access.queue.asyncAfter(deadline: .now() + .milliseconds(30)) { hit.signal() }
        guard hit.wait(timeout: .now() + 2) == .success else { throw Failure.message("Dock hit query did not finish") }
    }

    @MainActor private static func savePanel(_ name: String) {
        guard let view = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        try? bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent(name + ".png"))
    }

    @MainActor private static func checkPanelLayout(horizontal: Bool) throws {
        guard let view = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })?.contentView else { return }
        view.layoutSubtreeIfNeeded()
        guard let glass = view as? NSGlassEffectView, let content = glass.contentView else {
            try expect(false, "Dock preview uses native Liquid Glass with a content view")
            return
        }
        try expect(glass.style == .regular, "regular glass preserves legibility over arbitrary desktops")
        if #available(macOS 27.0, *) { try expect(glass.effectIsInteractive, "macOS 27 glass responds to pointer interaction") }
        try expect(content.bounds.width > 0 && content.bounds.height > 0, "glass content follows panel size")
        guard let scroll = content.subviews.compactMap({ $0 as? NSScrollView }).first, let document = scroll.documentView else {
            try expect(false, "glass content contains a scrollable window list")
            return
        }
        try expect(scroll.contentSize.height >= document.frame.height - 0.5, "rows fit vertically without a spurious scrollbar or clipped thumbnails")
        func buttons(in view: NSView) -> [NSButton] {
            view.subviews.flatMap { child -> [NSButton] in
                (child as? NSButton).map { [$0] } ?? buttons(in: child)
            }
        }
        let items = buttons(in: view).filter { $0.tag > 0 }
        guard items.count >= 2 else { try expect(false, "panel must contain both fixture window controls"); return }
        for item in items {
            try expect(document.bounds.contains(item.convert(item.bounds, to: document)), "scrollable glass content keeps each window selectable")
            try expect(item.showsBorderOnlyWhileMouseInside, "window controls use native hover feedback")
            try expect(item.bezelStyle == (horizontal ? .flexiblePush : .accessoryBarAction), "thumbnail controls support full-height content")
            if horizontal, let preview = item.subviews.first(where: { $0.layer?.contentsGravity == .resizeAspectFill }) {
                try expect(abs(preview.frame.width - item.bounds.width) < 1, "thumbnail fills the available card width")
                try expect(preview.frame.height >= item.bounds.height * 0.7, "thumbnail occupies most of the card height")
                try expect(preview.layer?.masksToBounds == true, "aspect-fill images clip to the rounded preview surface")
                let center = preview.convert(NSPoint(x: preview.bounds.midX, y: preview.bounds.midY), to: item.superview)
                try expect(item.hitTest(center) === item, "image subviews do not intercept thumbnail clicks")
            } else if horizontal {
                try expect(false, "thumbnail uses a full-width image surface")
            }
        }
        let first = items[0].frame
        let second = items[1].frame
        if horizontal {
            try expect(abs(first.minY - second.minY) < 1 && abs(first.minX - second.minX) > 10,
                   "thumbnail controls align horizontally without overlapping")
        } else {
            try expect(abs(first.minX - second.minX) < 1 && abs(first.minY - second.minY) > 10,
                   "window title controls align as a vertical list")
        }
    }

    @MainActor private static func snapshot(_ access: WindowAccess, pid: pid_t) async throws -> WindowSnapshot {
        for _ in 0..<5 {
            let result = await withCheckedContinuation { continuation in access.snapshot(pid: pid) { continuation.resume(returning: $0) } }
            if let result { return result }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        print("AX diagnostic status=\(status.rawValue) windows=\((value as? [AXUIElement])?.count ?? -1)")
        for window in value as? [AXUIElement] ?? [] {
            let role: String? = AXRead.value(window, kAXRoleAttribute)
            let subrole: String? = AXRead.value(window, kAXSubroleAttribute)
            let minimized: Bool? = AXRead.value(window, kAXMinimizedAttribute)
            print("AX diagnostic role=\(role ?? "nil") subrole=\(subrole ?? "nil") id=\(AXRead.id(window) ?? 0) minimized=\(String(describing: minimized))")
        }
        throw Failure.message("AX snapshot unavailable")
    }

    @MainActor private static func minimize(_ access: WindowAccess, _ window: AppWindow) async -> Bool {
        await withCheckedContinuation { continuation in access.minimize(window) { continuation.resume(returning: $0) } }
    }

    @MainActor private static func restore(_ access: WindowAccess, _ window: AppWindow) async -> Bool {
        await withCheckedContinuation { continuation in access.restore(window) { continuation.resume(returning: $0) } }
    }

    @MainActor private static func wait(_ message: String, attempts: Int = 30, condition: () -> Bool) async throws {
        for _ in 0..<attempts {
            if condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw Failure.message("timeout: " + message)
    }

    @MainActor private static func expect(_ condition: Bool, _ message: String) throws {
        checks += 1
        guard condition else { throw Failure.message(message) }
    }

    private enum Failure: Error {
        case message(String)
    }
}
