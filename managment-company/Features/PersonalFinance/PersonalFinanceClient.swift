import Foundation

/// Клиент portfolio-dashboard API. Не использует `APIClient` PropManager:
/// другой base URL, другой токен, ответы без обёртки `{ "data": … }` и без refresh-флоу.
/// Stateless, поэтому не привязан к MainActor (в отличие от view model).
protocol PersonalFinanceClient: Sendable {
    func fetchAccounts() async throws -> [PFAccount]
    func fetchCategories() async throws -> [PFCategory]
    func fetchDefaults() async throws -> PFDefaults
    func submitTransaction(_ request: PFTransactionRequest) async throws -> PFTransaction
}

struct LivePersonalFinanceClient: PersonalFinanceClient {
    var session: URLSession = .shared

    func fetchAccounts() async throws -> [PFAccount] {
        try await get("/api/accounts")
    }

    func fetchCategories() async throws -> [PFCategory] {
        let categories: [PFCategory] = try await get("/api/transaction-categories")
        return categories.filter(\.isActive)
    }

    func fetchDefaults() async throws -> PFDefaults {
        try await get("/api/transactions/defaults")
    }

    func submitTransaction(_ request: PFTransactionRequest) async throws -> PFTransaction {
        var urlRequest = try buildRequest(path: "/api/transactions", method: "POST")
        urlRequest.httpBody = try JSONEncoder().encode(request)
        return try await perform(urlRequest)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(buildRequest(path: path, method: "GET"))
    }

    private func buildRequest(path: String, method: String) throws -> URLRequest {
        guard PersonalFinanceSettings.isConfigured, let token = PersonalFinanceSettings.token else {
            throw PFError.notConfigured
        }
        guard let url = URL(string: "\(PersonalFinanceSettings.baseURL)\(path)") else {
            throw PFError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else {
            throw PFError.invalidResponse
        }
        if status == 401 { throw PFError.unauthorized }
        guard (200...299).contains(status) else { throw PFError.httpStatus(status) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PFError.invalidResponse
        }
    }
}
