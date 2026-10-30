import Testing
import Foundation
@testable import AgentLimits

struct CLILoginLauncherTests {
    @Test func loginCommandsUseOfficialCLIFlows() {
        #expect(CLILoginLauncher.loginCommand(for: .claudeCode)?.executableName == "claude")
        #expect(CLILoginLauncher.loginCommand(for: .claudeCode)?.arguments == ["auth", "login"])
        #expect(CLILoginLauncher.loginCommand(for: .codex)?.executableName == "codex")
        #expect(CLILoginLauncher.loginCommand(for: .codex)?.arguments == ["login"])
        #expect(CLILoginLauncher.loginCommand(for: .antigravity) == nil)
    }

    @Test func shellQuotingEscapesSingleQuotes() {
        #expect(CLILoginLauncher.shellQuoted("a b") == "'a b'")
        #expect(CLILoginLauncher.shellQuoted("it's") == "'it'\\''s'")
    }

    @Test func scriptPrefersResolvedExecutablePath() throws {
        let command = try #require(CLILoginLauncher.loginCommand(for: .codex))
        let script = CLILoginLauncher.makeScript(for: command, resolvedExecutable: "/opt/homebrew/bin/codex")
        #expect(script.hasPrefix("#!/bin/sh\n"))
        #expect(script.contains("-ilc ''\\''/opt/homebrew/bin/codex'\\'' '\\''login'\\'''"))
    }

    @Test func scriptFallsBackToBareNameWhenUnresolved() throws {
        let command = try #require(CLILoginLauncher.loginCommand(for: .claudeCode))
        let script = CLILoginLauncher.makeScript(for: command, resolvedExecutable: nil)
        #expect(script.contains("-ilc ''\\''claude'\\'' '\\''auth'\\'' '\\''login'\\'''"))
    }
}

struct CodexAuthDetectionTests {
    @Test func detectsJSONRPCErrorEnvelope() {
        // Captured from `codex app-server` with no stored credentials.
        let data = Data(#"{"error":{"code":-32600,"message":"codex account authentication required to read rate limits"},"id":2}"#.utf8)
        #expect(CodexAppServerClient.isErrorResponse(data))
        #expect(!CodexAppServerClient.isErrorResponse(Data(#"{"id":2,"result":{}}"#.utf8)))
    }

    @Test func loggedOutAccountRequiresLogin() {
        let data = Data(#"{"id":3,"result":{"account":null,"requiresOpenaiAuth":true,"workspaceRouting":null}}"#.utf8)
        #expect(CodexAppServerClient.requiresLogin(accountResponse: data))
    }

    @Test func loggedInAccountDoesNotRequireLogin() {
        let data = Data(#"{"id":3,"result":{"account":{"type":"chatgpt","email":"a@b.c","planType":"pro"},"requiresOpenaiAuth":true}}"#.utf8)
        #expect(!CodexAppServerClient.requiresLogin(accountResponse: data))
    }
}

@MainActor
struct ProviderCoordinatorLoginTests {
    private func makeCoordinator(
        suiteName: String,
        launchLogin: @escaping @MainActor (UsageProvider) throws -> Void
    ) -> ProviderCoordinator {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return ProviderCoordinator(
            visibilityStore: ProviderVisibilityStore(defaults: defaults),
            launchLogin: launchLogin
        )
    }

    @Test func startLoginLaunchesCLIAndMarksPending() {
        var launched: [UsageProvider] = []
        let coordinator = makeCoordinator(suiteName: "ProviderCoordinatorLoginTests.launch") { launched.append($0) }

        coordinator.startLogin(for: .codex, pollInterval: .seconds(60))

        #expect(launched == [.codex])
        #expect(coordinator.pendingLogins.contains(.codex))
        #expect(coordinator.loginLaunchError == nil)
    }

    @Test func launchFailureIsReportedAndNotPending() {
        let coordinator = makeCoordinator(suiteName: "ProviderCoordinatorLoginTests.failure") { _ in
            throw CLILoginError.launchFailed
        }

        coordinator.startLogin(for: .claudeCode)

        #expect(coordinator.loginLaunchError == .claudeCode)
        #expect(!coordinator.pendingLogins.contains(.claudeCode))
    }

    @Test func antigravityHasNoLoginFlow() {
        var launched: [UsageProvider] = []
        let coordinator = makeCoordinator(suiteName: "ProviderCoordinatorLoginTests.antigravity") { launched.append($0) }

        coordinator.startLogin(for: .antigravity)

        #expect(launched.isEmpty)
        #expect(!coordinator.supportsLogin(.antigravity))
    }
}
