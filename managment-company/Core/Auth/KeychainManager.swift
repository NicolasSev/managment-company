import Foundation
import Security

/// Manages secure storage of tokens using Keychain (SecItemAdd, SecItemCopyMatching, SecItemDelete).
final class KeychainManager {
    static let shared = KeychainManager()
    
    private let serviceName = "com.propmanager.tokens"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"
    
    private init() {}
    
    func storeAccessToken(_ token: String) -> Bool {
        store(key: accessTokenKey, value: token)
    }
    
    func storeRefreshToken(_ token: String) -> Bool {
        store(key: refreshTokenKey, value: token)
    }
    
    func storeTokens(access: String, refresh: String) -> Bool {
        storeAccessToken(access) && storeRefreshToken(refresh)
    }
    
    func getAccessToken() -> String? {
        retrieve(key: accessTokenKey)
    }
    
    func getRefreshToken() -> String? {
        retrieve(key: refreshTokenKey)
    }
    
    func clearTokens() -> Bool {
        delete(key: accessTokenKey) && delete(key: refreshTokenKey)
    }
    
    private func store(key: String, value: String) -> Bool {
        _ = delete(key: key)
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private func retrieve(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
    
    private func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
