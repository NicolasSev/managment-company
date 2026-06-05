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

    enum LoginOutcome: Equatable {
        case authenticated
        case mfaRequired(token: String)
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
    
    func login(email: String, password: String) async throws -> LoginOutcome {
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

        let decoded = try JSONDecoder().decode(LoginAttemptResponse.self, from: data)
        if decoded.data.requiresMFA == true {
            guard let token = decoded.data.mfaToken, !token.isEmpty else {
                throw AuthError.loginFailed
            }
            return .mfaRequired(token: token)
        }

        guard let access = decoded.data.accessToken,
              let refresh = decoded.data.refreshToken,
              let nextUser = decoded.data.user else {
            throw AuthError.loginFailed
        }

        sessionExpiredMessage = nil
        persistTokens(access: access, refresh: refresh)
        user = nextUser
        isAuthenticated = true
        return .authenticated
    }

    func authenticateMFA(token mfaToken: String, code: String) async throws {
        let url = URL(string: "\(baseURL)/v1/auth/mfa/authenticate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(MFAAuthenticateInput(
            mfaToken: mfaToken,
            code: code.trimmingCharacters(in: .whitespacesAndNewlines)
        ))

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.networkUnavailable(baseURL, networkErrorDetails(error))
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.mfaFailed
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

    func forgotPassword(email: String) async throws {
        let url = URL(string: "\(baseURL)/v1/auth/forgot-password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ForgotPasswordInput(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines)
        ))

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AuthError.passwordRecoveryFailed
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.networkUnavailable(baseURL, networkErrorDetails(error))
        }
    }

    func resetPassword(token: String, newPassword: String) async throws {
        let url = URL(string: "\(baseURL)/v1/auth/reset-password")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ResetPasswordInput(
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            newPassword: newPassword
        ))

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw AuthError.passwordResetFailed
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.networkUnavailable(baseURL, networkErrorDetails(error))
        }
    }

    func setupMFA() async throws -> MFASetupResult {
        do {
            return try await APIClient.shared.request(
                "/v1/auth/mfa/setup",
                method: "POST",
                body: EmptyJSONBody(),
                tokenProvider: { await MainActor.run { self.accessToken } },
                refreshAndRetry: { await self.refreshToken() }
            )
        } catch {
            throw AuthError.mfaSetupFailed
        }
    }

    func verifyMFA(code: String) async throws {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/auth/mfa/verify",
                method: "POST",
                body: MFACodeInput(code: code.trimmingCharacters(in: .whitespacesAndNewlines)),
                tokenProvider: { await MainActor.run { self.accessToken } },
                refreshAndRetry: { await self.refreshToken() }
            )
            await fetchUserWithRecovery()
        } catch {
            throw AuthError.mfaFailed
        }
    }

    func disableMFA(code: String) async throws {
        do {
            _ = try await APIClient.shared.requestData(
                "/v1/auth/mfa/disable",
                method: "POST",
                body: MFACodeInput(code: code.trimmingCharacters(in: .whitespacesAndNewlines)),
                tokenProvider: { await MainActor.run { self.accessToken } },
                refreshAndRetry: { await self.refreshToken() }
            )
            await fetchUserWithRecovery()
        } catch {
            throw AuthError.mfaFailed
        }
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

private struct LoginAttemptResponse: Codable {
    let data: LoginAttemptData

    struct LoginAttemptData: Codable {
        let accessToken: String?
        let refreshToken: String?
        let user: AuthManager.User?
        let requiresMFA: Bool?
        let mfaToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case user
            case requiresMFA = "requires_mfa"
            case mfaToken = "mfa_token"
        }
    }
}

struct MFASetupResult: Codable {
    let otpauthURL: String
    let backupCodes: [String]

    enum CodingKeys: String, CodingKey {
        case otpauthURL = "otpauth_url"
        case backupCodes = "backup_codes"
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

private struct MFAAuthenticateInput: Encodable {
    let mfaToken: String
    let code: String

    enum CodingKeys: String, CodingKey {
        case mfaToken = "mfa_token"
        case code
    }
}

private struct MFACodeInput: Encodable {
    let code: String
}

private struct ForgotPasswordInput: Encodable {
    let email: String
}

private struct ResetPasswordInput: Encodable {
    let token: String
    let newPassword: String

    enum CodingKeys: String, CodingKey {
        case token
        case newPassword = "new_password"
    }
}

enum AuthError: LocalizedError {
    case loginFailed
    case registrationFailed
    case networkUnavailable(String, String)
    case mfaFailed
    case mfaSetupFailed
    case passwordRecoveryFailed
    case passwordResetFailed

    var errorDescription: String? {
        switch self {
        case .loginFailed:
            return "Ошибка входа. Проверьте email и пароль."
        case .registrationFailed:
            return "Не удалось зарегистрироваться. Проверьте введенные данные."
        case .networkUnavailable(let baseURL, let details):
            return "Не удалось подключиться к API по адресу \(baseURL). \(details)"
        case .mfaFailed:
            return "Не удалось подтвердить код. Проверьте код и попробуйте снова."
        case .mfaSetupFailed:
            return "Не удалось подготовить двухфакторную аутентификацию."
        case .passwordRecoveryFailed:
            return "Не удалось отправить письмо для восстановления пароля."
        case .passwordResetFailed:
            return "Не удалось сбросить пароль. Проверьте токен и новый пароль."
        }
    }
}
