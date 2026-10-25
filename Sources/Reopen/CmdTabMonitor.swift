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

struct CmdTabSession {
    private var commandDown = false
    private var tabUsed = false

    mutating func flagsChanged(command: Bool) -> Bool {
        let completed = commandDown && !command && tabUsed
        commandDown = command
        if !command { tabUsed = false }
        return completed
    }

    mutating func keyDown(code: Int64, command: Bool) -> Bool {
        commandDown = command
        if command, code == 48 {
            let startsSession = !tabUsed
            tabUsed = true
            return startsSession
        }
        if tabUsed, command, [Int64(50), 123, 124].contains(code) { return false }
        tabUsed = false
        return true
    }
}

final class CmdTabMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var session = CmdTabSession()
    private let onCompleted: () -> Void
    private let onInterrupted: () -> Void

    init(onCompleted: @escaping () -> Void, onInterrupted: @escaping () -> Void = {}) {
        self.onCompleted = onCompleted
        self.onInterrupted = onInterrupted
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }
        guard CGPreflightListenEventAccess() else { return false }
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDown.rawValue)
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
        CFMachPortInvalidate(eventTap)
        self.eventTap = nil
        session = CmdTabSession()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .flagsChanged:
            if session.flagsChanged(command: event.flags.contains(.maskCommand)) { onCompleted() }
        case .keyDown:
            if session.keyDown(code: event.getIntegerValueField(.keyboardEventKeycode), command: event.flags.contains(.maskCommand)) {
                onInterrupted()
            }
        case .leftMouseDown, .rightMouseDown:
            session = CmdTabSession()
            onInterrupted()
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            session = CmdTabSession()
            onInterrupted()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
        default:
            break
        }
    }
}
