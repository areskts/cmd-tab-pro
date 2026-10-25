import AppKit

@main
private enum WindowPolicyTests {
    private static var count = 0

    static func main() {
        recovery()
        minimizing()
        dockLayout()
        clicks()
        keyboardSessions()
        preferences()
        print("window and Dock tests passed (\(count) checks)")
    }

    private static func recovery() {
        let visible = WindowState(id: 1, onScreen: true, main: true)
        let minimized = WindowState(id: 2, minimized: true, lastUsed: 10)
        let older = WindowState(id: 3, minimized: true, main: true, lastUsed: 5)
        expect(WindowPolicy.recovery(windows: nil, hidden: false) == .none, "failed AX reads must not create windows")
        expect(WindowPolicy.recovery(windows: [], hidden: false) == .reopen, "confirmed windowless app should reopen")
        expect(WindowPolicy.recovery(windows: [visible], hidden: false) == .none, "visible app needs no extra action")
        expect(WindowPolicy.recovery(windows: [visible], hidden: true) == .focus(1), "hidden app should use its original window")
        expect(WindowPolicy.recovery(windows: [minimized], hidden: false) == .restore(2), "sole minimized window should restore")
        expect(WindowPolicy.recovery(windows: [older, minimized], hidden: false) == .restore(2), "restore only most recently focused minimized window")
        expect(WindowPolicy.recovery(windows: [visible, minimized], hidden: false) == .none, "do not expand minimized windows when another is available")
        expect(WindowPolicy.recovery(windows: [minimized], hidden: true) == .restore(2), "hidden minimized app should restore its window")
        expect(WindowPolicy.recovery(windows: [WindowState(id: 4)], hidden: false) == .none, "another Space must not count as windowless")
        expect(WindowPolicy.recovery(windows: [WindowState(id: 5, fullscreen: true)], hidden: false) == .none, "full-screen window must not be reopened")
        expect(WindowPolicy.recovery(windows: [WindowState(id: 6, minimized: true), WindowState(id: 7, minimized: true, main: true)], hidden: false) == .restore(7), "main window is fallback when focus history is unavailable")
    }

    private static func minimizing() {
        let visible = WindowState(id: 1, onScreen: true)
        expect(WindowPolicy.minimizeTarget(windows: [visible], focusedID: 1, frontmost: true, hidden: false) == 1, "active ordinary window may minimize")
        expect(WindowPolicy.minimizeTarget(windows: [visible], focusedID: 1, frontmost: false, hidden: false) == nil, "background Dock click must activate")
        expect(WindowPolicy.minimizeTarget(windows: [visible], focusedID: 1, frontmost: true, hidden: true) == nil, "hidden app must restore")
        expect(WindowPolicy.minimizeTarget(windows: [visible], focusedID: nil, frontmost: true, hidden: false) == nil, "unknown focus must preserve the Dock click")
        expect(WindowPolicy.minimizeTarget(windows: [WindowState(id: 2)], focusedID: 2, frontmost: true, hidden: false) == nil, "other-Space window must not minimize")
        expect(WindowPolicy.minimizeTarget(windows: [WindowState(id: 3, minimized: true, onScreen: true)], focusedID: 3, frontmost: true, hidden: false) == nil, "already minimized window must restore")
        expect(WindowPolicy.minimizeTarget(windows: [WindowState(id: 4, onScreen: true, fullscreen: true)], focusedID: 4, frontmost: true, hidden: false) == nil, "full screen remains unchanged")
        expect(WindowPolicy.minimizeTarget(windows: [visible, WindowState(id: 5, onScreen: true)], focusedID: 5, frontmost: true, hidden: false) == 5, "minimize only focused window in multiwindow app")
    }

    private static func dockLayout() {
        expect(DockPolicy.thumbnailSize(for: CGSize(width: 1600, height: 900)) == CGSize(width: 480, height: 270), "wide thumbnail preserves aspect ratio")
        expect(DockPolicy.thumbnailSize(for: CGSize(width: 900, height: 1600)) == CGSize(width: 180, height: 320), "portrait thumbnail preserves aspect ratio")
        expect(DockPolicy.thumbnailSize(for: .zero) == CGSize(width: 1, height: 1), "invalid thumbnail bounds do not divide by zero")
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = CGSize(width: 360, height: 184)
        let bottom = DockPolicy.previewFrame(anchor: CGRect(x: 600, y: 0, width: 60, height: 60), size: size, screen: screen)
        expect(bottom.minY == 68 && screen.contains(bottom), "bottom Dock panel should sit above icon")
        let left = DockPolicy.previewFrame(anchor: CGRect(x: 0, y: 400, width: 60, height: 60), size: size, screen: screen)
        expect(left.minX == 68 && screen.contains(left), "left Dock panel should sit to the right")
        let right = DockPolicy.previewFrame(anchor: CGRect(x: 1380, y: 400, width: 60, height: 60), size: size, screen: screen)
        expect(right.maxX == 1372 && screen.contains(right), "right Dock panel should sit to the left")
        let secondScreen = CGRect(x: -1200, y: 200, width: 1200, height: 800)
        let other = DockPolicy.previewFrame(anchor: CGRect(x: -1000, y: 200, width: 60, height: 60), size: size, screen: secondScreen)
        expect(secondScreen.contains(other), "negative-coordinate display must contain its panel")
        let large = DockPolicy.previewFrame(anchor: CGRect(x: 1400, y: 0, width: 40, height: 60), size: CGSize(width: 2000, height: 1400), screen: screen)
        expect(screen.insetBy(dx: 12, dy: 12).contains(large), "large previews must fit within display bounds")
        expect(DockPolicy.appKitFrame(CGRect(x: 12, y: 700, width: 50, height: 60), desktopTop: 900) == CGRect(x: 12, y: 140, width: 50, height: 60), "AX and AppKit coordinate conversion must preserve size")
        expect(DockPolicy.nearEdge(CGPoint(x: 20, y: 450), screens: [screen]), "side Dock must be discoverable")
        expect(!DockPolicy.nearEdge(CGPoint(x: 700, y: 450), screens: [screen]), "ordinary desktop movements need no Dock AX lookup")
    }

    private static func clicks() {
        let icon = CGRect(x: 20, y: 20, width: 50, height: 50)
        func click(_ up: CGPoint = CGPoint(x: 40, y: 40), _ duration: TimeInterval = 0.1,
                   _ modifiers: Bool = false, _ count: Int = 1) -> Bool {
            DockPolicy.canMinimizeClick(down: CGPoint(x: 40, y: 40), up: up, icon: icon,
                                       duration: duration, modifiers: modifiers, clickCount: count)
        }
        expect(click(), "ordinary click may minimize")
        expect(click(CGPoint(x: 42, y: 40)), "small pointer jitter remains an ordinary click")
        expect(!click(CGPoint(x: 46, y: 40)), "dragging a Dock icon must retain system behavior")
        expect(!click(CGPoint(x: 200, y: 200)), "release outside icon must cancel minimization")
        expect(!click(CGPoint(x: 40, y: 40), 0.5), "long press must retain system behavior")
        expect(!click(CGPoint(x: 40, y: 40), 0.1, true), "modifier click must retain system behavior")
        expect(!click(CGPoint(x: 40, y: 40), 0.1, false, 2), "second click of double click must retain system behavior")
    }

    private static func keyboardSessions() {
        var session = CmdTabSession()
        expect(!session.flagsChanged(command: true), "Command down is not completion")
        expect(session.keyDown(code: 48, command: true), "a new Cmd+Tab session cancels recovery still pending from the previous switch")
        expect(!session.keyDown(code: 48, command: true), "repeated Tab within the same switch keeps the session armed")
        expect(session.flagsChanged(command: false), "Command release completes switching once")
        expect(!session.flagsChanged(command: false), "duplicate modifier event must not trigger another reopen")
        _ = session.keyDown(code: 48, command: true)
        expect(session.keyDown(code: 13, command: true), "Cmd+W cancels pending switching intent")
        expect(!session.flagsChanged(command: false), "Cmd+Tab followed by Cmd+W must not reopen after Command release")
        _ = session.keyDown(code: 48, command: true)
        expect(session.keyDown(code: 53, command: true), "Escape cancels switching")
        expect(!session.flagsChanged(command: false), "cancelled switch must not complete")
        _ = session.keyDown(code: 48, command: true)
        expect(!session.keyDown(code: 123, command: true), "arrow selection stays within switching session")
        expect(session.flagsChanged(command: false), "arrow selection still completes normally")
        expect(session.keyDown(code: 48, command: false), "plain Tab is not Cmd+Tab")
        expect(!session.flagsChanged(command: false), "plain Tab must not complete switching")
    }

    private static func preferences() {
        let suite = "com.ares.cmd.tab.windows.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = EnhancementSettings(defaults: defaults)
        expect(EnhancementFeature.allCases.allSatisfy { !settings.enabled($0) }, "new enhancements are opt-in")
        expect(settings.dockDisplayStyle == .titles, "Dock defaults to a label list without capture permission")
        var changes = 0
        settings.onChange = { changes += 1 }
        settings.set(.dockPreview, enabled: true)
        settings.set(.dockClickMinimize, enabled: true)
        settings.set(.dockPreview, enabled: false)
        expect(!settings.enabled(.dockPreview) && settings.enabled(.dockClickMinimize), "Dock switches must remain independent")
        expect(EnhancementSettings(defaults: defaults).enabled(.dockClickMinimize), "enhancement choices must persist")
        expect(changes == 3, "settings changes must notify the running controllers")
        settings.setDisplayStyle(.thumbnails)
        expect(EnhancementSettings(defaults: defaults).dockDisplayStyle == .thumbnails, "Dock display style persists independently")
        expect(changes == 4, "changing display style refreshes the running Dock controller")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        count += 1
        guard condition() else { fputs("window test failed: \(message)\n", stderr); exit(1) }
    }
}
