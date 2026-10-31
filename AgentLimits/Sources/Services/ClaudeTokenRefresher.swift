import Foundation

enum ClaudeTokenRefreshOutcome: Equatable, Sendable {
    /// A non-expired token is readable again.
    case renewed
    /// Claude Code was asked but the token is still expired (or a recent attempt failed).
    case failed
    /// No `claude` CLI was found, so there is nothing that can renew the token.
    case cliMissing
}

protocol ClaudeTokenRefreshing: Sendable {
    /// Asks Claude Code to renew its expired token.
    func refreshIfPossible() async -> ClaudeTokenRefreshOutcome
}

/// Lets Claude Code renew its own OAuth token when the stored one has expired.
///
/// This app must never redeem the refresh token itself: Anthropic's refresh tokens are single-use,
/// so a redeemed token would leave Claude Code with a dead one and force a real re-login. Instead the
/// `claude` CLI is started and asked for `/status`; Claude Code refreshes the expired token under its
/// own lock and rewrites the Keychain item, which the next credentials read picks up. Someone who works
/// only in the Claude desktop app never runs the CLI, so without this the token would stay expired.
actor ClaudeTokenRefresher: ClaudeTokenRefreshing {
    /// Wait after the first failed attempt; doubles on each further failure up to `maximumBackoff`.
    static let initialBackoff: TimeInterval = 240
    static let maximumBackoff: TimeInterval = 2 * 3600

    private let locateCLI: @Sendable () -> String?
    private let runProbe: @Sendable (_ executable: String, _ isRefreshed: @escaping @Sendable () -> Bool) async -> Void
    private let isRefreshed: @Sendable () -> Bool
    private let now: @Sendable () -> Date

    private var nextAttemptAllowed: Date?
    private var lastFailure: ClaudeTokenRefreshOutcome = .failed
    private var consecutiveFailures = 0
    private var inFlight: Task<ClaudeTokenRefreshOutcome, Never>?

    init(
        locateCLI: @escaping @Sendable () -> String? = {
            CLIExecutableLocator.resolve("claude", extraPaths: CLIExecutableLocator.claudeExtraPaths)
        },
        runProbe: @escaping @Sendable (String, @escaping @Sendable () -> Bool) async -> Void = {
            await ClaudeStatusProbe.run(executable: $0, isRefreshed: $1)
        },
        isRefreshed: @escaping @Sendable () -> Bool = {
            (try? CredentialsProvider().currentAccessToken()) != nil
        },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.locateCLI = locateCLI
        self.runProbe = runProbe
        self.isRefreshed = isRefreshed
        self.now = now
    }

    func refreshIfPossible() async -> ClaudeTokenRefreshOutcome {
        if let inFlight {
            return await inFlight.value
        }
        if let nextAttemptAllowed, now() < nextAttemptAllowed {
            return lastFailure
        }

        // Locating the CLI may start a login shell and reading the Keychain starts `security`: both
        // block, so neither runs on this actor's executor.
        let locateCLI = locateCLI
        let runProbe = runProbe
        let isRefreshed = isRefreshed
        let task = Task.detached { () -> ClaudeTokenRefreshOutcome in
            guard let executable = locateCLI() else { return .cliMissing }
            await runProbe(executable, isRefreshed)
            return isRefreshed() ? .renewed : .failed
        }
        inFlight = task
        let outcome = await task.value
        inFlight = nil

        if outcome == .renewed {
            consecutiveFailures = 0
            nextAttemptAllowed = nil
        } else {
            consecutiveFailures += 1
            lastFailure = outcome
            let backoff = Self.initialBackoff * pow(2, Double(min(consecutiveFailures - 1, 10)))
            nextAttemptAllowed = now().addingTimeInterval(min(backoff, Self.maximumBackoff))
        }
        return outcome
    }
}

/// Runs `claude` interactively on a pseudo-terminal in its own session, types `/status` once its
/// prompt is on screen, and stops once the Keychain holds a valid token again or the deadline passes.
/// The output is only scanned for the prompt and the workspace trust dialog; nothing is kept.
///
/// Claude Code draws with Ink, which repaints only the cells that change and positions them with cursor
/// moves, so the screen is never read line by line. What matters is the text right after the last `❯`,
/// the marker Claude Code puts on the focused option or on the input prompt.
enum ClaudeStatusProbe {
    static let timeout: TimeInterval = 60
    /// How long Claude Code gets to quit by itself after `/exit`, before any signal.
    static let exitWait: TimeInterval = 20
    /// How long it gets to quit after SIGTERM, before SIGKILL.
    static let termGrace: TimeInterval = 8
    static let directoryName = "ClaudeStatusProbe"

    /// Keeps the probe inert: every tool disabled, no MCP servers, no hooks, no project settings, no
    /// remote control. Even a mistyped line reaching the model could not run anything.
    static let arguments = [
        "--tools", "",
        "--strict-mcp-config",
        "--setting-sources", "user",
        "--settings", #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#
    ]

    static func run(executable: String, isRefreshed: @escaping @Sendable () -> Bool) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                if let directory = probeDirectory() {
                    runBlocking(executable: executable, workingDirectory: directory, isRefreshed: isRefreshed)
                }
                continuation.resume()
            }
        }
    }

    static func runBlocking(
        executable: String,
        workingDirectory: URL,
        isRefreshed: () -> Bool,
        timeout: TimeInterval = timeout,
        exitWait: TimeInterval = exitWait,
        termGrace: TimeInterval = termGrace,
        baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        guard let terminal = Terminal.start(
            executable: executable,
            workingDirectory: workingDirectory,
            environment: environment(executable: executable, workingDirectory: workingDirectory, base: baseEnvironment)
        ) else { return }
        defer { terminal.close() }

        let deadline = Date().addingTimeInterval(timeout)
        var stage = Stage.waitingForPrompt
        var trustKeysLeft = 3
        var nextRefreshCheck = Date().addingTimeInterval(1)

        while Date() < deadline, !terminal.child.hasExited() {
            terminal.pump(for: 0.05)
            if Date() >= nextRefreshCheck {
                if isRefreshed() { break }
                nextRefreshCheck = Date().addingTimeInterval(2)
            }
            guard terminal.idle(for: 0.8) else { continue }

            switch nextKeys(onScreen: terminal.screen, probeDirectory: workingDirectory.path, stage: stage) {
            case .trust(let key) where trustKeysLeft > 0:
                terminal.send(key)
                trustKeysLeft -= 1
            case .typeStatus:
                terminal.send("/status")
                stage = .statusTyped
            case .submitStatus:
                terminal.send("\r")
                stage = .statusSubmitted
            default:
                break
            }
        }

        requestExit(terminal, wait: exitWait)
        terminal.child.terminate(grace: termGrace, draining: terminal)
    }

    /// Closes whatever `/status` opened with a single Esc (two in a row would rewind the conversation),
    /// then types `/exit` and presses Enter only once the prompt shows it highlighted. Without that
    /// confirmation nothing is submitted, and the signals in `Child.terminate` take over.
    private static func requestExit(_ terminal: Terminal, wait: TimeInterval) {
        guard !terminal.child.hasExited() else { return }
        terminal.send("\u{1b}")
        terminal.pump(until: { terminal.idle(for: 0.8) }, upTo: 3)
        terminal.send("/exit")
        terminal.pump(until: { highlights("/exit", description: "Exit the CLI", onScreen: terminal.screen) }, upTo: 3)
        if highlights("/exit", description: "Exit the CLI", onScreen: terminal.screen) {
            terminal.send("\r")
        }
        terminal.pump(until: { terminal.child.hasExited() }, upTo: wait)
    }

    enum Stage: Equatable {
        case waitingForPrompt
        case statusTyped
        case statusSubmitted
    }

    enum Action: Equatable {
        case wait
        case trust(String)
        case typeStatus
        case submitStatus
    }

    /// Decides what to type for the current screen. Nothing is ever confirmed blindly:
    /// - Enter goes to the trust dialog only when it names the probe folder and `❯` is on "Yes";
    /// - `/status` is typed (without Enter) only at the empty input prompt;
    /// - Enter submits it only once the prompt shows `/status` highlighted with its own description.
    /// Any other dialog, such as a startup question, leaves `❯` on its own option and gets nothing.
    static func nextKeys(onScreen screen: String, probeDirectory: String, stage: Stage) -> Action {
        let text = normalized(screen)
        guard let focus = focusedText(normalizedScreen: text) else { return .wait }

        let onYes = focus.hasPrefix("yes,itrustthisfolder")
        let onNo = focus.hasPrefix("no,exit") || focus.hasPrefix("no,continue")
        if onYes || onNo {
            guard text.contains("quicksafetycheck"), namesFolder(probeDirectory, in: text) else { return .wait }
            // "No" is listed first and focused by default; "Yes" is right below it.
            return .trust(onYes ? "\r" : "\u{1b}[B")
        }

        switch stage {
        case .waitingForPrompt:
            let atPrompt = focus.isEmpty || focus.hasPrefix("try\"") || focus.hasPrefix("─")
            let hasFooter = text.contains("forshortcuts") || text.contains("shift+tabtocycle")
            return atPrompt && hasFooter ? .typeStatus : .wait
        case .statusTyped:
            let ready = highlights(
                "/status",
                description: "Show Claude Code status including version",
                onScreen: screen
            )
            return ready ? .submitStatus : .wait
        case .statusSubmitted:
            return .wait
        }
    }

    /// True when the input prompt shows `command` as the selected suggestion, with its description.
    static func highlights(_ command: String, description: String, onScreen screen: String) -> Bool {
        focusedText(normalizedScreen: normalized(screen))?.hasPrefix(normalized(command + description)) == true
    }

    private static func focusedText(normalizedScreen text: String) -> String? {
        guard let marker = text.range(of: "❯", options: .backwards) else { return nil }
        return String(text[marker.upperBound...].prefix(160))
    }

    private static func namesFolder(_ path: String, in text: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var forms = [normalized(path)]
        if path.hasPrefix(home) {
            forms.append(normalized("~" + path.dropFirst(home.count)))
        }
        return forms.contains { !$0.isEmpty && text.contains($0) }
    }

    /// Lowercased, with escape sequences, control characters and whitespace removed: spaces in Ink's
    /// output are often cursor moves, so words can only be compared run together.
    static func normalized(_ screen: String) -> String {
        String(String.UnicodeScalarView(stripANSI(screen).lowercased().unicodeScalars.filter {
            $0.value >= 0x20 && $0.value != 0x7f && !$0.properties.isWhitespace
        }))
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            // CSI sequences (cursor moves, colours, mode queries), OSC strings, charset selection, and
            // the two-byte ESC commands Ink emits.
            of: [
                "\u{1b}\\[[0-9;?<>=]*[ -/]*[@-~]",
                "\u{1b}\\][^\u{07}\u{1b}]*(\u{07}|\u{1b}\\\\)",
                "\u{1b}[()][0-9A-Za-z]",
                "\u{1b}[=>78DEHMNO]"
            ].joined(separator: "|"),
            with: "",
            options: .regularExpression
        )
    }

    /// Only what a CLI needs to run and reach the network. API keys and tokens from the app's own
    /// environment never reach the child, and the probe must never self-update the CLI.
    static func environment(executable: String, workingDirectory: URL, base: [String: String]) -> [String: String] {
        let allowed: Set<String> = [
            "HOME", "USER", "LOGNAME", "SHELL", "TMPDIR", "LANG",
            "http_proxy", "https_proxy", "no_proxy", "all_proxy",
            "HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "ALL_PROXY",
            "SSL_CERT_FILE", "NODE_EXTRA_CA_CERTS"
        ]
        var env = base.filter { key, _ in allowed.contains(key) || key.hasPrefix("LC_") }
        let binDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        env["PATH"] = [binDirectory, base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
        env["TERM"] = "xterm-256color"
        env["PWD"] = workingDirectory.path
        env["DISABLE_AUTOUPDATER"] = "1"
        return env
    }

    /// A dedicated, owner-only, empty folder: the only one the probe ever trusts.
    private static func probeDirectory() -> URL? {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let directory = support.appendingPathComponent("AgentLimits/\(directoryName)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            return nil
        }
        return directory
    }
}
