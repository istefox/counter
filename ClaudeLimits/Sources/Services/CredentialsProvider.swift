import Foundation

enum CredentialsError: Error {
    case notAuthenticated
}

protocol CredentialsSource {
    func readAccessToken() throws -> String
}

struct CredentialsProvider {
    let sources: [CredentialsSource]

    init(sources: [CredentialsSource] = [KeychainCredentialsReader(), FileCredentialsReader()]) {
        self.sources = sources
    }

    func currentAccessToken() throws -> String {
        for source in sources {
            if let token = try? source.readAccessToken() {
                return token
            }
        }
        throw CredentialsError.notAuthenticated
    }
}
