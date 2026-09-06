import Foundation

enum UsageError: Error, Equatable {
    case notAuthenticated
    case tokenExpired
    case forbidden
    case rateLimited
    case decoding
    case network
    case generic(statusCode: Int)
}

actor ClaudeUsageClient {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let maxNetworkRetries = 3

    private let session: URLSession
    private let credentialsProvider: CredentialsProvider

    init(
        session: URLSession = .shared,
        credentialsProvider: CredentialsProvider = CredentialsProvider()
    ) {
        self.session = session
        self.credentialsProvider = credentialsProvider
    }

    func fetchUsage() async throws -> UsageResponse {
        let token: String
        do {
            token = try credentialsProvider.currentAccessToken()
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
