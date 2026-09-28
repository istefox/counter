import Foundation

enum KeychainError: Error {
    case unavailable(status: Int32)
}

/// Reads the Claude Code OAuth credentials through `/usr/bin/security` rather than `SecItemCopyMatching`.
///
/// Claude Code rewrites this item with `security add-generic-password -U` on every token refresh, which
/// resets the item's partition list to `apple-tool:` and drops any app previously granted "Always Allow".
/// Reading in-process therefore re-triggers the Keychain password prompt after each refresh. Going through
/// the same `security` tool that owns the item keeps the read inside the `apple-tool:` partition, so it
/// never prompts.
struct KeychainCredentialsReader: CredentialsSource {
    static let serviceName = "Claude Code-credentials"
    private static let securityToolURL = URL(fileURLWithPath: "/usr/bin/security")

    func readAccessToken() throws -> String {
        let process = Process()
        process.executableURL = Self.securityToolURL
        process.arguments = ["find-generic-password", "-s", Self.serviceName, "-a", NSUserName(), "-w"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice

        try process.run()
        // Drain the pipe before waiting so a large payload cannot block the child on a full buffer.
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw KeychainError.unavailable(status: process.terminationStatus)
        }

        let trimmed = String(decoding: output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let decoded = try JSONDecoder().decode(ClaudeCredentialsFile.self, from: Data(trimmed.utf8))
        return decoded.claudeAiOauth.accessToken
    }
}
