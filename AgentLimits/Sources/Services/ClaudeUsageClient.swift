import Foundation

enum UsageError: Error, Equatable {
    case notAuthenticated
    case tokenExpired
    /// The stored token is past its expiry and asking Claude Code to renew it did not work (yet).
    case tokenAwaitingRefresh
    /// The stored token is past its expiry and no `claude` CLI was found to renew it.
    case tokenRefreshUnavailable
    case forbidden
    case rateLimited
    case decoding
    case network
    case generic(statusCode: Int)
}

actor ClaudeUsageClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let maxNetworkRetries = 3
    // Keeps the polling loop from re-triggering a Keychain access prompt every 5 minutes;
    // a stale-but-still-valid cached token is fine because a 401 clears it immediately below.
    private static let tokenCacheTTL: TimeInterval = 1800

    private let session: URLSession
    private let credentialsProvider: CredentialsProvider
    private let tokenRefresher: ClaudeTokenRefreshing

    private var cachedToken: String?
    private var cachedTokenExpiresAt: Date?

    init(
        session: URLSession = .shared,
        credentialsProvider: CredentialsProvider = CredentialsProvider(),
        tokenRefresher: ClaudeTokenRefreshing = ClaudeTokenRefresher()
    ) {
        self.session = session
        self.credentialsProvider = credentialsProvider
        self.tokenRefresher = tokenRefresher
    }

    func fetchUsage() async throws -> UsageResponse {
        let token: String
        do {
            token = try currentAccessToken()
        } catch CredentialsError.expired {
            // Only an expired token is handed to Claude Code for renewal; a missing login
            // or a revoked token (401 below) still needs the user to sign in.
            token = try await renewedAccessToken()
        } catch {
            throw UsageError.notAuthenticated
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")

        var lastNetworkError: Error?

        for attempt in 0..<Self.maxNetworkRetries {
            do {
                return try await performRequest(request)
            } catch let error as UsageError {
                if case .tokenExpired = error {
                    cachedToken = nil
                    cachedTokenExpiresAt = nil
                }
                // Non-retryable: auth/rate-limit errors must surface immediately.
                throw error
            } catch {
                lastNetworkError = error
                if attempt < Self.maxNetworkRetries - 1 {
                    try? await Task.sleep(for: .seconds(1 << attempt))
                }
            }
        }

        _ = lastNetworkError
        throw UsageError.network
    }

    private func renewedAccessToken() async throws -> String {
        switch await tokenRefresher.refreshIfPossible() {
        case .renewed:
            guard let renewed = try? currentAccessToken() else { throw UsageError.tokenAwaitingRefresh }
            return renewed
        case .failed:
            throw UsageError.tokenAwaitingRefresh
        case .cliMissing:
            throw UsageError.tokenRefreshUnavailable
        }
    }

    private func currentAccessToken() throws -> String {
        let now = Date()
        if let cachedToken, let expiresAt = cachedTokenExpiresAt, now < expiresAt {
            return cachedToken
        }

        let token = try credentialsProvider.currentAccessToken(now: now)
        // Never cache past the token's own expiry, so the next poll re-reads the Keychain
        // and picks up the token Claude Code refreshed meanwhile.
        let ttlExpiry = now.addingTimeInterval(Self.tokenCacheTTL)
        cachedToken = token.value
        cachedTokenExpiresAt = token.expiresAt.map { min($0, ttlExpiry) } ?? ttlExpiry
        return token.value
    }

    private func performRequest(_ request: URLRequest) async throws -> UsageResponse {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw error
        }

        guard let http = response as? HTTPURLResponse else {
            throw UsageError.generic(statusCode: -1)
        }

        switch http.statusCode {
        case 200:
            do {
                return try JSONDecoder.claudeUsageDecoder.decode(UsageResponse.self, from: data)
            } catch {
                throw UsageError.decoding
            }
        case 401:
            throw UsageError.tokenExpired
        case 403:
            throw UsageError.forbidden
        case 429:
            throw UsageError.rateLimited
        default:
            throw UsageError.generic(statusCode: http.statusCode)
        }
    }
}
