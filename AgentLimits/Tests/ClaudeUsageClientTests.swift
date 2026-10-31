import Foundation
import Testing
@testable import AgentLimits

private struct ExpiredSource: CredentialsSource {
    func readAccessToken() throws -> ClaudeAccessToken {
        ClaudeAccessToken(value: "expired-token", expiresAt: Date(timeIntervalSinceNow: -60))
    }
}

private struct MissingSource: CredentialsSource {
    func readAccessToken() throws -> ClaudeAccessToken {
        throw CredentialsError.notAuthenticated
    }
}

/// Expired until the fake refresher "renews" it, like the Keychain item Claude Code rewrites.
private final class RenewableSource: CredentialsSource, @unchecked Sendable {
    private let lock = NSLock()
    private var renewed = false

    func renew() {
        lock.withLock { renewed = true }
    }

    func readAccessToken() throws -> ClaudeAccessToken {
        lock.withLock {
            renewed
                ? ClaudeAccessToken(value: "renewed-token", expiresAt: Date(timeIntervalSinceNow: 3600))
                : ClaudeAccessToken(value: "expired-token", expiresAt: Date(timeIntervalSinceNow: -60))
        }
    }
}

private actor RenewingRefresher: ClaudeTokenRefreshing {
    let source: RenewableSource

    init(source: RenewableSource) {
        self.source = source
    }

    func refreshIfPossible() async -> ClaudeTokenRefreshOutcome {
        source.renew()
        return .renewed
    }
}

/// Answers the usage endpoint with an empty limit list and records the bearer token it saw.
private final class UsageStubProtocol: URLProtocol {
    nonisolated(unsafe) static var lastAuthorization: String?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastAuthorization = request.value(forHTTPHeaderField: "Authorization")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"limits":[]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor FakeRefresher: ClaudeTokenRefreshing {
    private(set) var calls = 0
    let result: ClaudeTokenRefreshOutcome

    init(result: ClaudeTokenRefreshOutcome) {
        self.result = result
    }

    func refreshIfPossible() async -> ClaudeTokenRefreshOutcome {
        calls += 1
        return result
    }
}

struct ClaudeUsageClientTests {
    @Test func expiredTokenReportsAwaitingRefreshWhenRenewalFails() async {
        let refresher = FakeRefresher(result: .failed)
        let client = ClaudeUsageClient(
            credentialsProvider: CredentialsProvider(sources: [ExpiredSource()]),
            tokenRefresher: refresher
        )
        await #expect(throws: UsageError.tokenAwaitingRefresh) {
            try await client.fetchUsage()
        }
        #expect(await refresher.calls == 1)
    }

    @Test func expiredTokenRenewedByClaudeCodeIsUsedForTheRequest() async throws {
        let source = RenewableSource()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageStubProtocol.self]
        let client = ClaudeUsageClient(
            session: URLSession(configuration: configuration),
            credentialsProvider: CredentialsProvider(sources: [source]),
            tokenRefresher: RenewingRefresher(source: source)
        )
        let usage = try await client.fetchUsage()
        #expect(usage.limits.isEmpty)
        #expect(UsageStubProtocol.lastAuthorization == "Bearer renewed-token")
    }

    @Test func tokenStillExpiredAfterRenewalReportsAwaitingRefresh() async {
        let refresher = FakeRefresher(result: .renewed)
        let client = ClaudeUsageClient(
            credentialsProvider: CredentialsProvider(sources: [ExpiredSource()]),
            tokenRefresher: refresher
        )
        await #expect(throws: UsageError.tokenAwaitingRefresh) {
            try await client.fetchUsage()
        }
    }

    @Test func expiredTokenWithoutCLIReportsRefreshUnavailable() async {
        let client = ClaudeUsageClient(
            credentialsProvider: CredentialsProvider(sources: [ExpiredSource()]),
            tokenRefresher: FakeRefresher(result: .cliMissing)
        )
        await #expect(throws: UsageError.tokenRefreshUnavailable) {
            try await client.fetchUsage()
        }
    }

    @Test func missingCredentialsReportNotAuthenticatedWithoutRenewal() async {
        let refresher = FakeRefresher(result: .renewed)
        let client = ClaudeUsageClient(
            credentialsProvider: CredentialsProvider(sources: [MissingSource()]),
            tokenRefresher: refresher
        )
        await #expect(throws: UsageError.notAuthenticated) {
            try await client.fetchUsage()
        }
        #expect(await refresher.calls == 0)
    }
}
