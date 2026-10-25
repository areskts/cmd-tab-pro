import Foundation

struct WindowState: Equatable {
    let id: UInt32
    var minimized = false
    var onScreen = false
    var fullscreen = false
    var main = false
    var lastUsed: TimeInterval = 0
}

enum WindowRecoveryAction: Equatable {
    case none
    case reopen
    case focus(UInt32)
    case restore(UInt32)
}

enum WindowPolicy {
    static func recovery(windows: [WindowState]?, hidden: Bool) -> WindowRecoveryAction {
        guard let windows else { return .none }
        guard !windows.isEmpty else { return .reopen }
        let ordinary = windows.filter { !$0.minimized }
        if let window = preferred(ordinary) { return hidden ? .focus(window.id) : .none }
        guard let window = preferred(windows) else { return .none }
        return .restore(window.id)
    }

    static func minimizeTarget(windows: [WindowState], focusedID: UInt32?, frontmost: Bool, hidden: Bool) -> UInt32? {
        guard frontmost, !hidden, let focusedID,
              let window = windows.first(where: { $0.id == focusedID }),
              window.onScreen, !window.minimized, !window.fullscreen else { return nil }
        return window.id
    }

    private static func preferred(_ windows: [WindowState]) -> WindowState? {
        if let recent = windows.max(by: { $0.lastUsed < $1.lastUsed }), recent.lastUsed > 0 { return recent }
        return windows.first(where: { $0.main }) ?? windows.first
    }
}
