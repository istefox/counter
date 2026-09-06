import Testing
import Foundation
@testable import AgentLimits

@MainActor
struct ProviderCoordinatorTests {
    private func makeIsolatedDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeCoordinator(suiteName: String) -> ProviderCoordinator {
        let store = ProviderVisibilityStore(defaults: makeIsolatedDefaults(suiteName: suiteName))
        return ProviderCoordinator(visibilityStore: store)
    }

    @Test func visibleProvidersMirrorsStoreFilteringByDefault() {
        let coordinator = makeCoordinator(suiteName: "ProviderCoordinatorTests.visibleProvidersMirrorsStoreFilteringByDefault")

        #expect(coordinator.visibleProviders == UsageProvider.allCases)
        for provider in UsageProvider.allCases {
            #expect(coordinator.isVisible(provider))
        }
    }

    @Test func setVisibleFalseRemovesProviderFromVisibleList() {
        let suiteName = "ProviderCoordinatorTests.setVisibleFalseRemovesProviderFromVisibleList"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProviderCoordinator(visibilityStore: ProviderVisibilityStore(defaults: defaults))

        coordinator.setVisible(false, for: .codex)

        #expect(!coordinator.isVisible(.codex))
        #expect(coordinator.visibleProviders == [.claudeCode, .antigravity])
    }

    @Test func hidingAllProvidersYieldsEmptyVisibleList() {
        let suiteName = "ProviderCoordinatorTests.hidingAllProvidersYieldsEmptyVisibleList"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let coordinator = ProviderCoordinator(visibilityStore: ProviderVisibilityStore(defaults: defaults))

        for provider in UsageProvider.allCases {
            coordinator.setVisible(false, for: provider)
        }

        #expect(coordinator.visibleProviders.isEmpty)
    }
}
