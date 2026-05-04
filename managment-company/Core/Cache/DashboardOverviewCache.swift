import Foundation

/// Последний успешный снимок «Главной» для офлайн-режима и плохой сети.
struct DashboardOverviewSnapshot: Codable {
    let userId: String
    let properties: [Property]
    let tasks: [AppTask]
    let analytics: AnalyticsDashboard?
    let occupancy: OccupancyPayload?
    let savedAt: Date
}

enum DashboardOverviewCache {
    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("dashboard-overview-cache.json", isDirectory: false)
    }

    static func load() -> DashboardOverviewSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(DashboardOverviewSnapshot.self, from: data)
    }

    static func save(_ snapshot: DashboardOverviewSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // без кэша приложение продолжит работать
        }
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
