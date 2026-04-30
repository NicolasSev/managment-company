import SwiftUI

@main
struct managment_companyApp: App {
    @StateObject private var authManager = AuthManager()
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    MainTabView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(authManager)
            .alert(
                "Сессия",
                isPresented: Binding(
                    get: { authManager.sessionExpiredMessage != nil },
                    set: { if !$0 { authManager.acknowledgeSessionExpired() } }
                )
            ) {
                Button("OK", role: .cancel) {
                    authManager.acknowledgeSessionExpired()
                }
            } message: {
                Text(authManager.sessionExpiredMessage ?? "")
            }
        }
    }
}
