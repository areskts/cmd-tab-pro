import AppKit
import Darwin

private let statePath = "/tmp/cmd-tab-pro-fixture-state"
private let readyPath = "/tmp/cmd-tab-pro-fixture-ready"
private let visibleReopenPath = "/tmp/cmd-tab-pro-fixture-visible-reopen"

private final class Delegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var closeSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        createWindow("opened")
        signal(SIGUSR1, SIG_IGN)
        closeSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        closeSignal?.setEventHandler { [weak self] in
            self?.window?.close()
            DispatchQueue.main.async { self?.window = nil }
            try? "closed".write(toFile: statePath, atomically: true, encoding: .utf8)
        }
        closeSignal?.resume()
        try? "ready".write(toFile: readyPath, atomically: true, encoding: .utf8)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if flag {
            let visibleCount = NSApp.windows.filter { $0.isVisible }.count
            try? String(visibleCount).write(toFile: visibleReopenPath, atomically: true, encoding: .utf8)
        } else {
            createWindow("reopened")
        }
        return true
    }

    private func createWindow(_ state: String) {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 320, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Cmd Tab Pro Acceptance Fixture"
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.makeKeyAndOrderFront(nil)
        self.window = window
        try? state.write(toFile: statePath, atomically: true, encoding: .utf8)
    }
}

let app = NSApplication.shared
private let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
