import Foundation
import Security

enum KeychainError: Error {
    case unavailable(status: OSStatus)
}

struct KeychainCredentialsReader: CredentialsSource {
    static let serviceName = "Claude Code-credentials"

    func readAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.serviceName,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.unavailable(status: status)
        }

        let decoded = try JSONDecoder().decode(ClaudeCredentialsFile.self, from: data)
        return decoded.claudeAiOauth.accessToken
    }
}
