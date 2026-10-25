import AppKit
import ApplicationServices

struct DockTarget {
    let app: NSRunningApplication
    let frame: CGRect
}

final class DockController {
    private let access: WindowAccess
    private let settings: EnhancementSettings
    private let targetAtPoint: (CGPoint) -> DockTarget?
    private let willAct: (pid_t) -> Void
    private let preview = DockPreviewPanel()
    private let capture = WindowPreviewCapture()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var interceptsClicks = false
    private var target: DockTarget?
    private var snapshot: WindowSnapshot?
    private var snapshotPending = false
    private var observation: WindowObservation?
    private var generation = 0
    private var hitGeneration = 0
    private var clickGeneration = 0
    private var hitWork: DispatchWorkItem?
    private var showWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    private var holdWork: DispatchWorkItem?
    private var pendingDown: (event: CGEvent, window: AppWindow, icon: CGRect, time: TimeInterval)?
    private let replayTag: Int64 = 0x4354505245504c

    init(access: WindowAccess, settings: EnhancementSettings,
         targetAtPoint: @escaping (CGPoint) -> DockTarget? = DockController.dockTarget,
         willAct: @escaping (pid_t) -> Void) {
        self.access = access
        self.settings = settings
        self.targetAtPoint = targetAtPoint
        self.willAct = willAct
    }

    func configure(active: Bool) {
        guard active, settings.accessibilityGranted,
              settings.enabled(.dockPreview) || settings.enabled(.dockClickMinimize) else { stop(); return }
        if globalMonitor == nil {
            let events: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] in self?.handle($0) }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
                self?.handle(event)
                return event
            }
        }
        clearTarget()
        installTap(interceptClicks: settings.enabled(.dockClickMinimize))
        if !settings.enabled(.dockPreview) { dismissPreview() }
    }

    func stop() {
        clickGeneration += 1
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        clearTarget()
        removeTap()
    }

    func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            clickGeneration += 1
            if event.keyCode == 53 { clearTarget() }
            return
        }
        let point = NSEvent.mouseLocation
        if event.type == .scrollWheel {
            if !preview.isVisible || !preview.frame.contains(point) { clearTarget() }
            return
        }
        if event.type == .rightMouseDown { clickGeneration += 1 }
        if !preview.isVisible || !preview.frame.contains(point) { clearTarget() }
    }

    func pointerMoved(to cgPoint: CGPoint) {
        hitGeneration += 1
        hitWork?.cancel()
        let desktopTop = NSScreen.screens.first?.frame.maxY ?? 0
        let point = CGPoint(x: cgPoint.x, y: desktopTop - cgPoint.y)
        if preview.isVisible, preview.frame.insetBy(dx: -5, dy: -5).contains(point) {
            hideWork?.cancel()
            return
        }
        if let target, target.frame.contains(cgPoint) {
            hideWork?.cancel()
            if snapshot == nil { refreshWindows() }
        } else {
            scheduleHide()
        }
        guard DockPolicy.nearEdge(point, screens: NSScreen.screens.map(\.frame)) else { return }
        let request = hitGeneration
        let work = DispatchWorkItem { [weak self] in
            let hit = self?.targetAtPoint(cgPoint)
            DispatchQueue.main.async { [weak self] in
                guard let self, request == self.hitGeneration else { return }
                if let hit { self.hover(hit) } else { self.scheduleHide() }
            }
        }
        hitWork = work
        access.queue.asyncAfter(deadline: .now() + .milliseconds(16), execute: work)
    }

    static func dockTarget(at point: CGPoint) -> DockTarget? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let application = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.1)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(point.x), Float(point.y), &element) == .success,
              var item = element else { return nil }
        for _ in 0..<6 {
            let subrole: String? = AXRead.value(item, kAXSubroleAttribute)
            if subrole == "AXApplicationDockItem" {
                guard let url: URL = AXRead.value(item, kAXURLAttribute), let frame = AXRead.frame(item),
                      let app = NSWorkspace.shared.runningApplications.first(where: {
                          $0.bundleURL?.standardizedFileURL == url.standardizedFileURL
                      }), app.activationPolicy == .regular, !app.isTerminated else { return nil }
                return DockTarget(app: app, frame: frame)
            }
            guard let parent: AXUIElement = AXRead.value(item, kAXParentAttribute) else { return nil }
            item = parent
        }
        return nil
    }

    func hover(_ hit: DockTarget) {
        hideWork?.cancel()
        if let target, target.app.processIdentifier == hit.app.processIdentifier {
            self.target = hit
            return
        }
        clearTarget()
        target = hit
        refreshWindows()
    }

    private func refreshWindows() {
        guard let target, !snapshotPending else { return }
        snapshotPending = true
        let request = generation
        let pid = target.app.processIdentifier
        access.snapshot(pid: pid) { [weak self] snapshot in
            guard let self, request == self.generation, self.target?.app.processIdentifier == pid else { return }
            self.snapshotPending = false
            self.snapshot = snapshot
            guard let snapshot else { self.dismissPreview(); return }
            self.observation = WindowObservation(pid: pid, windows: snapshot.windows) { [weak self] in
                self?.showWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.refreshWindows() }
                self?.showWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50), execute: work)
            }
            guard !snapshot.windows.isEmpty, self.settings.enabled(.dockPreview) else { self.dismissPreview(); return }
            self.showWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.showPreview(request: request) }
            self.showWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(self.preview.isVisible ? 0 : 250), execute: work)
        }
    }

    private func showPreview(request: Int) {
        guard request == generation, let target, let snapshot, !snapshot.windows.isEmpty,
              settings.enabled(.dockPreview), !target.app.isTerminated else { return }
        let anchor = DockPolicy.appKitFrame(target.frame, desktopTop: NSScreen.screens.first?.frame.maxY ?? 0)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) else { return }
        let style = settings.dockDisplayStyle
        preview.show(app: target.app, windows: snapshot.windows, anchor: anchor, screen: screen,
                     style: style, capture: style == .thumbnails ? capture : nil) { [weak self] in
            self?.select($0)
        }
        if style == .thumbnails {
            capture.load(snapshot.windows) { [weak self] id, image in self?.preview.setImage(image, for: id) }
        }
    }

    private func select(_ window: AppWindow) {
        let pid = window.pid
        let request = clickGeneration
        access.snapshot(pid: pid) { [weak self] current in
            guard let self, request == self.clickGeneration, self.settings.enabled(.dockPreview),
                  let current, let live = current.windows.first(where: { $0.state.id == window.state.id }),
                  let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
            let minimize = self.settings.enabled(.dockClickMinimize) && WindowPolicy.minimizeTarget(
                windows: current.states, focusedID: current.focusedID,
                frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, hidden: app.isHidden
            ) == live.state.id
            self.willAct(pid)
            self.clearTarget()
            if minimize {
                self.access.minimize(live) { _ in }
            } else {
                self.access.restore(live)
            }
        }
    }

    private func scheduleHide() {
        guard target != nil, hideWork?.isCancelled != false else { return }
        let work = DispatchWorkItem { [weak self] in self?.clearTarget() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180), execute: work)
    }

    private func clearTarget() {
        generation += 1
        hitGeneration += 1
        target = nil
        snapshot = nil
        snapshotPending = false
        observation = nil
        hitWork?.cancel()
        hideWork?.cancel()
        dismissPreview()
    }

    private func dismissPreview() {
        showWork?.cancel()
        capture.stop()
        preview.hide()
    }

    private func installTap(interceptClicks: Bool) {
        if tap != nil, interceptsClicks != interceptClicks { removeTap() }
        guard tap == nil else { return }
        interceptsClicks = interceptClicks
        let mask = [CGEventType.mouseMoved, .leftMouseDown, .rightMouseDown, .leftMouseUp, .leftMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                               options: interceptClicks ? .defaultTap : .listenOnly,
                               eventsOfInterest: mask, callback: { proxy, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<DockController>.fromOpaque(context).takeUnretainedValue()
            return controller.mouseEvent(proxy: proxy, type: type, event: event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        settings.dockObserverAvailable = tap != nil
        settings.dockTapAvailable = interceptClicks && tap != nil
        guard let tap else { return }
        tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let tapSource { CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        replayPendingDown()
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        tapSource = nil
        settings.dockObserverAvailable = false
        settings.dockTapAvailable = false
    }

    private func mouseEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            replayPendingDown()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != replayTag else { return Unmanaged.passUnretained(event) }
        if type == .mouseMoved {
            pointerMoved(to: event.location)
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDown {
            clickGeneration += 1
            return interceptsClicks ? mouseDown(event) : Unmanaged.passUnretained(event)
        }
        guard interceptsClicks else { return Unmanaged.passUnretained(event) }
        guard let pending = pendingDown else { return Unmanaged.passUnretained(event) }
        if type == .leftMouseDragged {
            if hypot(event.location.x - pending.event.location.x, event.location.y - pending.event.location.y) >= 4 {
                pendingDown = nil
                holdWork?.cancel()
                pending.event.tapPostEvent(proxy)
                return Unmanaged.passUnretained(event)
            }
            return nil
        }
        guard type == .leftMouseUp else { return Unmanaged.passUnretained(event) }
        pendingDown = nil
        holdWork?.cancel()
        let minimize = NSWorkspace.shared.frontmostApplication?.processIdentifier == pending.window.pid && DockPolicy.canMinimizeClick(
            down: pending.event.location, up: event.location, icon: pending.icon,
            duration: ProcessInfo.processInfo.systemUptime - pending.time, modifiers: hasModifiers(event),
            clickCount: Int(event.getIntegerValueField(.mouseEventClickState))
        )
        guard minimize, let release = event.copy() else {
            pending.event.tapPostEvent(proxy)
            return Unmanaged.passUnretained(event)
        }
        clearTarget()
        confirmClick(window: pending.window, down: pending.event, release: release, request: clickGeneration)
        return nil
    }

    private func confirmClick(window: AppWindow, down: CGEvent, release: CGEvent, request: Int) {
        // Dock magnification moves icon frames; recheck the application at release before minimizing.
        access.queue.async { [weak self] in
            let hit = self?.targetAtPoint(release.location)
            DispatchQueue.main.async { [weak self] in
                guard let self, request == self.clickGeneration else { return }
                guard hit?.app.processIdentifier == window.pid else { self.replay(down, release); return }
                self.access.snapshot(pid: window.pid) { [weak self] snapshot in
                    guard let self, request == self.clickGeneration else { return }
                    guard let snapshot, self.settings.enabled(.dockClickMinimize),
                          let id = WindowPolicy.minimizeTarget(windows: snapshot.states, focusedID: snapshot.focusedID,
                              frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == window.pid,
                              hidden: hit?.app.isHidden ?? true),
                          let target = snapshot.windows.first(where: { $0.state.id == id }) else {
                        self.replay(down, release)
                        return
                    }
                    self.willAct(window.pid)
                    self.access.minimize(target) { [weak self] success in
                        guard let self, !success, request == self.clickGeneration else { return }
                        self.replay(down, release)
                    }
                }
            }
        }
    }

    private func replay(_ down: CGEvent, _ release: CGEvent) {
        post(down)
        post(release)
    }

    private func mouseDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard !hasModifiers(event), event.getIntegerValueField(.mouseEventClickState) == 1,
              let target, target.frame.contains(event.location), let snapshot,
              let id = WindowPolicy.minimizeTarget(windows: snapshot.states, focusedID: snapshot.focusedID,
                  frontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == target.app.processIdentifier,
                  hidden: target.app.isHidden),
              let window = snapshot.windows.first(where: { $0.state.id == id }), let down = event.copy() else {
            return Unmanaged.passUnretained(event)
        }
        pendingDown = (down, window, target.frame, ProcessInfo.processInfo.systemUptime)
        let work = DispatchWorkItem { [weak self] in self?.replayPendingDown() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400), execute: work)
        return nil
    }

    private func replayPendingDown() {
        holdWork?.cancel()
        guard let pending = pendingDown else { return }
        pendingDown = nil
        post(pending.event)
    }

    private func post(_ event: CGEvent) {
        event.setIntegerValueField(.eventSourceUserData, value: replayTag)
        event.post(tap: .cgSessionEventTap)
    }

    private func hasModifiers(_ event: CGEvent) -> Bool {
        !event.flags.intersection([.maskCommand, .maskControl, .maskShift, .maskAlternate, .maskSecondaryFn]).isEmpty
    }
}
