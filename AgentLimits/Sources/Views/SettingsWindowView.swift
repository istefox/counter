import SwiftUI

struct SettingsWindowView: View {
    @Environment(ProviderCoordinator.self) private var coordinator
    @Environment(LoginItemManager.self) private var loginItemManager

    var body: some View {
        @Bindable var loginItemManager = loginItemManager

        TabView {
            Form {
                Toggle("Avvia al login", isOn: $loginItemManager.isEnabled)
            }
            .padding(20)
            .tabItem {
                Label("Generali", systemImage: "gearshape")
            }

            Form {
                ForEach(UsageProvider.allCases) { provider in
                    Toggle(provider.displayName, isOn: providerBinding(for: provider))
                }
            }
            .padding(20)
            .tabItem {
                Label("Provider", systemImage: "list.bullet")
            }
        }
        .frame(width: 360, height: 200)
    }

    private func providerBinding(for provider: UsageProvider) -> Binding<Bool> {
        Binding(
            get: { coordinator.isVisible(provider) },
            set: { coordinator.setVisible($0, for: provider) }
        )
    }
}
