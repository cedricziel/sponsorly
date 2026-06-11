import Foundation

/// Identifies a cached report by everything that determines its contents.
struct ReportCacheKey: Hashable {
    let profileId: String
    let reportTypeId: String
    let startDate: String
    let endDate: String
    let timeUnit: String

    var filename: String {
        "\(profileId)_\(reportTypeId)_\(startDate)_\(endDate)_\(timeUnit).json"
            .replacingOccurrences(of: "/", with: "-")
    }
}

/// On-disk cache of decoded report rows. Past-day ranges are immutable (long
/// TTL); today-inclusive ranges use a short TTL.
actor ReportCache {
    static let immutableTTL: TimeInterval = 7 * 24 * 3600
    static let volatileTTL: TimeInterval = 300

    private let directory: URL

    init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.directory = caches.appendingPathComponent("Reports", isDirectory: true)
        }
    }

    func load(_ key: ReportCacheKey) -> [CampaignReportRow]? {
        guard let data = try? Data(contentsOf: fileURL(key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.expiresAt > Date()
        else {
            return nil
        }
        return entry.rows
    }

    func save(_ rows: [CampaignReportRow], for key: ReportCacheKey, ttl: TimeInterval) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let entry = Entry(rows: rows, expiresAt: Date().addingTimeInterval(ttl))
        if let data = try? JSONEncoder().encode(entry) {
            try? data.write(to: fileURL(key))
        }
    }

    private func fileURL(_ key: ReportCacheKey) -> URL {
        directory.appendingPathComponent(key.filename)
    }

    private struct Entry: Codable {
        let rows: [CampaignReportRow]
        let expiresAt: Date
    }
}
