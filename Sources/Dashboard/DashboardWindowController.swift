import AppKit
import ServiceManagement

enum InterfaceTheme: String, CaseIterable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

final class DashboardWindowController: NSWindowController {
    private let tabViewController: DashboardTabViewController
    private var hasCentered = false

    init(statistics: SwitchStatisticsStore, enhancements: EnhancementSettings, isReopenEnabled: @escaping () -> Bool,
         setReopenEnabled: @escaping (Bool) -> Void, loginStatus: @escaping () -> SMAppService.Status,
         setLoginEnabled: @escaping (Bool) throws -> Void, interfaceTheme: @escaping () -> InterfaceTheme,
         setInterfaceTheme: @escaping (InterfaceTheme) -> Void, menuBarIconVisible: @escaping () -> Bool,
         setMenuBarIconVisible: @escaping (Bool) -> Void, appIconOption: @escaping () -> AppIconOption,
         setAppIconOption: @escaping (AppIconOption) -> Void, diagnosticText: @escaping () -> String,
         openReleases: @escaping () -> Void, reopenMode: @escaping () -> ReopenMode,
         setReopenMode: @escaping (ReopenMode) -> Void, restoreDefaults: @escaping () -> Void) {
        tabViewController = DashboardTabViewController(
            statistics: statistics, enhancements: enhancements, isReopenEnabled: isReopenEnabled, setReopenEnabled: setReopenEnabled,
            loginStatus: loginStatus, setLoginEnabled: setLoginEnabled, interfaceTheme: interfaceTheme,
            setInterfaceTheme: setInterfaceTheme, menuBarIconVisible: menuBarIconVisible,
            setMenuBarIconVisible: setMenuBarIconVisible, appIconOption: appIconOption,
            setAppIconOption: setAppIconOption, diagnosticText: diagnosticText, openReleases: openReleases,
            reopenMode: reopenMode, setReopenMode: setReopenMode,
            restoreDefaults: restoreDefaults
        )
        let contentSize = NSSize(width: 680, height: 620)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        super.init(window: window)
        window.contentViewController = tabViewController
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.isOpaque = false
        window.backgroundColor = .windowBackgroundColor
        window.title = "Cmd Tab Pro"
        window.titleVisibility = .hidden
        window.toolbarStyle = .expanded
        window.isReleasedWhenClosed = false
    }

    required init?(coder: NSCoder) { nil }

    func showDashboard() {
        show(selectedTab: nil)
    }

    func showAbout() {
        show(selectedTab: 3)
    }

    func refresh() {
        tabViewController.refreshSelectedTab()
    }

    private func show(selectedTab: Int?) {
        if let selectedTab { tabViewController.selectedTabViewItemIndex = selectedTab }
        tabViewController.refreshSelectedTab()
        if !hasCentered {
            window?.center()
            hasCentered = true
        }
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private final class DashboardTabViewController: NSTabViewController {
    private let generalViewController: GeneralViewController
    private let statisticsViewController: StatisticsViewController
    private let aboutViewController: AboutViewController
    private let enhancementsViewController: EnhancementsViewController

    init(statistics: SwitchStatisticsStore, enhancements: EnhancementSettings, isReopenEnabled: @escaping () -> Bool,
         setReopenEnabled: @escaping (Bool) -> Void, loginStatus: @escaping () -> SMAppService.Status,
         setLoginEnabled: @escaping (Bool) throws -> Void, interfaceTheme: @escaping () -> InterfaceTheme,
         setInterfaceTheme: @escaping (InterfaceTheme) -> Void, menuBarIconVisible: @escaping () -> Bool,
         setMenuBarIconVisible: @escaping (Bool) -> Void, appIconOption: @escaping () -> AppIconOption,
         setAppIconOption: @escaping (AppIconOption) -> Void, diagnosticText: @escaping () -> String,
         openReleases: @escaping () -> Void, reopenMode: @escaping () -> ReopenMode,
         setReopenMode: @escaping (ReopenMode) -> Void, restoreDefaults: @escaping () -> Void) {
        generalViewController = GeneralViewController(
            isReopenEnabled: isReopenEnabled, setReopenEnabled: setReopenEnabled,
            loginStatus: loginStatus, setLoginEnabled: setLoginEnabled, interfaceTheme: interfaceTheme,
            setInterfaceTheme: setInterfaceTheme, menuBarIconVisible: menuBarIconVisible,
            setMenuBarIconVisible: setMenuBarIconVisible, appIconOption: appIconOption, setAppIconOption: setAppIconOption,
            reopenMode: reopenMode, setReopenMode: setReopenMode
        )
        statisticsViewController = StatisticsViewController(statistics: statistics)
        aboutViewController = AboutViewController(
            statistics: statistics, appIconOption: appIconOption, diagnosticText: diagnosticText, openReleases: openReleases,
            restoreDefaults: restoreDefaults
        )
        enhancementsViewController = EnhancementsViewController(settings: enhancements)
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        addTab("切换设置", symbol: "rectangle.2.swap", viewController: generalViewController)
        addTab("Dock 预览", symbol: "dock.rectangle", viewController: enhancementsViewController)
        addTab("统计", symbol: "chart.bar.xaxis", viewController: statisticsViewController)
        addTab("关于", symbol: "info.circle", viewController: aboutViewController)
        selectedTabViewItemIndex = 0
    }

    required init?(coder: NSCoder) { nil }

    func refreshSelectedTab() {
        switch selectedTabViewItemIndex {
        case 0: generalViewController.refresh()
        case 1: enhancementsViewController.refresh()
        case 2: statisticsViewController.refresh()
        case 3: aboutViewController.refresh()
        default: break
        }
    }

    private func addTab(_ label: String, symbol: String, viewController: NSViewController) {
        let item = NSTabViewItem(viewController: viewController)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        addTabViewItem(item)
    }
}
