import Foundation

struct DailySwitchSummary: Equatable {
    let date: Date
    let count: Int
}

struct AppSwitchSummary: Equatable {
    let bundleIdentifier: String
    let displayName: String
    let count: Int
}

struct SwitchStatisticsSnapshot: Equatable {
    let days: [DailySwitchSummary]
    let topApps: [AppSwitchSummary]

    var todayCount: Int { days.last?.count ?? 0 }
    var sevenDayCount: Int { days.reduce(0) { $0 + $1.count } }
}

extension Notification.Name {
    static let switchStatisticsDidChange = Notification.Name("SwitchStatisticsDidChange")
}

final class SwitchStatisticsStore {
    private struct StoredApp: Codable {
        var displayName: String
        var count: Int
    }

    private struct StoredDay: Codable {
        var count = 0
        var apps = [String: StoredApp]()
    }

    private struct StoredStatistics: Codable {
        var days = [String: StoredDay]()
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let storageKey = "switchStatistics.v1"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .autoupdatingCurrent) {
        self.defaults = defaults
        self.calendar = calendar
        prune()
    }

    func record(bundleIdentifier: String, displayName: String, at date: Date = Date()) {
        var statistics = load()
        retainRecentDays(in: &statistics, relativeTo: date)
        let key = dayKey(for: date)
        var day = statistics.days[key] ?? StoredDay()
        var app = day.apps[bundleIdentifier] ?? StoredApp(displayName: displayName, count: 0)
        app.displayName = displayName
        app.count += 1
        day.count += 1
        day.apps[bundleIdentifier] = app
        statistics.days[key] = day
        save(statistics)
        NotificationCenter.default.post(name: .switchStatisticsDidChange, object: self)
    }

    func snapshot(at date: Date = Date()) -> SwitchStatisticsSnapshot {
        var statistics = load()
        let originalDayCount = statistics.days.count
        retainRecentDays(in: &statistics, relativeTo: date)
        if statistics.days.count != originalDayCount { save(statistics) }
        let dates = recentDates(relativeTo: date)
        let days = dates.map { day in
            DailySwitchSummary(date: day, count: statistics.days[dayKey(for: day)]?.count ?? 0)
        }
        var apps = [String: StoredApp]()
        for day in dates.compactMap({ statistics.days[dayKey(for: $0)] }) {
            for (identifier, value) in day.apps {
                var total = apps[identifier] ?? StoredApp(displayName: value.displayName, count: 0)
                total.displayName = value.displayName
                total.count += value.count
                apps[identifier] = total
            }
        }
        let summaries = apps.map { entry in
            AppSwitchSummary(bundleIdentifier: entry.key, displayName: entry.value.displayName, count: entry.value.count)
        }
        let sorted = summaries.sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.displayName < rhs.displayName : lhs.count > rhs.count
        }
        return SwitchStatisticsSnapshot(days: days, topApps: Array(sorted.prefix(5)))
    }

    func clear() {
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: .switchStatisticsDidChange, object: self)
    }

    private func prune(at date: Date = Date()) {
        var statistics = load()
        let original = statistics.days.count
        retainRecentDays(in: &statistics, relativeTo: date)
        guard statistics.days.count != original else { return }
        save(statistics)
    }

    private func retainRecentDays(in statistics: inout StoredStatistics, relativeTo date: Date) {
        let validKeys = Set(recentDates(relativeTo: date).map(dayKey))
        statistics.days = statistics.days.filter { validKeys.contains($0.key) }
    }

    private func recentDates(relativeTo date: Date) -> [Date] {
        let today = calendar.startOfDay(for: date)
        return (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func load() -> StoredStatistics {
        guard let data = defaults.data(forKey: storageKey),
              let statistics = try? JSONDecoder().decode(StoredStatistics.self, from: data) else { return StoredStatistics() }
        return statistics
    }

    private func save(_ statistics: StoredStatistics) {
        guard let data = try? JSONEncoder().encode(statistics) else { return }
        defaults.set(data, forKey: storageKey)
    }
}
