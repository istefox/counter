import Foundation

/// A GUI app launched via LaunchServices (Dock/Finder double-click, `open`) inherits a
/// minimal PATH that does not include a shell's `.zshrc`/`.zprofile` additions — where
/// CLIs like `codex` and `claude` commonly live (e.g. `~/.local/bin`, mise/asdf shims, nvm).
/// `ProcessInfo`'s PATH alone is therefore not enough; common user-local install locations
/// are checked first, and as a last resort a login shell is asked to resolve the name the
/// way a terminal would (`command -v`), covering PATH customizations this app cannot
/// otherwise predict.
enum CLIExecutableLocator {
    /// Where Claude Code's own local installer puts the binary, besides the common paths.
    static var claudeExtraPaths: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.claude/local/claude"]
    }

    static func resolve(_ name: String, extraPaths: [String] = []) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = extraPaths + [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.local/share/mise/shims/\(name)",
        ]
        for path in commonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/\(name)"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return resolveViaLoginShell(name)
    }

    private static func resolveViaLoginShell(_ name: String) -> String? {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "command -v \(name)"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty,
            FileManager.default.isExecutableFile(atPath: path)
        else { return nil }
        return path
    }
}
