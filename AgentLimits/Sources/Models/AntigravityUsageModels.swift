import Foundation

/// Only the fields this app reads from Antigravity's `GetUserStatus` response are
/// declared — the real payload is much larger (supported MIME types, UI tags, etc.)
/// and `Decodable` silently ignores undeclared keys, so no DTO needs to cover the
/// whole shape. Verified live in this session against a real account via the
/// language server's Connect-RPC endpoint (see AntigravityClient.swift).
struct AntigravityQuotaInfo: Decodable {
    let remainingFraction: Double?
    let resetTime: String?

    var resetTimeDate: Date? {
        resetTime.flatMap { antigravityISOFormatter.date(from: $0) }
    }
}

struct AntigravityModelOrAlias: Decodable {
    let model: String?
}

struct AntigravityModelConfig: Decodable {
    let label: String?
    let modelOrAlias: AntigravityModelOrAlias?
    let quotaInfo: AntigravityQuotaInfo?
}

struct AntigravityCascadeModelConfigData: Decodable {
    let clientModelConfigs: [AntigravityModelConfig]?
}

struct AntigravityPlanInfo: Decodable {
    let planName: String?
    let monthlyPromptCredits: Int?
    let monthlyFlowCredits: Int?
}

struct AntigravityPlanStatus: Decodable {
    let planInfo: AntigravityPlanInfo?
    let availablePromptCredits: Int?
    let availableFlowCredits: Int?
}

struct AntigravityUserStatus: Decodable {
    let cascadeModelConfigData: AntigravityCascadeModelConfigData?
    let planStatus: AntigravityPlanStatus?
}

struct AntigravityUsageRow: Identifiable, UsageLimitDisplayable {
    let id: String
    let displayTitle: String
    let percent: Double
    let resetsAt: Date?
}

extension AntigravityUserStatus {
    /// One row per model that reports a quota fraction, plus account-level credit
    /// rows when the plan tracks them. Models without `quotaInfo`/`remainingFraction`
    /// are skipped — same "ignore windows without data" behavior as Codex's rows.
    var rows: [AntigravityUsageRow] {
        let modelRows = (cascadeModelConfigData?.clientModelConfigs ?? [])
            .compactMap { config -> AntigravityUsageRow? in
                guard let fraction = config.quotaInfo?.remainingFraction else { return nil }
                let title = config.label ?? config.modelOrAlias?.model ?? "Modello sconosciuto"
                return AntigravityUsageRow(
                    id: "antigravity-\(config.modelOrAlias?.model ?? title)",
                    displayTitle: title,
                    percent: (1 - fraction) * 100,
                    resetsAt: config.quotaInfo?.resetTimeDate
                )
            }

        let creditRows = [
            creditRow(
                id: "antigravity-prompt-credits",
                title: "Crediti prompt",
                available: planStatus?.availablePromptCredits,
                monthly: planStatus?.planInfo?.monthlyPromptCredits
            ),
            creditRow(
                id: "antigravity-flow-credits",
                title: "Crediti flow",
                available: planStatus?.availableFlowCredits,
                monthly: planStatus?.planInfo?.monthlyFlowCredits
            ),
        ].compactMap { $0 }

        return modelRows + creditRows
    }

    private func creditRow(id: String, title: String, available: Int?, monthly: Int?) -> AntigravityUsageRow? {
        guard let available, let monthly, monthly > 0 else { return nil }
        let usedPercent = (1 - Double(available) / Double(monthly)) * 100
        return AntigravityUsageRow(id: id, displayTitle: title, percent: usedPercent, resetsAt: nil)
    }
}

// Configured once and only ever read afterwards, so sharing across isolation
// domains is safe despite ISO8601DateFormatter not being Sendable.
nonisolated(unsafe) private let antigravityISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
