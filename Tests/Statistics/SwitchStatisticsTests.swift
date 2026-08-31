import Foundation

@main
private enum SwitchStatisticsTests {
    static func main() {
        let suite = "com.ares.cmd.tab.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(1) }
        defer { defaults.removePersistentDomain(forName: suite) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let store = SwitchStatisticsStore(defaults: defaults, calendar: calendar)
        let today = date(2026, 8, 31, calendar: calendar)
        store.record(bundleIdentifier: "com.example.old", displayName: "Old", at: date(2026, 8, 24, calendar: calendar))
        store.record(bundleIdentifier: "com.tencent.xinWeChat", displayName: "微信", at: date(2026, 8, 30, calendar: calendar))
        store.record(bundleIdentifier: "com.apple.finder", displayName: "Finder", at: today)
        store.record(bundleIdentifier: "com.apple.finder", displayName: "Finder", at: today)
        let snapshot = store.snapshot(at: today)
        expect(snapshot.days.count == 7, "snapshot must contain seven days")
        expect(snapshot.todayCount == 2, "today count must match records, got \(snapshot.todayCount)")
        expect(snapshot.sevenDayCount == 3, "expired records must be removed, got \(snapshot.sevenDayCount)")
        expect(snapshot.topApps.map(\.bundleIdentifier) == ["com.apple.finder", "com.tencent.xinWeChat"], "apps must be sorted by count")
        expect(snapshot.topApps.first?.displayName == "Finder", "display name must be retained")
        let stored = defaults.data(forKey: "switchStatistics.v1").map { String(decoding: $0, as: UTF8.self) } ?? ""
        expect(!stored.contains("com.example.old"), "expired app data must be deleted from storage")
        print("statistics tests passed")
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("statistics test failed: \(message)\n", stderr)
            exit(1)
        }
    }
}
