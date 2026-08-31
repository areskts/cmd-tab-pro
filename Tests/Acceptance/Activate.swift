import AppKit
import Darwin

guard CommandLine.arguments.count >= 2,
      let app = NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]).first else {
    exit(2)
}
if CommandLine.arguments.contains("--terminate") {
    exit(app.terminate() ? 0 : 3)
}
let activated = app.activate(options: [.activateAllWindows])
usleep(600_000)
exit(activated ? 0 : 3)
