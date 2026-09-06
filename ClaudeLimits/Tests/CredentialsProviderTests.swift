import XCTest
@testable import ClaudeLimits

private struct FailingSource: CredentialsSource {
    func readAccessToken() throws -> String {
        throw CredentialsError.notAuthenticated
    }
}

private struct SucceedingSource: CredentialsSource {
    let token: String
    func readAccessToken() throws -> String {
        token
    }
}

final class CredentialsProviderTests: XCTestCase {
    func testReturnsFirstSuccessfulSource() throws {
        let provider = CredentialsProvider(sources: [FailingSource(), SucceedingSource(token: "abc123")])
        let token = try provider.currentAccessToken()
        XCTAssertEqual(token, "abc123")
    }

    func testPrefersFirstSourceOverFallback() throws {
        let provider = CredentialsProvider(sources: [SucceedingSource(token: "keychain-token"), SucceedingSource(token: "file-token")])
        let token = try provider.currentAccessToken()
        XCTAssertEqual(token, "keychain-token")
    }

    func testThrowsWhenAllSourcesFail() {
        let provider = CredentialsProvider(sources: [FailingSource(), FailingSource()])
        XCTAssertThrowsError(try provider.currentAccessToken()) { error in
            XCTAssertEqual(error as? CredentialsError, .notAuthenticated)
        }
    }
}

extension CredentialsError: Equatable {
    public static func == (lhs: CredentialsError, rhs: CredentialsError) -> Bool {
        switch (lhs, rhs) {
        case (.notAuthenticated, .notAuthenticated):
            return true
        }
    }
}
