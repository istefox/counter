import AppKit
import SwiftUI

struct UsagePopoverView: View {
    @Environment(UsageMonitor.self) private var claudeMonitor
    @Environment(CodexUsageMonitor.self) private var codexMonitor
    @Environment(AntigravityUsageMonitor.self) private var antigravityMonitor
    @Environment(LoginItemManager.self) private var loginItemManager

    var body: some View {
        @Bindable var loginItemManager = loginItemManager

        VStack(alignment: .leading, spacing: 16) {
            providerSection(title: "Claude Code", lastUpdated: claudeMonitor.lastUpdated) {
                if let usage = claudeMonitor.usage {
                    ForEach(usage.limits) { limit in
                        UsageProgressRow(limit: limit)
                    }
                } else if let error = claudeMonitor.lastError {
                    Text(errorMessage(for: error))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Caricamento…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            providerSection(title: "Codex", lastUpdated: codexMonitor.lastUpdated) {
                if let usage = codexMonitor.usage {
                    ForEach(usage.rows) { row in
                        UsageProgressRow(limit: row)
                    }
                } else if let error = codexMonitor.lastError {
                    Text(errorMessage(for: error))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Caricamento…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            providerSection(title: "Antigravity (Gemini)", lastUpdated: antigravityMonitor.lastUpdated) {
                if let usage = antigravityMonitor.usage {
                    ForEach(usage.rows) { row in
                        UsageProgressRow(limit: row)
                    }
                } else if let error = antigravityMonitor.lastError {
                    Text(errorMessage(for: error))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Caricamento…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            Toggle("Avvia al login", isOn: $loginItemManager.isEnabled)
                .toggleStyle(.switch)

            HStack {
                Button("Aggiorna ora") {
                    Task {
                        await claudeMonitor.refresh()
                        await codexMonitor.refresh()
                        await antigravityMonitor.refresh()
                    }
                }
                .disabled(claudeMonitor.isRefreshing || codexMonitor.isRefreshing || antigravityMonitor.isRefreshing)

                Spacer()

                Button("Esci") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(16)
        .frame(width: 300)
        .task {
            await claudeMonitor.refresh()
            await codexMonitor.refresh()
            await antigravityMonitor.refresh()
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
