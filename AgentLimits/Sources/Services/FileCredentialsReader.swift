import Foundation

enum FileCredentialsError: Error {
    case fileNotFound
    case noAccessToken
}

struct FileCredentialsReader: CredentialsSource {
    func readAccessToken() throws -> String {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")

        let credentialsURL = configDir.appendingPathComponent(".credentials.json")

        guard FileManager.default.fileExists(atPath: credentialsURL.path) else {
            throw FileCredentialsError.fileNotFound
        }

        let data = try Data(contentsOf: credentialsURL)
        let decoded = try JSONDecoder().decode(ClaudeCredentialsFile.self, from: data)
        return decoded.claudeAiOauth.accessToken
    }
}
