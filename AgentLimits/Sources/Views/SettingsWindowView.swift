import SwiftUI

struct SettingsWindowView: View {
    @Environment(ProviderCoordinator.self) private var coordinator
    @Environment(LoginItemManager.self) private var loginItemManager

    var body: some View {
        @Bindable var loginItemManager = loginItemManager

        TabView {
            Form {
                Toggle("Avvia al login", isOn: $loginItemManager.isEnabled)

                if !loginItemManager.canRegisterLoginItem {
                    Text("Sposta AgentLimits in /Applications per attivare l'avvio al login.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if loginItemManager.hasStaleRegistration {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("È registrata una voce di avvio al login che punta a una copia non installata di AgentLimits.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Rimuovi voce di login errata") {
                            loginItemManager.removeStaleRegistration()
                        }
                    }
                }
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
