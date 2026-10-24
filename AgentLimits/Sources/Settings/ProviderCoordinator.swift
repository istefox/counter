import Foundation
import Observation

@MainActor
@Observable
final class ProviderCoordinator {
    let claude: UsageMonitor
    let codex: CodexUsageMonitor
    let antigravity: AntigravityUsageMonitor

    /// Providers whose CLI login was launched from the app and that are being re-polled
    /// until fresh credentials show up.
    private(set) var pendingLogins: Set<UsageProvider> = []
    private(set) var loginLaunchError: UsageProvider?

    private let visibilityStore: ProviderVisibilityStore
    private let launchLogin: @MainActor (UsageProvider) throws -> Void
    private var loginWatchTasks: [UsageProvider: Task<Void, Never>] = [:]

    init(
        claude: UsageMonitor = UsageMonitor(),
        codex: CodexUsageMonitor = CodexUsageMonitor(),
        antigravity: AntigravityUsageMonitor = AntigravityUsageMonitor(),
        visibilityStore: ProviderVisibilityStore = ProviderVisibilityStore(),
        launchLogin: @escaping @MainActor (UsageProvider) throws -> Void = CLILoginLauncher.launch(for:)
    ) {
        self.claude = claude
        self.codex = codex
        self.antigravity = antigravity
        self.visibilityStore = visibilityStore
        self.launchLogin = launchLogin
    }

    func isVisible(_ provider: UsageProvider) -> Bool {
        visibilityStore.isVisible(provider)
    }

    var visibleProviders: [UsageProvider] {
        visibilityStore.visibleProviders
    }

    var isRefreshingVisible: Bool {
        visibleProviders.contains { provider in
            switch provider {
            case .claudeCode:
                return claude.isRefreshing
            case .codex:
                return codex.isRefreshing
            case .antigravity:
                return antigravity.isRefreshing
            }
        }
    }

    func setVisible(_ isVisible: Bool, for provider: UsageProvider) {
        visibilityStore.setVisible(isVisible, for: provider)
        let monitorControl = monitorControl(for: provider)
        if isVisible {
            monitorControl.startPolling()
        } else {
            monitorControl.stopPolling()
        }
    }

    func startPollingForVisibleProviders() {
        for provider in visibleProviders {
            monitorControl(for: provider).startPolling()
        }
    }

    func refreshVisible() async {
        for provider in visibleProviders {
            await monitorControl(for: provider).refresh()
        }
    }

    func supportsLogin(_ provider: UsageProvider) -> Bool {
        CLILoginLauncher.loginCommand(for: provider) != nil
    }

    /// True when the provider's last refresh failed because its credentials are missing or expired.
    func needsLogin(_ provider: UsageProvider) -> Bool {
        switch provider {
        case .claudeCode:
            return claude.lastError == .notAuthenticated || claude.lastError == .tokenExpired
        case .codex:
            return codex.lastError == .notAuthenticated
        case .antigravity:
            return false
        }
    }

    /// Opens the provider's official CLI login, then re-polls every few seconds so the
    /// popover recovers on its own as soon as the new credentials are written.
    func startLogin(
        for provider: UsageProvider,
        pollInterval: Duration = .seconds(5),
        timeout: Duration = .seconds(300)
    ) {
        guard supportsLogin(provider) else { return }
        do {
            try launchLogin(provider)
            loginLaunchError = nil
        } catch {
            loginLaunchError = provider
            return
        }

        loginWatchTasks[provider]?.cancel()
        pendingLogins.insert(provider)
        loginWatchTasks[provider] = Task { [weak self] in
            let deadline = ContinuousClock.now + timeout
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: pollInterval)
                guard let self, !Task.isCancelled else { return }
                await self.monitorControl(for: provider).refresh()
                if !self.needsLogin(provider) { break }
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingLogins.remove(provider)
            self.loginWatchTasks[provider] = nil
        }
    }

    private func monitorControl(for provider: UsageProvider) -> any PollingUsageMonitor {
        switch provider {
        case .claudeCode:
            return claude
        case .codex:
            return codex
        case .antigravity:
            return antigravity
        }
    }
}

@MainActor
protocol PollingUsageMonitor {
    func startPolling(interval: Duration)
    func stopPolling()
    func refresh() async
}

extension PollingUsageMonitor {
    func startPolling() {
        startPolling(interval: .seconds(300))
    }
}

extension UsageMonitor: PollingUsageMonitor {}
extension CodexUsageMonitor: PollingUsageMonitor {}
extension AntigravityUsageMonitor: PollingUsageMonitor {}
