import Foundation

enum CredentialsError: Error {
    case notAuthenticated
    /// Credentials exist but every token is past its expiry. Claude Code refreshes it the next
    /// time it runs; this app never refreshes it, since that would rotate Claude Code's refresh token.
    case expired
}

protocol CredentialsSource {
    func readAccessToken() throws -> ClaudeAccessToken
}

struct CredentialsProvider {
    let sources: [CredentialsSource]

    init(sources: [CredentialsSource] = [KeychainCredentialsReader(), FileCredentialsReader()]) {
        self.sources = sources
    }

    func currentAccessToken(now: Date = .now) throws -> ClaudeAccessToken {
        var foundExpired = false
        for source in sources {
            guard let token = try? source.readAccessToken() else { continue }
            if token.isExpired(at: now) {
                foundExpired = true
                continue
            }
            return token
        }
        throw foundExpired ? CredentialsError.expired : CredentialsError.notAuthenticated
    }
}
