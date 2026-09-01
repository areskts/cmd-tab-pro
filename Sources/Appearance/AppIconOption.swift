import AppKit

enum AppIconOption: String, CaseIterable {
    case option1
    case option2
    case option3

    var title: String {
        switch self {
        case .option1: return "窗口切换"
        case .option2: return "Cmd+Tab"
        case .option3: return "窗口唤回"
        }
    }

    var resourceURL: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "icns", subdirectory: "IconOptions")
    }

    var image: NSImage {
        resourceURL.flatMap(NSImage.init(contentsOf:))
            ?? NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
    }

    static func current(defaults: UserDefaults = .standard) -> AppIconOption {
        guard let installed = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let installedData = try? Data(contentsOf: installed) else { return stored(defaults: defaults) }
        for option in allCases {
            guard let url = option.resourceURL, let data = try? Data(contentsOf: url), data == installedData else { continue }
            if defaults.string(forKey: "appIconOption") != option.rawValue { defaults.set(option.rawValue, forKey: "appIconOption") }
            return option
        }
        return stored(defaults: defaults)
    }

    private static func stored(defaults: UserDefaults) -> AppIconOption {
        guard let value = defaults.string(forKey: "appIconOption") else { return .option2 }
        return AppIconOption(rawValue: value) ?? .option2
    }
}
