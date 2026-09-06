import Testing
import Foundation
@testable import AgentLimits

@MainActor
struct ProviderVisibilityStoreTests {
    private func makeIsolatedDefaults(suiteName: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func defaultsToAllVisibleWhenEmpty() {
        let suiteName = "ProviderVisibilityStoreTests.defaultsToAllVisibleWhenEmpty"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProviderVisibilityStore(defaults: defaults)

        for provider in UsageProvider.allCases {
            #expect(store.isVisible(provider))
        }
    }

    @Test func setVisibleUpdatesOnlyTargetProvider() {
        let suiteName = "ProviderVisibilityStoreTests.setVisibleUpdatesOnlyTargetProvider"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProviderVisibilityStore(defaults: defaults)
        store.setVisible(false, for: .codex)

        #expect(!store.isVisible(.codex))
        #expect(store.isVisible(.claudeCode))
        #expect(store.isVisible(.antigravity))
    }

    @Test func persistsAcrossStoreInstances() {
        let suiteName = "ProviderVisibilityStoreTests.persistsAcrossStoreInstances"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = ProviderVisibilityStore(defaults: defaults)
        firstStore.setVisible(false, for: .antigravity)

        let secondStore = ProviderVisibilityStore(defaults: defaults)
        #expect(!secondStore.isVisible(.antigravity))
    }

    @Test func visibleProvidersPreservesOrderAndFiltersHidden() {
        let suiteName = "ProviderVisibilityStoreTests.visibleProvidersPreservesOrderAndFiltersHidden"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProviderVisibilityStore(defaults: defaults)
        store.setVisible(false, for: .codex)

        #expect(store.visibleProviders == [.claudeCode, .antigravity])
    }

    @Test func visibleProvidersIsEmptyWhenAllHidden() {
        let suiteName = "ProviderVisibilityStoreTests.visibleProvidersIsEmptyWhenAllHidden"
        let defaults = makeIsolatedDefaults(suiteName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ProviderVisibilityStore(defaults: defaults)
        for provider in UsageProvider.allCases {
            store.setVisible(false, for: provider)
        }

        #expect(store.visibleProviders.isEmpty)
    }
}
