import Foundation

enum AppEnvironment {
    static let apiBaseURL: String = {
        if let value = ProcessInfo.processInfo.environment["API_BASE_URL"],
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        if let value = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }

        #if targetEnvironment(simulator)
        return "http://127.0.0.1:3810"
        #else
        return "http://185.146.3.87/propmanager-api"
        #endif
    }()
}
