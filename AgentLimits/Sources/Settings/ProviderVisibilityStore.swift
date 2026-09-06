import Foundation
import Observation

@MainActor
@Observable
final class ProviderVisibilityStore {
    private let defaults: UserDefaults
    private var visibility: [UsageProvider: Bool]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var initial: [UsageProvider: Bool] = [:]
        for provider in UsageProvider.allCases {
            if defaults.object(forKey: provider.defaultsKey) == nil {
                initial[provider] = true
            } else {
                initial[provider] = defaults.bool(forKey: provider.defaultsKey)
            }
        }
        self.visibility = initial
    }

    func isVisible(_ provider: UsageProvider) -> Bool {
        visibility[provider] ?? true
    }

    func setVisible(_ isVisible: Bool, for provider: UsageProvider) {
        visibility[provider] = isVisible
        defaults.set(isVisible, forKey: provider.defaultsKey)
    }

    var visibleProviders: [UsageProvider] {
        UsageProvider.allCases.filter { isVisible($0) }
    }
}
