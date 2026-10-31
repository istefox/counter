import Darwin
import Foundation
import Testing
@testable import AgentLimits

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }

    func increment() {
        lock.withLock { value += 1 }
    }
}

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_000_000)

    var now: Date { lock.withLock { current } }

    func advance(_ seconds: TimeInterval) {
        lock.withLock { current += seconds }
    }
}

/// A temporary folder named like the real probe folder, holding a stand-in `claude` script.
private struct ProbeSandbox {
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentLimitsTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(ClaudeStatusProbe.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func file(_ name: String) -> URL { directory.appendingPathComponent(name) }

    /// The script records its own PID; it reads its terminal raw and unechoed, like Claude Code does.
    func script(_ body: String) throws -> String {
        let script = file("claude")
        try """
        #!/bin/sh
        echo $$ > '\(file("pid").path)'
        stty -echo -icanon min 1
        \(body)
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script.path
    }

    /// Shows a REPL prompt, accepts `/status` only once it is typed, shows it highlighted, waits for Enter.
    var replUntilStatusSubmitted: String {
        """
        printf '────\\n❯ Try "x"\\n? for shortcuts\\n'
        cmd=$(dd bs=1 count=7 2>/dev/null)
        printf '%s\\n' "$cmd" > '\(file("received").path)'
        printf '❯ /status   Show Claude Code status including version, model\\n'
        dd bs=1 count=1 >/dev/null 2>&1
        echo submitted >> '\(file("received").path)'
        """
    }

    func isGone(pidFile name: String) throws -> Bool {
        let text = try String(contentsOf: file(name), encoding: .utf8)
        guard let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return kill(pid, 0) == -1 && errno == ESRCH
    }

    func received() throws -> [String] {
        try String(contentsOf: file("received"), encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func receivedBytes() -> String {
        (try? String(contentsOf: file("received"), encoding: .utf8)) ?? ""
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }
}

struct ClaudeTokenRefresherTests {
    @Test func missingCLIIsReportedAndBacksOff() async {
        let runs = Counter()
        let lookups = Counter()
        let clock = FakeClock()
        let refresher = ClaudeTokenRefresher(
            locateCLI: {
                lookups.increment()
                return nil
            },
            runProbe: { _, _ in runs.increment() },
            isRefreshed: { true },
            now: { clock.now }
        )
        #expect(await refresher.refreshIfPossible() == .cliMissing)
        // The next polls neither search again nor change their answer until the backoff ends.
        #expect(await refresher.refreshIfPossible() == .cliMissing)
        #expect(lookups.count == 1)
        clock.advance(ClaudeTokenRefresher.initialBackoff + 1)
        _ = await refresher.refreshIfPossible()
        #expect(lookups.count == 2)
        #expect(runs.count == 0)
    }

    @Test func reportsWhetherTheTokenWasRenewed() async {
        let renewed = ClaudeTokenRefresher(locateCLI: { "/bin/claude" }, runProbe: { _, _ in }, isRefreshed: { true })
        let stale = ClaudeTokenRefresher(locateCLI: { "/bin/claude" }, runProbe: { _, _ in }, isRefreshed: { false })
        #expect(await renewed.refreshIfPossible() == .renewed)
        #expect(await stale.refreshIfPossible() == .failed)
    }

    @Test func failuresBackOffExponentially() async {
        let runs = Counter()
        let clock = FakeClock()
        let refresher = ClaudeTokenRefresher(
            locateCLI: { "/bin/claude" },
            runProbe: { _, _ in runs.increment() },
            isRefreshed: { false },
            now: { clock.now }
        )
        let first = ClaudeTokenRefresher.initialBackoff

        _ = await refresher.refreshIfPossible()
        clock.advance(first - 1)
        #expect(await refresher.refreshIfPossible() == .failed)
        #expect(runs.count == 1)

        clock.advance(2)
        _ = await refresher.refreshIfPossible()
        #expect(runs.count == 2)

        // The second failure doubles the wait.
        clock.advance(first + 1)
        _ = await refresher.refreshIfPossible()
        #expect(runs.count == 2)
        clock.advance(first)
        _ = await refresher.refreshIfPossible()
        #expect(runs.count == 3)
    }

    @Test func backoffIsCappedAndResetBySuccess() async {
        let runs = Counter()
        let clock = FakeClock()
        let renewed = Counter()
        let refresher = ClaudeTokenRefresher(
            locateCLI: { "/bin/claude" },
            runProbe: { _, _ in runs.increment() },
            isRefreshed: { renewed.count > 0 },
            now: { clock.now }
        )
        for _ in 0..<12 {
            _ = await refresher.refreshIfPossible()
            clock.advance(ClaudeTokenRefresher.maximumBackoff + 1)
        }
        #expect(runs.count == 12)

        renewed.increment()
        #expect(await refresher.refreshIfPossible() == .renewed)
        // After a success the next expiry is handled straight away.
        #expect(await refresher.refreshIfPossible() == .renewed)
        #expect(runs.count == 14)
    }

    @Test func concurrentCallersShareOneProbe() async {
        let runs = Counter()
        let refresher = ClaudeTokenRefresher(
            locateCLI: { "/bin/claude" },
            runProbe: { _, _ in
                runs.increment()
                try? await Task.sleep(for: .milliseconds(300))
            },
            isRefreshed: { true }
        )
        async let first = refresher.refreshIfPossible()
        async let second = refresher.refreshIfPossible()
        let results = await [first, second]
        #expect(results == [.renewed, .renewed])
        #expect(runs.count == 1)
    }
}

struct ClaudeStatusProbeProcessTests {
    @Test func submitsStatusAndStopsTheWholeGroupOnTimeout() throws {
        let sandbox = try ProbeSandbox()
        defer { sandbox.remove() }
        let executable = try sandbox.script("""
        \(sandbox.replUntilStatusSubmitted)
        sleep 60 &
        echo $! > '\(sandbox.file("sleep.pid").path)'
        wait
        """)

        let start = Date()
        ClaudeStatusProbe.runBlocking(
            executable: executable, workingDirectory: sandbox.directory, isRefreshed: { false },
            timeout: 4, exitWait: 1, termGrace: 3
        )
        #expect(Date().timeIntervalSince(start) < 15)
        #expect(try sandbox.received() == ["/status", "submitted"])
        #expect(try sandbox.isGone(pidFile: "pid"))
        #expect(try sandbox.isGone(pidFile: "sleep.pid"))
    }

    @Test func asksTheCLIToExitOnceTheTokenIsRenewed() throws {
        let sandbox = try ProbeSandbox()
        defer { sandbox.remove() }
        let executable = try sandbox.script("""
        \(sandbox.replUntilStatusSubmitted)
        dd bs=1 count=1 >/dev/null 2>&1
        printf '❯ Try "x"\\n'
        cmd=$(dd bs=1 count=5 2>/dev/null)
        printf '❯ /exit   Exit the CLI\\n'
        dd bs=1 count=1 >/dev/null 2>&1
        printf '%s\\n' "$cmd" >> '\(sandbox.file("received").path)'
        exit 0
        """)

        let start = Date()
        ClaudeStatusProbe.runBlocking(
            executable: executable, workingDirectory: sandbox.directory,
            isRefreshed: { sandbox.receivedBytes().contains("submitted") },
            timeout: 30, exitWait: 10, termGrace: 3
        )
        #expect(Date().timeIntervalSince(start) < 10)
        #expect(try sandbox.received() == ["/status", "submitted", "/exit"])
        #expect(try sandbox.isGone(pidFile: "pid"))
    }

    @Test func givesTheCLITimeToQuitAfterSIGTERM() throws {
        let sandbox = try ProbeSandbox()
        defer { sandbox.remove() }
        let executable = try sandbox.script("""
        trap 'sleep 1; echo clean > "\(sandbox.file("clean").path)"; exit 0' TERM
        echo 'busy'
        while :; do sleep 0.2; done
        """)

        ClaudeStatusProbe.runBlocking(
            executable: executable, workingDirectory: sandbox.directory, isRefreshed: { false },
            timeout: 1, exitWait: 0.2, termGrace: 6
        )
        #expect(FileManager.default.fileExists(atPath: sandbox.file("clean").path))
        #expect(try sandbox.isGone(pidFile: "pid"))
    }

    @Test func neverTypesAnythingIntoAnUnknownScreen() throws {
        let sandbox = try ProbeSandbox()
        defer { sandbox.remove() }
        let executable = try sandbox.script("""
        echo 'Some unexpected screen'
        while :; do dd bs=1 count=1 >> '\(sandbox.file("received").path)' 2>/dev/null; done
        """)

        ClaudeStatusProbe.runBlocking(
            executable: executable, workingDirectory: sandbox.directory, isRefreshed: { false },
            timeout: 2, exitWait: 0.5, termGrace: 2
        )
        let received = sandbox.receivedBytes()
        #expect(!received.contains("/status"))
        #expect(!received.contains("\n") && !received.contains("\r"))
        #expect(try sandbox.isGone(pidFile: "pid"))
    }

    @Test func neverConfirmsAStartupDialogShownOverThePrompt() throws {
        let sandbox = try ProbeSandbox()
        defer { sandbox.remove() }
        let screen = sandbox.file("screen")
        try ClaudeScreenFixtures.replThenStartupDialog.write(to: screen, atomically: true, encoding: .utf8)
        let executable = try sandbox.script("""
        cat '\(screen.path)'
        while :; do dd bs=1 count=1 >> '\(sandbox.file("received").path)' 2>/dev/null; done
        """)

        ClaudeStatusProbe.runBlocking(
            executable: executable, workingDirectory: sandbox.directory, isRefreshed: { false },
            timeout: 3, exitWait: 0.5, termGrace: 2
        )
        let received = sandbox.receivedBytes()
        #expect(!received.contains("/status"))
        #expect(!received.contains("\n") && !received.contains("\r"))
    }
}

/// Screens captured from the real Claude Code 2.1.310 (see `ClaudeScreenFixtures`).
struct ClaudeStatusProbeScreenTests {
    private typealias Screens = ClaudeScreenFixtures
    private let down = "\u{1b}[B"

    private func keys(
        _ screen: String,
        stage: ClaudeStatusProbe.Stage = .waitingForPrompt,
        folder: String = ClaudeScreenFixtures.probeDirectory
    ) -> ClaudeStatusProbe.Action {
        ClaudeStatusProbe.nextKeys(onScreen: screen, probeDirectory: folder, stage: stage)
    }

    @Test func trustDialogMovesFromNoToYesThenConfirms() {
        #expect(keys(Screens.trustDialog) == .trust(down))
        let onYes = Screens.trustDialog + Screens.trustAfterDown
        #expect(keys(onYes) == .trust("\r"))
        #expect(keys(onYes + Screens.trustAfterUp) == .trust(down))
    }

    @Test func trustDialogForAnotherFolderOrWithoutContextGetsNothing() {
        #expect(keys(Screens.trustDialog + Screens.trustAfterDown, folder: "/Users/me/code") == .wait)
        #expect(keys(Screens.trustAfterDown) == .wait)
    }

    @Test func statusIsTypedOnlyAtTheInputPrompt() {
        #expect(keys(Screens.replReady) == .typeStatus)
        // Claude Code asked a question right after drawing the prompt: `❯` is on that question's "Yes".
        #expect(keys(Screens.replThenStartupDialog) == .wait)
    }

    @Test func statusIsSubmittedOnlyOnceShownHighlighted() {
        let typed = Screens.replReady + Screens.statusTyped
        #expect(keys(typed, stage: .statusTyped) == .submitStatus)
        #expect(keys(Screens.replReady, stage: .statusTyped) == .wait)
        #expect(keys(typed, stage: .statusSubmitted) == .wait)
    }

    @Test func exitIsRecognizedOnlyWhenHighlighted() {
        #expect(ClaudeStatusProbe.highlights("/exit", description: "Exit the CLI", onScreen: Screens.exitTyped))
        #expect(!ClaudeStatusProbe.highlights("/exit", description: "Exit the CLI", onScreen: Screens.replReady))
    }

    @Test func childEnvironmentKeepsOnlyAllowedVariables() {
        let env = ClaudeStatusProbe.environment(
            executable: "/opt/tools/claude",
            workingDirectory: URL(fileURLWithPath: "/tmp/probe"),
            base: [
                "HOME": "/Users/me",
                "PATH": "/usr/bin:/bin",
                "LC_ALL": "it_IT.UTF-8",
                "HTTPS_PROXY": "http://proxy:8080",
                "ANTHROPIC_API_KEY": "sk-test",
                "CLAUDE_CODE_OAUTH_TOKEN": "token",
                "CLAUDECODE": "1",
                "NODE_OPTIONS": "--require /tmp/x.js"
            ]
        )
        #expect(env["HOME"] == "/Users/me")
        #expect(env["LC_ALL"] == "it_IT.UTF-8")
        #expect(env["HTTPS_PROXY"] == "http://proxy:8080")
        #expect(env["ANTHROPIC_API_KEY"] == nil)
        #expect(env["CLAUDE_CODE_OAUTH_TOKEN"] == nil)
        #expect(env["CLAUDECODE"] == nil)
        #expect(env["NODE_OPTIONS"] == nil)
        #expect(env["PATH"] == "/opt/tools:/usr/bin:/bin")
        #expect(env["PWD"] == "/tmp/probe")
        #expect(env["DISABLE_AUTOUPDATER"] == "1")
    }
}
