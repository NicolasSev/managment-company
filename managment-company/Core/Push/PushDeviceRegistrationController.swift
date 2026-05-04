import Combine
import Foundation

/// Хранит APNs-токен и отправляет `POST /v1/devices/register` после входа (idempotent upsert на сервере).
@MainActor
final class PushDeviceRegistrationController: ObservableObject {
    private var pendingTokenHex: String?
    private var lastRegisteredHex: String?

    func setDeviceToken(_ hex: String) {
        pendingTokenHex = hex
    }

    func resetForLogout() {
        lastRegisteredHex = nil
    }

    /// Запросить регистрацию, если уже есть токен и активная сессия.
    func syncRegistration(with authManager: AuthManager) async {
        guard authManager.isAuthenticated, let hex = pendingTokenHex, !hex.isEmpty else { return }
        guard hex != lastRegisteredHex else { return }
        do {
            _ = try await APIClient.shared.request(
                "/v1/devices/register",
                method: "POST",
                body: RegisterDeviceBody(platform: "ios", token: hex),
                tokenProvider: { authManager.accessToken },
                refreshAndRetry: { await authManager.refreshToken() }
            ) as DeviceRegisterData
            lastRegisteredHex = hex
        } catch {
            // Повторим при следующем `syncRegistration` или при смене токена.
        }
    }
}
