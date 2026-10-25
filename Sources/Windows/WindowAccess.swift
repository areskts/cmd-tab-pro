import AppKit
import ApplicationServices

// This private AX bridge links focus and visibility to the exact window; no Space-management APIs are used.
@_silgen_name("_AXUIElementGetWindow")
private func axWindowID(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AXRead {
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func id(_ element: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard axWindowID(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let position: CFTypeRef = value(element, kAXPositionAttribute),
              let size: CFTypeRef = value(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }
}

struct AppWindow {
    let element: AXUIElement
    let pid: pid_t
    var state: WindowState
    let title: String
    let frame: CGRect
}

struct WindowSnapshot {
    let windows: [AppWindow]
    let focusedID: CGWindowID?
    var states: [WindowState] { windows.map(\.state) }
}

final class WindowObservation {
    private var observer: AXObserver?
    private let onChange: () -> Void

    init?(pid: pid_t, windows: [AppWindow] = [], onChange: @escaping () -> Void) {
        self.onChange = onChange
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, context in
            guard let context else { return }
            let observation = Unmanaged<WindowObservation>.fromOpaque(context).takeUnretainedValue()
            observation.onChange()
        }, &observer) == .success, let observer else { return nil }
        self.observer = observer
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        let context = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXFocusedWindowChangedNotification, kAXWindowCreatedNotification, kAXApplicationHiddenNotification,
                     kAXApplicationShownNotification] {
            AXObserverAddNotification(observer, application, name as CFString, context)
        }
        for window in windows {
            for name in [kAXUIElementDestroyedNotification, kAXWindowMiniaturizedNotification,
                         kAXWindowDeminiaturizedNotification, kAXTitleChangedNotification] {
                AXObserverAddNotification(observer, window.element, name as CFString, context)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
    }

    deinit {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }
}

class WindowAccess {
    let queue = DispatchQueue(label: "com.ares.cmd.tab.windows", qos: .userInitiated)
    private var focusObservation: WindowObservation?
    private var observedPID: pid_t?
    private var recentWindows = [CGWindowID: TimeInterval]()

    func observeFocus(of app: NSRunningApplication?) {
        guard AXIsProcessTrusted(), let app, app.activationPolicy == .regular,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            focusObservation = nil
            observedPID = nil
            return
        }
        let pid = app.processIdentifier
        guard observedPID != pid else { return }
        observedPID = pid
        focusObservation = WindowObservation(pid: pid) { [weak self] in self?.rememberFocus(pid: pid) }
        rememberFocus(pid: pid)
    }

    func snapshot(pid: pid_t, completion: @escaping (WindowSnapshot?) -> Void) {
        guard pid != ProcessInfo.processInfo.processIdentifier, AXIsProcessTrusted() else { completion(nil); return }
        let recent = recentWindows
        queue.async {
            let snapshot = Self.readSnapshot(pid: pid, recent: recent)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    func restore(_ window: AppWindow, completion: @escaping (Bool) -> Void = { _ in }) {
        guard AXIsProcessTrusted(), let app = NSRunningApplication(processIdentifier: window.pid), !app.isTerminated else {
            completion(false)
            return
        }
        app.unhide()
        app.activate(options: [])
        queue.async {
            let minimized: Bool? = AXRead.value(window.element, kAXMinimizedAttribute)
            let restored = minimized != true || AXUIElementSetAttributeValue(
                window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse
            ) == .success
            let raised = restored && AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
            DispatchQueue.main.async { completion(raised) }
        }
    }

    func minimize(_ window: AppWindow, completion: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted(), !window.state.fullscreen else { completion(false); return }
        queue.async {
            let fullscreen: Bool = AXRead.value(window.element, "AXFullScreen") ?? false
            var settable = DarwinBoolean(false)
            let allowed = !fullscreen && AXUIElementIsAttributeSettable(
                window.element, kAXMinimizedAttribute as CFString, &settable
            ) == .success && settable.boolValue
            let success = allowed && AXUIElementSetAttributeValue(
                window.element, kAXMinimizedAttribute as CFString, kCFBooleanTrue
            ) == .success
            DispatchQueue.main.async { completion(success) }
        }
    }

    private func rememberFocus(pid: pid_t) {
        queue.async { [weak self] in
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.15)
            guard let element: AXUIElement = AXRead.value(application, kAXFocusedWindowAttribute),
                  let id = AXRead.id(element) else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.recentWindows.count > 256 { self.recentWindows.removeAll(keepingCapacity: true) }
                self.recentWindows[id] = ProcessInfo.processInfo.systemUptime
            }
        }
    }

    private static func readSnapshot(pid: pid_t, recent: [CGWindowID: TimeInterval]) -> WindowSnapshot? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.15)
        guard let elements: [AXUIElement] = AXRead.value(application, kAXWindowsAttribute),
              let cgWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
        // Finder includes its desktop AXScrollArea in AXWindows on macOS 27.
        let windowElements = isFinder ? elements.filter { (AXRead.value($0, kAXRoleAttribute) as String?) != kAXScrollAreaRole } : elements
        let onScreen = Set(cgWindows.compactMap { window -> CGWindowID? in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowIsOnscreen as String] as? Bool == true else { return nil }
            return window[kCGWindowNumber as String] as? CGWindowID
        })
        var windows = [AppWindow]()
        for element in windowElements {
            guard let role: String = AXRead.value(element, kAXRoleAttribute), role == kAXWindowRole else { return nil }
            let subrole: String? = AXRead.value(element, kAXSubroleAttribute)
            guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { continue }
            guard let id = AXRead.id(element), let minimized: Bool = AXRead.value(element, kAXMinimizedAttribute) else { return nil }
            let state = WindowState(id: id, minimized: minimized, onScreen: onScreen.contains(id),
                                    fullscreen: AXRead.value(element, "AXFullScreen") ?? false,
                                    main: AXRead.value(element, kAXMainAttribute) ?? false, lastUsed: recent[id] ?? 0)
            windows.append(AppWindow(element: element, pid: pid, state: state,
                                     title: AXRead.value(element, kAXTitleAttribute) ?? "未命名窗口",
                                     frame: AXRead.frame(element) ?? .zero))
        }
        guard windowElements.isEmpty || !windows.isEmpty else { return nil }
        let focused: AXUIElement? = AXRead.value(application, kAXFocusedWindowAttribute)
        return WindowSnapshot(windows: windows, focusedID: focused.flatMap(AXRead.id))
    }
}
