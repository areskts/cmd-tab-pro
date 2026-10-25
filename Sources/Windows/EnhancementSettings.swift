import AppKit
import ApplicationServices

enum EnhancementFeature: String, CaseIterable {
    case windowRecovery
    case dockPreview
    case dockClickMinimize

    var title: String {
        switch self {
        case .windowRecovery: return "恢复隐藏和最小化窗口"
        case .dockPreview: return "Dock 悬停面板"
        case .dockClickMinimize: return "点击最小化"
        }
    }
}

enum DockDisplayStyle: String, CaseIterable {
    case titles
    case thumbnails

    var title: String { self == .titles ? "标签列表" : "窗口缩略图" }
}

final class EnhancementSettings {
    private let defaults: UserDefaults
    var onChange: () -> Void = {}
    var dockTapAvailable = false
    var dockObserverAvailable = false
    var accessibilityGranted: Bool { AXIsProcessTrusted() }
    var screenCaptureGranted: Bool { CGPreflightScreenCaptureAccess() }
    var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }
    var dockDisplayStyle: DockDisplayStyle {
        DockDisplayStyle(rawValue: defaults.string(forKey: "dockDisplayStyle") ?? "") ?? .titles
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func enabled(_ feature: EnhancementFeature) -> Bool {
        defaults.bool(forKey: feature.rawValue + "Enabled")
    }

    func set(_ feature: EnhancementFeature, enabled: Bool) {
        defaults.set(enabled, forKey: feature.rawValue + "Enabled")
        onChange()
    }

    func setDisplayStyle(_ style: DockDisplayStyle) {
        defaults.set(style.rawValue, forKey: "dockDisplayStyle")
        onChange()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenCapture() {
        guard !screenCaptureGranted else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    func requestInputMonitoring() {
        if !inputMonitoringGranted { _ = CGRequestListenEventAccess() }
        // The request API may return silently, so open the permission pane explicitly.
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
