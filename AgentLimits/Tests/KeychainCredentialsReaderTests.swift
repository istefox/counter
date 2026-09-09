import XCTest
@testable import AgentLimits

final class KeychainCredentialsReaderTests: XCTestCase {
    func testReadsTokenUsingExactServiceAndAccountArguments() throws {
        var arguments: [String] = []
        let reader = KeychainCredentialsReader { received in
            arguments = received
            return Data("{\"claudeAiOauth\":{\"accessToken\":\"test-token\"}}\n".utf8)
        }

        XCTAssertEqual(try reader.readAccessToken(), "test-token")
        XCTAssertEqual(arguments, [
            "find-generic-password", "-s", "Claude Code-credentials",
            "-a", NSUserName(), "-w"
        ])
    }

    func testRejectsMalformedMissingAndEmptyCredentialsWithoutExposingPayload() {
        let payloads = [
            "private-test-payload",
            "{}",
            "{\"claudeAiOauth\":{\"accessToken\":\"\"}}",
            "{\"claudeAiOauth\":{\"accessToken\":\"   \"}}"
        ]
        for payload in payloads {
            let reader = KeychainCredentialsReader { _ in Data(payload.utf8) }
            XCTAssertThrowsError(try reader.readAccessToken()) { error in
                XCTAssertEqual(error as? KeychainError, .invalidCredentials)
                XCTAssertFalse(String(describing: error).contains("private-test-payload"))
            }
        }
    }

    func testCommandFailurePreservesProviderFallback() throws {
        for failure in [KeychainError.unavailable(status: 44), .timeout, .launchFailed] {
            let reader = KeychainCredentialsReader { _ in throw failure }
            let provider = CredentialsProvider(sources: [reader, FallbackCredentialsSource()])
            XCTAssertEqual(try provider.currentAccessToken(), "fallback-token")
        }
    }
}

final class CredentialCommandRunnerTests: XCTestCase {
    func testDrainsOutputLargerThanPipeCapacity() throws {
        let data = try CredentialCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "262144", "/dev/zero"]
        )
        XCTAssertEqual(data.count, 262_144)
        XCTAssertTrue(data.allSatisfy { $0 == 0 })
    }

    func testDiscardsLargeStandardError() throws {
        let data = try runShell("/usr/bin/head -c 262144 /dev/zero >&2; printf ok")
        XCTAssertEqual(String(data: data, encoding: .utf8), "ok")
    }

    func testPassesArgumentsLiterallyWithoutShellExpansion() throws {
        let argument = "account with spaces; \u{24}(echo injected)"
        let data = try CredentialCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/printf"),
            arguments: ["%s", argument]
        )
        XCTAssertEqual(String(data: data, encoding: .utf8), argument)
    }

    func testRejectsNonzeroExitWithoutExposingOutput() {
        XCTAssertThrowsError(try runShell("printf private-test-payload; exit 44")) { error in
            XCTAssertEqual(error as? KeychainError, .unavailable(status: 44))
            XCTAssertFalse(String(describing: error).contains("private-test-payload"))
        }
    }

    func testReportsLaunchFailure() {
        XCTAssertThrowsError(try CredentialCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/nonexistent-agentlimits-test-command"),
            arguments: []
        )) { error in
            XCTAssertEqual(error as? KeychainError, .launchFailed)
        }
    }

    func testCapsOutputSize() {
        XCTAssertThrowsError(try CredentialCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/head"),
            arguments: ["-c", "262144", "/dev/zero"],
            maximumOutputBytes: 1024
        )) { error in
            XCTAssertEqual(error as? KeychainError, .outputTooLarge)
        }
    }

    func testTimesOutStalledProcess() {
        let start = ContinuousClock.now
        XCTAssertThrowsError(try CredentialCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["10"],
            timeout: .milliseconds(100)
        )) { error in
            XCTAssertEqual(error as? KeychainError, .timeout)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    func testTimesOutEvenAfterChildClosesStandardOutput() {
        let start = ContinuousClock.now
        XCTAssertThrowsError(try runShell(
            "exec 1>&-; exec /bin/sleep 10", timeout: .milliseconds(100)
        )) { error in
            XCTAssertEqual(error as? KeychainError, .timeout)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(3))
    }

    private func runShell(_ script: String, timeout: Duration = .seconds(5)) throws -> Data {
        try CredentialCommandRunner.run(
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", script],
            timeout: timeout
        )
    }
}

private struct FallbackCredentialsSource: CredentialsSource {
    func readAccessToken() throws -> String { "fallback-token" }
}
