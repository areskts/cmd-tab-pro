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

    init(statistics: SwitchStatisticsStore, isReopenEnabled: @escaping () -> Bool,
         setReopenEnabled: @escaping (Bool) -> Void, loginStatus: @escaping () -> SMAppService.Status,
         setLoginEnabled: @escaping (Bool) throws -> Void, interfaceTheme: @escaping () -> InterfaceTheme,
         setInterfaceTheme: @escaping (InterfaceTheme) -> Void, menuBarIconVisible: @escaping () -> Bool,
         setMenuBarIconVisible: @escaping (Bool) -> Void, appIconOption: @escaping () -> AppIconOption,
         setAppIconOption: @escaping (AppIconOption) -> Void, diagnosticText: @escaping () -> String,
         openReleases: @escaping () -> Void) {
        tabViewController = DashboardTabViewController(
            statistics: statistics, isReopenEnabled: isReopenEnabled, setReopenEnabled: setReopenEnabled,
            loginStatus: loginStatus, setLoginEnabled: setLoginEnabled, interfaceTheme: interfaceTheme,
            setInterfaceTheme: setInterfaceTheme, menuBarIconVisible: menuBarIconVisible,
            setMenuBarIconVisible: setMenuBarIconVisible, appIconOption: appIconOption,
            setAppIconOption: setAppIconOption, diagnosticText: diagnosticText, openReleases: openReleases
        )
        let contentSize = NSSize(width: 420, height: 460)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        super.init(window: window)
        window.contentViewController = tabViewController
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.backgroundColor = .textBackgroundColor
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
        show(selectedTab: 2)
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

    init(statistics: SwitchStatisticsStore, isReopenEnabled: @escaping () -> Bool,
         setReopenEnabled: @escaping (Bool) -> Void, loginStatus: @escaping () -> SMAppService.Status,
         setLoginEnabled: @escaping (Bool) throws -> Void, interfaceTheme: @escaping () -> InterfaceTheme,
         setInterfaceTheme: @escaping (InterfaceTheme) -> Void, menuBarIconVisible: @escaping () -> Bool,
         setMenuBarIconVisible: @escaping (Bool) -> Void, appIconOption: @escaping () -> AppIconOption,
         setAppIconOption: @escaping (AppIconOption) -> Void, diagnosticText: @escaping () -> String,
         openReleases: @escaping () -> Void) {
        generalViewController = GeneralViewController(
            isReopenEnabled: isReopenEnabled, setReopenEnabled: setReopenEnabled,
            loginStatus: loginStatus, setLoginEnabled: setLoginEnabled, interfaceTheme: interfaceTheme,
            setInterfaceTheme: setInterfaceTheme, menuBarIconVisible: menuBarIconVisible,
            setMenuBarIconVisible: setMenuBarIconVisible, appIconOption: appIconOption, setAppIconOption: setAppIconOption
        )
        statisticsViewController = StatisticsViewController(statistics: statistics)
        aboutViewController = AboutViewController(
            statistics: statistics, appIconOption: appIconOption, diagnosticText: diagnosticText, openReleases: openReleases
        )
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        addTab("通用", symbol: "gearshape", viewController: generalViewController)
        addTab("统计", symbol: "chart.bar.xaxis", viewController: statisticsViewController)
        addTab("关于", symbol: "info.circle", viewController: aboutViewController)
        selectedTabViewItemIndex = 0
    }

    required init?(coder: NSCoder) { nil }

    func refreshSelectedTab() {
        switch selectedTabViewItemIndex {
        case 0: generalViewController.refresh()
        case 1: statisticsViewController.refresh()
        case 2: aboutViewController.refresh()
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
