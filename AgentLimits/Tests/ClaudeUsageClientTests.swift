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

struct ClaudeUsageClientTests {
    @Test func expiredTokenReportsAwaitingRefreshWithoutCallingTheAPI() async {
        let client = ClaudeUsageClient(credentialsProvider: CredentialsProvider(sources: [ExpiredSource()]))
        await #expect(throws: UsageError.tokenAwaitingRefresh) {
            try await client.fetchUsage()
        }
    }

    @Test func missingCredentialsReportNotAuthenticated() async {
        let client = ClaudeUsageClient(credentialsProvider: CredentialsProvider(sources: [MissingSource()]))
        await #expect(throws: UsageError.notAuthenticated) {
            try await client.fetchUsage()
        }
    }
}
