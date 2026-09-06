import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @Environment(UsageMonitor.self) private var monitor
    @Environment(LoginItemManager.self) private var loginItemManager

    var body: some View {
        @Bindable var loginItemManager = loginItemManager

        VStack(alignment: .leading, spacing: 12) {
            header

            if let usage = monitor.usage {
                ForEach(usage.limits) { limit in
                    UsageProgressRow(limit: limit)
                }
            } else if let error = monitor.lastError {
                Text(errorMessage(for: error))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("Caricamento…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Toggle("Avvia al login", isOn: $loginItemManager.isEnabled)
                .toggleStyle(.switch)

            HStack {
                Button("Aggiorna ora") {
                    Task { await monitor.refresh() }
                }
                .disabled(monitor.isRefreshing)

                Spacer()

                Button("Esci") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .task {
            await monitor.refresh()
        }
    }

    private var header: some View {
        HStack {
            Text("Claude Code")
                .font(.headline)
            Spacer()
            if let lastUpdated = monitor.lastUpdated {
                Text(lastUpdated.formatted(date: .omitted, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
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
}
