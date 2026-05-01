import Foundation
import Combine

@MainActor
class AuthManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var accessToken: String?
    @Published var user: User?
    /// Shown when refresh fails on cold start or when `/me` returns 401.
    @Published var sessionExpiredMessage: String?
    
    private let keychain = KeychainManager.shared
    private let baseURL = AppEnvironment.apiBaseURL
    
    struct User: Codable {
        let id: String
        let email: String
        let name: String?
        let timezone: String
        let baseCurrency: String
        /// Optional fields returned by `/v1/auth/me` (contract `User`).
        let mfaEnabled: Bool?
        let theme: String?
        let locale: String?

        enum CodingKeys: String, CodingKey {
            case id, email, name, timezone
            case baseCurrency = "base_currency"
            case mfaEnabled = "mfa_enabled"
            case theme, locale
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            email = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
            name = try container.decodeIfPresent(String.self, forKey: .name)
            timezone = try container.decodeIfPresent(String.self, forKey: .timezone) ?? "Asia/Almaty"
            baseCurrency = try container.decodeIfPresent(String.self, forKey: .baseCurrency) ?? "KZT"
            mfaEnabled = try container.decodeIfPresent(Bool.self, forKey: .mfaEnabled)
            theme = try container.decodeIfPresent(String.self, forKey: .theme)
            locale = try container.decodeIfPresent(String.self, forKey: .locale)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(email, forKey: .email)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encode(timezone, forKey: .timezone)
            try container.encode(baseCurrency, forKey: .baseCurrency)
            try container.encodeIfPresent(mfaEnabled, forKey: .mfaEnabled)
            try container.encodeIfPresent(theme, forKey: .theme)
            try container.encodeIfPresent(locale, forKey: .locale)
        }
    }
    
    init() {
        restoreFromKeychain()
    }
    
    private func restoreFromKeychain() {
        accessToken = keychain.getAccessToken()
        if keychain.getRefreshToken() != nil {
            Task { await restoreSessionUsingRefresh() }
            return
        }
        if accessToken != nil {
            isAuthenticated = true
            Task { await fetchUserWithRecovery() }
        }
    }

    private func restoreSessionUsingRefresh() async {
        let ok = await refreshToken()
        if ok {
            sessionExpiredMessage = nil
            isAuthenticated = true
            return
        }
        sessionExpiredMessage = "Сессия истекла. Войдите снова."
    }

    func acknowledgeSessionExpired() {
        sessionExpiredMessage = nil
    }
    
    private func persistTokens(access: String, refresh: String) {
        _ = keychain.storeTokens(access: access, refresh: refresh)
        accessToken = access
    }
    
    /// Refreshes tokens using stored refresh token. Returns true if successful.
    func refreshToken() async -> Bool {
        guard let refresh = keychain.getRefreshToken() else { return false }
        let url = URL(string: "\(baseURL)/v1/auth/refresh")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["refresh_token": refresh])
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                clearTokens()
                return false
            }
            let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
            persistTokens(access: decoded.data.accessToken, refresh: decoded.data.refreshToken)
            user = decoded.data.user
            isAuthenticated = true
            return true
        } catch {
            clearTokens()
            return false
        }
    }
    
    private func clearTokens() {
        _ = keychain.clearTokens()
        accessToken = nil
        user = nil
        isAuthenticated = false
    }
    
    private func fetchUserWithRecovery() async {
        guard let token = accessToken,
              let url = URL(string: "\(baseURL)/v1/auth/me") else { return }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                if await refreshToken() { return }
                sessionExpiredMessage = "Сессия истекла. Войдите снова."
                return
            }
            guard (200...299).contains(http.statusCode) else { return }
            user = try JSONDecoder().decode(APIUserResponse.self, from: data).data
        } catch {
            if await refreshToken() { return }
        }
    }
    
    func login(email: String, password: String) async throws {
        let url = URL(string: "\(baseURL)/v1/auth/login")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email, "password": password])
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkUnavailable(baseURL, networkErrorDetails(error))
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.loginFailed
        }
        
        let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
        sessionExpiredMessage = nil
        persistTokens(access: decoded.data.accessToken, refresh: decoded.data.refreshToken)
        user = decoded.data.user
        isAuthenticated = true
    }
    
    func register(email: String, password: String, name: String) async throws {
        let url = URL(string: "\(baseURL)/v1/auth/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "email": email,
            "password": password,
            "name": name
        ])
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkUnavailable(baseURL, networkErrorDetails(error))
        }
        guard let http = response as? HTTPURLResponse, (200...201).contains(http.statusCode) else {
            throw AuthError.registrationFailed
        }
        
        let decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
        sessionExpiredMessage = nil
        persistTokens(access: decoded.data.accessToken, refresh: decoded.data.refreshToken)
        user = decoded.data.user
        isAuthenticated = true
    }
    
    func logout() {
        clearTokens()
    }

    func updateProfile(name: String, timezone: String, baseCurrency: String) async throws {
        let updatedUser: User = try await APIClient.shared.request(
            "/v1/auth/me",
            method: "PUT",
            body: ProfileUpdateInput(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                timezone: timezone.trimmingCharacters(in: .whitespacesAndNewlines),
                baseCurrency: baseCurrency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            ),
            tokenProvider: { await MainActor.run { self.accessToken } },
            refreshAndRetry: { await self.refreshToken() }
        )

        user = updatedUser
    }
    
    func authorizedRequest(_ path: String) -> URLRequest? {
        guard let token = accessToken,
              let url = URL(string: "\(baseURL)\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func networkErrorDetails(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return "\(urlError.localizedDescription) (\(urlError.code.rawValue))"
        }
        return error.localizedDescription
    }
}

struct LoginResponse: Codable {
    let data: LoginData
    struct LoginData: Codable {
        let accessToken: String
        let refreshToken: String
        let user: AuthManager.User
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
        }
    }
}

private struct ProfileUpdateInput: Encodable {
    let name: String
    let timezone: String
    let baseCurrency: String

    enum CodingKeys: String, CodingKey {
        case name, timezone
        case baseCurrency = "base_currency"
    }
}

private struct APIUserResponse: Codable {
    let data: AuthManager.User
}

enum AuthError: LocalizedError {
    case loginFailed
    case registrationFailed
    case networkUnavailable(String, String)

    var errorDescription: String? {
        switch self {
        case .loginFailed:
            return "Ошибка входа. Проверьте email и пароль."
        case .registrationFailed:
            return "Не удалось зарегистрироваться. Проверьте введенные данные."
        case .networkUnavailable(let baseURL, let details):
            return "Не удалось подключиться к API по адресу \(baseURL). \(details)"
        }
    }
}
