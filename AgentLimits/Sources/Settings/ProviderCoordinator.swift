import Foundation
import Observation

@MainActor
@Observable
final class ProviderCoordinator {
    let claude: UsageMonitor
    let codex: CodexUsageMonitor
    let antigravity: AntigravityUsageMonitor

    private let visibilityStore: ProviderVisibilityStore

    init(
        claude: UsageMonitor = UsageMonitor(),
        codex: CodexUsageMonitor = CodexUsageMonitor(),
        antigravity: AntigravityUsageMonitor = AntigravityUsageMonitor(),
        visibilityStore: ProviderVisibilityStore = ProviderVisibilityStore()
    ) {
        self.claude = claude
        self.codex = codex
        self.antigravity = antigravity
        self.visibilityStore = visibilityStore
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
