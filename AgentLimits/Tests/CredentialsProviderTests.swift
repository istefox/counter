import XCTest
@testable import AgentLimits

private struct FailingSource: CredentialsSource {
    func readAccessToken() throws -> ClaudeAccessToken {
        throw CredentialsError.notAuthenticated
    }
}

private struct SucceedingSource: CredentialsSource {
    let token: String
    var expiresAt: Date?
    func readAccessToken() throws -> ClaudeAccessToken {
        ClaudeAccessToken(value: token, expiresAt: expiresAt)
    }
}

final class CredentialsProviderTests: XCTestCase {
    func testReturnsFirstSuccessfulSource() throws {
        let provider = CredentialsProvider(sources: [FailingSource(), SucceedingSource(token: "abc123")])
        let token = try provider.currentAccessToken()
        XCTAssertEqual(token.value, "abc123")
    }

    func testPrefersFirstSourceOverFallback() throws {
        let provider = CredentialsProvider(sources: [SucceedingSource(token: "keychain-token"), SucceedingSource(token: "file-token")])
        let token = try provider.currentAccessToken()
        XCTAssertEqual(token.value, "keychain-token")
    }

    func testSkipsExpiredTokenInFavorOfValidFallback() throws {
        let now = Date()
        let provider = CredentialsProvider(sources: [
            SucceedingSource(token: "expired-token", expiresAt: now.addingTimeInterval(-60)),
            SucceedingSource(token: "valid-token", expiresAt: now.addingTimeInterval(3600))
        ])
        XCTAssertEqual(try provider.currentAccessToken(now: now).value, "valid-token")
    }

    func testThrowsExpiredWhenOnlyExpiredTokensExist() {
        let now = Date()
        let provider = CredentialsProvider(sources: [
            FailingSource(),
            SucceedingSource(token: "expired-token", expiresAt: now)
        ])
        XCTAssertThrowsError(try provider.currentAccessToken(now: now)) { error in
            XCTAssertEqual(error as? CredentialsError, .expired)
        }
    }

    func testAcceptsTokenWithoutExpiry() throws {
        let provider = CredentialsProvider(sources: [SucceedingSource(token: "no-expiry")])
        XCTAssertEqual(try provider.currentAccessToken().value, "no-expiry")
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
        case (.notAuthenticated, .notAuthenticated), (.expired, .expired):
            return true
        default:
            return false
        }
    }
}
