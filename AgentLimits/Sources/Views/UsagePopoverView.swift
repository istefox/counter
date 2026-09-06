import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @Environment(ProviderCoordinator.self) private var coordinator
    @Environment(LoginItemManager.self) private var loginItemManager
    @Environment(AppWindowPresenter.self) private var windowPresenter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if coordinator.visibleProviders.isEmpty {
                Text("Nessun provider selezionato — abilitane uno in Impostazioni")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(Array(coordinator.visibleProviders.enumerated()), id: \.element) { index, provider in
                    if index > 0 {
                        Divider()
                    }
                    providerContent(for: provider)
                }
            }

            Divider()

            HStack {
                Button("Aggiorna ora") {
                    Task {
                        await coordinator.refreshVisible()
                    }
                }
                .disabled(coordinator.isRefreshingVisible)

                Spacer()

                settingsMenu
            }
        }
        .padding(16)
        .frame(width: 300)
        .task {
            await coordinator.refreshVisible()
        }
    }

    @ViewBuilder
    private var settingsMenu: some View {
        Menu {
            Button("Impostazioni") {
                closePopoverThenPresent {
                    windowPresenter.showSettings(coordinator: coordinator, loginItemManager: loginItemManager)
                }
            }
            Button("About") {
                closePopoverThenPresent {
                    windowPresenter.showAbout()
                }
            }
            Button("Esci") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Impostazioni e altre azioni")
    }

    private func closePopoverThenPresent(_ present: @escaping () -> Void) {
        NSApp.keyWindow?.close()
        present()
    }

    @ViewBuilder
    private func providerContent(for provider: UsageProvider) -> some View {
        switch provider {
        case .claudeCode:
            providerSection(title: provider.displayName, lastUpdated: coordinator.claude.lastUpdated) {
                if let usage = coordinator.claude.usage {
                    ForEach(usage.limits) { limit in
                        UsageProgressRow(limit: limit)
                    }
                } else if let error = coordinator.claude.lastError {
                    Text(errorMessage(for: error))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Caricamento…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case .codex:
            providerSection(title: provider.displayName, lastUpdated: coordinator.codex.lastUpdated) {
                if let usage = coordinator.codex.usage {
                    ForEach(usage.rows) { row in
                        UsageProgressRow(limit: row)
                    }
                } else if let error = coordinator.codex.lastError {
                    Text(errorMessage(for: error))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Caricamento…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        case .antigravity:
            providerSection(title: provider.displayName, lastUpdated: coordinator.antigravity.lastUpdated) {
                if let usage = coordinator.antigravity.usage {
                    ForEach(usage.rows) { row in
                        UsageProgressRow(limit: row)
                    }
                } else if let error = coordinator.antigravity.lastError {
                    Text(errorMessage(for: error))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Caricamento…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func providerSection<Content: View>(
        title: String,
        lastUpdated: Date?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if let lastUpdated {
                    Text(lastUpdated.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            content()
        }
    }

    private func errorMessage(for error: UsageError) -> String {
        switch error {
        case .notAuthenticated:
            return "Nessuna sessione Claude Code trovata. Esegui il login dalla CLI."
        case .tokenExpired:
            return "Sessione scaduta. Esegui di nuovo il login dalla CLI Claude Code."
        case .forbidden:
            return "Il tuo account non ha accesso ai dati di utilizzo."
        case .rateLimited:
            return "Troppe richieste. Riprova tra qualche minuto."
        case .decoding:
            return "Risposta dell'API non riconosciuta."
        case .network:
            return "Errore di rete. Riprova."
        case .generic(let statusCode):
            return "Errore imprevisto (\(statusCode))."
        }
    }

    private func errorMessage(for error: CodexUsageError) -> String {
        switch error {
        case .codexNotInstalled:
            return "CLI Codex non trovata nel PATH."
        case .processFailed:
            return "Impossibile avviare Codex app-server."
        case .decoding:
            return "Risposta di Codex non riconosciuta."
        case .timeout:
            return "Codex non ha risposto in tempo."
        }
    }

    private func errorMessage(for error: AntigravityUsageError) -> String {
        switch error {
        case .antigravityNotInstalled:
            return "Google Antigravity non è installato."
        case .processFailed:
            return "Impossibile connettersi al language server di Antigravity."
        case .decoding:
            return "Risposta di Antigravity non riconosciuta."
        case .timeout:
            return "Antigravity non ha risposto in tempo."
        }
    }
}
