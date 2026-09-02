import AppKit
import CoreGraphics

enum ReopenMode: String, CaseIterable {
    case automatic
    case compatible

    var title: String {
        switch self {
        case .automatic: return "增强自动模式"
        case .compatible: return "兼容模式"
        }
    }

    var description: String {
        switch self {
        case .automatic: return "需要输入监控权限，可处理更多无窗口场景"
        case .compatible: return "无需额外权限，从其他应用切回时唤回"
        }
    }
}

final class CmdTabMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var commandDown = false
    private var tabUsedInSession = false
    private let onCompleted: () -> Void

    init(onCompleted: @escaping () -> Void) {
        self.onCompleted = onCompleted
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CmdTabMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            }, userInfo: context
        ) else { return false }
        self.eventTap = eventTap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        return true
    }

    func stop() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        self.runLoopSource = nil
        self.eventTap = nil
        commandDown = false
        tabUsedInSession = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            let isCommandDown = event.flags.contains(.maskCommand)
            // macOS 常见顺序是先松 Tab、后松 Command，按会话是否使用过 Tab 判断结束。
            if commandDown && !isCommandDown && tabUsedInSession {
                onCompleted()
                tabUsedInSession = false
            }
            commandDown = isCommandDown
        case .keyDown:
            guard commandDown else { return }
            if event.getIntegerValueField(.keyboardEventKeycode) == 48 { tabUsedInSession = true }
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        default:
            break
        }
    }
}
