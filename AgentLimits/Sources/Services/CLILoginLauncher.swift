import AppKit
import Foundation

enum CLILoginError: Error, Equatable {
    case unsupportedProvider
    case launchFailed
}

/// Starts the official CLI login flow (`claude auth login`, `codex login`) in a Terminal
/// window. Both commands open the browser for OAuth and write the new credentials where
/// the usage clients already read them (Keychain for Claude Code, `~/.codex` for Codex),
/// so the app never handles passwords or tokens itself. A visible Terminal is used rather
/// than a hidden `Process` because either flow may fall back to asking the user to paste
/// a code when the browser callback cannot reach the CLI.
///
/// The flow is launched through a throwaway `.command` file opened with LaunchServices,
/// which needs no Automation (Apple Events) permission, unlike scripting Terminal.
enum CLILoginLauncher {
    struct LoginCommand: Equatable {
        let executableName: String
        let arguments: [String]
        let title: String
    }

    static func loginCommand(for provider: UsageProvider) -> LoginCommand? {
        switch provider {
        case .claudeCode:
            return LoginCommand(executableName: "claude", arguments: ["auth", "login"], title: "Login Claude Code")
        case .codex:
            return LoginCommand(executableName: "codex", arguments: ["login"], title: "Login Codex")
        case .antigravity:
            return nil
        }
    }

    @MainActor
    static func launch(for provider: UsageProvider) throws {
        guard let command = loginCommand(for: provider) else {
            throw CLILoginError.unsupportedProvider
        }
        let executable = CLIExecutableLocator.resolve(
            command.executableName,
            extraPaths: provider == .claudeCode ? CLIExecutableLocator.claudeExtraPaths : []
        )
        let script = makeScript(for: command, resolvedExecutable: executable)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentLimits-\(command.executableName)-login.command")
        do {
            try Data(script.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            throw CLILoginError.launchFailed
        }

        guard NSWorkspace.shared.open(url) else {
            throw CLILoginError.launchFailed
        }
    }

    /// The command runs inside the user's interactive login shell so it sees the same PATH,
    /// proxy variables and `CLAUDE_CONFIG_DIR`/`CODEX_HOME` overrides as a normal terminal.
    static func makeScript(for command: LoginCommand, resolvedExecutable: String?) -> String {
        let invocation = ([resolvedExecutable ?? command.executableName] + command.arguments)
            .map(shellQuoted)
            .joined(separator: " ")
        return """
        #!/bin/sh
        clear
        echo \(shellQuoted("AgentLimits — \(command.title)"))
        echo
        "${SHELL:-/bin/zsh}" -ilc \(shellQuoted(invocation))
        status=$?
        echo
        if [ "$status" -eq 0 ]; then
          echo "Login completato. AgentLimits si aggiornerà da solo: puoi chiudere questa finestra."
        else
          echo "Login non riuscito (codice $status)."
        fi
        rm -f "$0"

        """
    }

    static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
