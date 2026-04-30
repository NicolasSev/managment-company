//
//  managment_companyTests.swift
//  managment-companyTests
//

import Foundation
import Testing
@testable import managment_company

struct ManagmentCompanyTests {

    @Test func apiURLBuilderJoinsRelativeDownloadPath() {
        let url = APIURLBuilder.absoluteDownloadURL(
            base: "http://127.0.0.1:8080",
            downloadPath: "/v1/files/abc/download?user=x&истекает=1&signature=y"
        )
        // Foundation percent-encodes non-ASCII in query (e.g. Cyrillic param names).
        #expect(url?.absoluteString == "http://127.0.0.1:8080/v1/files/abc/download?user=x&%D0%B8%D1%81%D1%82%D0%B5%D0%BA%D0%B0%D0%B5%D1%82=1&signature=y")
    }

    @Test func apiURLBuilderPassesThroughAbsoluteHttpURL() {
        let full = "https://cdn.example.com/file.pdf"
        let url = APIURLBuilder.absoluteDownloadURL(base: "http://127.0.0.1:8080", downloadPath: full)
        #expect(url?.absoluteString == full)
    }

    @Test func keychainRoundTripForTokens() {
        let keychain = KeychainManager.shared
        _ = keychain.clearTokens()
        #expect(keychain.storeTokens(access: "test-access", refresh: "test-refresh"))
        #expect(keychain.getAccessToken() == "test-access")
        #expect(keychain.getRefreshToken() == "test-refresh")
        _ = keychain.clearTokens()
        #expect(keychain.getAccessToken() == nil)
    }
}
