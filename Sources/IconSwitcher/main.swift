import Darwin
import Foundation

private let bundleIdentifier = "com.ares.cmd.tab"
private let defaults = UserDefaults(suiteName: bundleIdentifier)

private func run(_ executable: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    do {
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    } catch {
        return -1
    }
}

private func reopen(_ appPath: String) {
    _ = run("/usr/bin/open", [appPath])
}

private func storeError(_ message: String) {
    defaults?.set(message, forKey: "appIconSwitchError")
    defaults?.synchronize()
}

private func signAndVerify(_ appPath: String, signature: CodeSignature) -> Bool {
    let signed = run("/usr/bin/codesign", [
        "--force", "--options", "runtime", "--sign", signature.identity,
        "--identifier", bundleIdentifier, appPath
    ]) == 0
    return signed && verify(appPath) && (signature.identity == "-" || signature.matches(URL(fileURLWithPath: appPath)))
}

private func verify(_ appPath: String) -> Bool {
    run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appPath]) == 0
}

private func removeSelf() {
    try? FileManager.default.removeItem(atPath: CommandLine.arguments[0])
}

guard CommandLine.arguments.count == 5,
      let parentPid = pid_t(CommandLine.arguments[1]) else { exit(2) }
let appPath = CommandLine.arguments[2]
let sourceIconPath = CommandLine.arguments[3]
let option = CommandLine.arguments[4]
let appURL = URL(fileURLWithPath: appPath)
let sourceIconURL = URL(fileURLWithPath: sourceIconPath)
let resourcesURL = appURL.appendingPathComponent("Contents/Resources", isDirectory: true)
let iconOptionsURL = resourcesURL.appendingPathComponent("IconOptions", isDirectory: true)
let validSource = sourceIconURL.standardizedFileURL.path.hasPrefix(iconOptionsURL.standardizedFileURL.path + "/")
guard Bundle(url: appURL)?.bundleIdentifier == bundleIdentifier, validSource,
      AppIconOptionName.all.contains(option), FileManager.default.fileExists(atPath: sourceIconPath) else { exit(3) }

for _ in 0..<100 {
    if kill(parentPid, 0) != 0 { break }
    usleep(100_000)
}
if kill(parentPid, 0) == 0 {
    storeError("Cmd Tab Pro 未能正常退出，应用图标没有更改。")
    reopen(appPath)
    removeSelf()
    exit(4)
}

let fileManager = FileManager.default
let token = UUID().uuidString
let appParentURL = appURL.deletingLastPathComponent()
let stagedAppURL = appParentURL.appendingPathComponent(".CmdTabPro-\(token).app")
let backupName = ".CmdTabPro-backup-\(token).app"
let backupURL = appParentURL.appendingPathComponent(backupName)
let stagedResourcesURL = stagedAppURL.appendingPathComponent("Contents/Resources", isDirectory: true)
let stagedSourceIconURL = stagedResourcesURL.appendingPathComponent("IconOptions/\(sourceIconURL.lastPathComponent)")
let stagedDestinationIconURL = stagedResourcesURL.appendingPathComponent("AppIcon.icns")
do {
    guard let signature = CodeSignature(appURL) else { throw IconSwitchError.signingFailed }
    try fileManager.copyItem(at: appURL, to: stagedAppURL)
    try fileManager.removeItem(at: stagedDestinationIconURL)
    try fileManager.copyItem(at: stagedSourceIconURL, to: stagedDestinationIconURL)
    guard signAndVerify(stagedAppURL.path, signature: signature) else { throw IconSwitchError.signingFailed }
    _ = try fileManager.replaceItemAt(
        appURL, withItemAt: stagedAppURL, backupItemName: backupName,
        options: [.usingNewMetadataOnly, .withoutDeletingBackupItem]
    )
    try fileManager.setAttributes([.modificationDate: Date()], ofItemAtPath: appPath)
    guard verify(appPath) else { throw IconSwitchError.finalVerificationFailed }
    defaults?.set(option, forKey: "appIconOption")
    defaults?.removeObject(forKey: "appIconSwitchError")
    defaults?.synchronize()
    try? fileManager.removeItem(at: backupURL)
} catch {
    try? fileManager.removeItem(at: stagedAppURL)
    let restored = restoreOriginalApp(fileManager: fileManager, appURL: appURL, backupURL: backupURL)
    storeError(restored ? "无法切换应用图标，原应用未更改。" : "无法恢复 Cmd Tab Pro，请重新安装应用。备份保留在：\(backupURL.path)")
}
reopen(appPath)
removeSelf()

private enum IconSwitchError: Error {
    case signingFailed
    case finalVerificationFailed
}

private func restoreOriginalApp(fileManager: FileManager, appURL: URL, backupURL: URL) -> Bool {
    guard fileManager.fileExists(atPath: backupURL.path) else {
        return fileManager.fileExists(atPath: appURL.path) && verify(appURL.path)
    }
    do {
        if fileManager.fileExists(atPath: appURL.path) {
            _ = try fileManager.replaceItemAt(
                appURL, withItemAt: backupURL, backupItemName: nil, options: .usingNewMetadataOnly
            )
        } else {
            try fileManager.moveItem(at: backupURL, to: appURL)
        }
        return verify(appURL.path)
    } catch {
        return false
    }
}

private enum AppIconOptionName {
    static let all: Set<String> = ["option1", "option2", "option3"]
}
