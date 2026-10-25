import AppKit
import ServiceManagement

@main
private enum DashboardTests {
    private static var checks = 0

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "com.ares.cmd.tab.ui.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let statistics = SwitchStatisticsStore(defaults: defaults)
        let enhancements = EnhancementSettings(defaults: defaults)
        for index in 1...5 { statistics.record(bundleIdentifier: "com.example.fixture.\(index)", displayName: "测试应用 \(index)") }
        var enabled = true
        var menuVisible = false
        var theme = InterfaceTheme.system
        var login = false
        var icon = AppIconOption.option2
        var mode = ReopenMode.compatible
        var restoreRequests = 0
        var releaseRequests = 0
        let controller = DashboardWindowController(
            statistics: statistics, enhancements: enhancements,
            isReopenEnabled: { enabled }, setReopenEnabled: { enabled = $0 },
            loginStatus: { login ? .enabled : .notRegistered }, setLoginEnabled: { login = $0 },
            interfaceTheme: { theme }, setInterfaceTheme: { theme = $0; app.appearance = $0.appearance },
            menuBarIconVisible: { menuVisible }, setMenuBarIconVisible: { menuVisible = $0 },
            appIconOption: { icon }, setAppIconOption: { icon = $0 }, diagnosticText: { "diagnostics fixture" },
            openReleases: { releaseRequests += 1 }, reopenMode: { mode }, setReopenMode: { mode = $0 },
            restoreDefaults: { restoreRequests += 1 }
        )
        guard let window = controller.window,
              let tabs = window.contentViewController as? NSTabViewController else { fail("dashboard unavailable") }
        expect(tabs.tabViewItems.map(\.label) == ["切换设置", "Dock 预览", "统计", "关于"], "settings pages follow the requested names and order")
        expect(window.contentLayoutRect.size == NSSize(width: 680, height: 620), "settings uses the spacious content size")
        expect(!window.styleMask.contains(.resizable), "settings remains non-resizable")
        expect(!window.isOpaque, "settings window allows native backdrop material")
        if CommandLine.arguments.count == 1 || CommandLine.arguments.contains("--preview") {
            app.appearance = NSAppearance(named: .darkAqua)
            let dock = DockPreviewPanel()
            let sample = NSRunningApplication.current
            if Bundle.main.bundleIdentifier?.hasSuffix(".dockpreview") == true, let screen = NSScreen.main {
                let windows = ["梳理 cmd-tab-pro 参考内容", "窗口与 Dock 增强"].enumerated().map { index, title in
                    AppWindow(element: AXUIElementCreateApplication(sample.processIdentifier), pid: sample.processIdentifier,
                              state: WindowState(id: UInt32(index + 1), minimized: index == 1), title: title, frame: .zero)
                }
                let anchor = NSRect(x: screen.visibleFrame.maxX - 180, y: screen.visibleFrame.minY, width: 40, height: 40)
                dock.show(app: sample, windows: windows, anchor: anchor, screen: screen) { _ in }
                // Only synthetic preview content is shareable; production panels retain their capture protection.
                NSApp.windows.first { $0 is NSPanel }?.sharingType = .readOnly
            } else {
                controller.showDashboard()
            }
            app.run()
            withExtendedLifetime(dock) {}
            return
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark"),
                                   (.accessibilityHighContrastAqua, "contrast-light"), (.accessibilityHighContrastDarkAqua, "contrast-dark")] {
            app.appearance = NSAppearance(named: appearance)
            for index in 0..<tabs.tabViewItems.count {
                tabs.selectedTabViewItemIndex = index
                controller.refresh()
                window.contentView?.layoutSubtreeIfNeeded()
                guard let view = tabs.tabViewItems[index].viewController?.view else { fail("tab has no view") }
                expect((view as? NSVisualEffectView)?.material == .underWindowBackground, "all pages share the native window material")
                view.layoutSubtreeIfNeeded()
                guard let scroll = descendants(view).compactMap({ $0 as? NSScrollView }).first,
                      let document = scroll.documentView else { fail("settings page must have a scrollable document") }
                document.layoutSubtreeIfNeeded()
                expect(scroll.hasVerticalScroller, "long settings pages remain reachable")
                if index == 2 {
                    expect(document.bounds.height > scroll.contentSize.height, "five-app ranking exercises vertical scrolling")
                    scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
                    scroll.reflectScrolledClipView(scroll.contentView)
                    expect(scroll.documentVisibleRect.maxY >= document.bounds.maxY - 1, "scrolling reaches the final ranking row")
                    scroll.contentView.scroll(to: .zero)
                    scroll.reflectScrolledClipView(scroll.contentView)
                }
                let controls = descendants(document).filter { $0 is NSControl && !$0.isHiddenOrHasHiddenAncestor }
                expect(!controls.isEmpty, "page \(index) has controls")
                if index == 1, let grid = descendants(document).compactMap({ $0 as? NSGridView }).first,
                   let label = grid.cell(atColumnIndex: 0, rowIndex: 0).contentView,
                   let status = grid.cell(atColumnIndex: 1, rowIndex: 0).contentView {
                    let gap = status.convert(status.bounds, to: grid).minX - label.convert(label.bounds, to: grid).maxX
                    expect(gap >= 0 && gap <= grid.columnSpacing * 2, "permission status stays next to its label in \(name): gap \(gap)")
                }
                for control in controls {
                    let rect = control.convert(control.bounds, to: document)
                    expect(rect.width > 0 && rect.height > 0, "page \(index) control has nonzero size")
                    expect(document.bounds.insetBy(dx: -1, dy: -1).contains(rect), "page \(index) control stays within scrollable content: \(rect)")
                }
                if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(index)-\(name).png"))
                }
                if let frame = window.contentView?.superview,
                   let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) {
                    frame.cacheDisplay(in: frame.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("\(index)-\(name)-window.png"))
                }
            }
        }
        tabs.selectedTabViewItemIndex = 0
        let general = tabs.tabViewItems[0].viewController!.view
        let generalSwitches = descendants(general).compactMap { $0 as? NSSwitch }
        expect(generalSwitches.count == 3, "general controls include recovery, login and menu bar")
        generalSwitches[0].performClick(nil)
        expect(!enabled, "pause control reaches running state callback")
        generalSwitches[1].performClick(nil)
        expect(login, "login switch reaches registration callback")
        generalSwitches[2].performClick(nil)
        expect(menuVisible, "menu bar switch reaches visibility callback")
        let popups = descendants(general).compactMap { $0 as? NSPopUpButton }
        expect(popups.count == 2, "mode and theme selectors remain available")
        popups[0].selectItem(at: 0)
        popups[0].sendAction(popups[0].action, to: popups[0].target)
        expect(mode == .automatic, "mode selector reaches mode callback")
        popups[1].selectItem(at: 2)
        popups[1].sendAction(popups[1].action, to: popups[1].target)
        expect(theme == .dark, "theme selector reaches appearance callback")
        tabs.selectedTabViewItemIndex = 1
        let enhancementSwitches = descendants(tabs.tabViewItems[1].viewController!.view).compactMap { $0 as? NSSwitch }
        expect(enhancementSwitches.count == 3, "three independent enhancement switches exist")
        for toggle in enhancementSwitches {
            toggle.state = .on
            toggle.sendAction(toggle.action, to: toggle.target)
        }
        expect(EnhancementFeature.allCases.allSatisfy(enhancements.enabled), "enhancement controls persist selected features")
        let statusGrid = descendants(tabs.tabViewItems[1].viewController!.view).compactMap { $0 as? NSGridView }.first!
        expect(statusGrid.numberOfRows == 3, "authorization status includes all three system permissions")
        expect((0..<statusGrid.numberOfRows).map { (statusGrid.cell(atColumnIndex: 0, rowIndex: $0).contentView as? NSTextField)?.stringValue } == ["窗口控制：", "屏幕录制：", "输入监控："], "permission labels include input monitoring for automatic mode")
        enhancements.dockObserverAvailable = true
        enhancements.dockTapAvailable = true
        controller.refresh()
        expect(descendants(statusGrid).filter { $0 is NSTextField || $0 is NSImageView }.count == 6, "refresh keeps three permission rows without overlapping views or feature readiness")
        let windowStatus = statusGrid.cell(atColumnIndex: 1, rowIndex: 0).contentView!
        if enhancements.accessibilityGranted {
            let icon = windowStatus as? NSImageView
            expect(icon?.image != nil && icon?.contentTintColor == .systemGreen, "granted permission uses the native green success icon")
            expect(icon?.isAccessibilityElement() == true, "status icon remains reachable by screen readers")
            expect(icon?.accessibilityLabel() == "窗口控制：已授权", "status icon preserves the permission name and spoken state")
        } else {
            expect((windowStatus as? NSTextField)?.stringValue == "未授权，窗口增强暂不可用", "missing permission retains its explanation")
            expect(windowStatus.accessibilityLabel() == "窗口控制：未授权，窗口增强暂不可用", "missing permission preserves the spoken state")
        }
        expect((statusGrid.cell(atColumnIndex: 1, rowIndex: 1).contentView as? NSTextField)?.stringValue == "标签模式无需录屏", "title mode keeps the no-recording explanation")
        let inputStatus = statusGrid.cell(atColumnIndex: 1, rowIndex: 2).contentView!
        let inputText = enhancements.inputMonitoringGranted ? "已授权" : "未授权，仅增强自动模式需要"
        expect(inputStatus.accessibilityLabel() == "输入监控：" + inputText, "input monitoring status preserves its spoken meaning")
        expect(enhancements.inputMonitoringGranted ? (inputStatus as? NSImageView)?.contentTintColor == .systemGreen : (inputStatus as? NSTextField)?.stringValue == inputText, "input monitoring reflects the real permission using the shared status style")
        let inputButton = descendants(tabs.tabViewItems[1].viewController!.view).compactMap { $0 as? NSButton }.first { $0.title == "授权输入监控" }
        expect(inputButton != nil && inputButton?.isEnabled == !enhancements.inputMonitoringGranted, "input monitoring has an explicit grant button enabled only while permission is missing")
        expect(mode == .automatic, "showing and refreshing permissions does not change the selected mode")
        tabs.tabViewItems[1].viewController!.view.layoutSubtreeIfNeeded()
        if let card = descendants(tabs.tabViewItems[1].viewController!.view).first(where: { $0 is NSBox && statusGrid.isDescendant(of: $0) }),
           let bitmap = card.bitmapImageRepForCachingDisplay(in: card.bounds) {
            card.cacheDisplay(in: card.bounds, to: bitmap)
            try! bitmap.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent("authorization-status-dark.png"))
        }
        let displayStyle = descendants(tabs.tabViewItems[1].viewController!.view).compactMap { $0 as? NSPopUpButton }.first!
        expect(displayStyle.itemTitles == ["标签列表", "窗口缩略图"], "Dock provides both approved display styles")
        displayStyle.selectItem(at: 1)
        displayStyle.sendAction(displayStyle.action, to: displayStyle.target)
        expect(enhancements.dockDisplayStyle == .thumbnails, "display style selector reaches persisted settings")
        let about = tabs.tabViewItems[3].viewController!.view
        expect(descendants(about).compactMap { $0 as? NSButton }.contains(where: { $0.title == "复制诊断信息" }), "diagnostics action remains available")
        expect(statistics.snapshot().sevenDayCount == 5, "UI navigation does not destroy statistics")
        tabs.selectedTabViewItemIndex = 3
        let aboutButtons = descendants(about).compactMap { $0 as? NSButton }
        let clear = aboutButtons.first { $0.title == "清除统计…" }!
        respondToAlert(.alertSecondButtonReturn) { clear.performClick(nil) }
        expect(statistics.snapshot().sevenDayCount == 5, "cancelling clear preserves stored statistics")
        respondToAlert(.alertFirstButtonReturn) { clear.performClick(nil) }
        expect(statistics.snapshot().sevenDayCount == 0, "confirmed clear removes isolated test statistics")
        let reset = aboutButtons.first { $0.title == "恢复默认设置…" }!
        respondToAlert(.alertSecondButtonReturn) { reset.performClick(nil) }
        expect(restoreRequests == 0, "cancelled reset must not change preferences")
        respondToAlert(.alertFirstButtonReturn) { reset.performClick(nil) }
        expect(restoreRequests == 1, "confirmed reset reaches reset callback once")
        aboutButtons.first { $0.title == "检查更新…" }!.performClick(nil)
        expect(releaseRequests == 1, "update button requests the release page without background network access")
        tabs.selectedTabViewItemIndex = 0
        let firstIcon = descendants(general).compactMap { $0 as? NSButton }.first { $0.toolTip == "窗口切换" }!
        respondToAlert(.alertSecondButtonReturn) { firstIcon.performClick(nil) }
        expect(icon == .option2, "cancelled icon change preserves installed choice")
        respondToAlert(.alertFirstButtonReturn) { firstIcon.performClick(nil) }
        expect(icon == .option1, "confirmed icon change reaches icon callback")
        controller.showAbout()
        expect(tabs.selectedTabViewItemIndex == 3, "About menu opens the correct page after reordering")
        window.orderOut(nil)
        print("dashboard tests passed (\(checks) checks; light/dark snapshots saved)")
    }

    private static func respondToAlert(_ response: NSApplication.ModalResponse, action: () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { NSApp.stopModal(withCode: response) }
        action()
    }

    private static func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fail(message) }
    }

    private static func fail(_ message: String) -> Never {
        fputs("dashboard test failed: \(message)\n", stderr)
        exit(1)
    }
}
