import Foundation

enum APIURLBuilder {
    /// Joins API base URL with a relative download path from the backend (e.g. `/v1/files/...`).
    static func absoluteDownloadURL(base: String, downloadPath: String) -> URL? {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if downloadPath.lowercased().hasPrefix("http") {
            return URL(string: downloadPath)
        }
        let baseClean = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let path = downloadPath.hasPrefix("/") ? downloadPath : "/" + downloadPath
        return URL(string: baseClean + path)
    }
}
