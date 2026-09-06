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

struct AntigravityUserStatus: Decodable {
    let cascadeModelConfigData: AntigravityCascadeModelConfigData?
}

struct AntigravityUsageRow: Identifiable, UsageLimitDisplayable {
    let id: String
    let displayTitle: String
    let percent: Double
    let resetsAt: Date?
}

extension AntigravityUserStatus {
    /// A single aggregated "Gemini" row, not one row per model. Live inspection of
    /// `GetUserStatus` (this session, real account) confirmed every entry in
    /// `clientModelConfigs` — Gemini variants, Claude-via-Antigravity, GPT-OSS alike —
    /// shares one account-level quota pool: identical `remainingFraction`/`resetTime`
    /// across the board. So there is no per-model data to preserve, and no second,
    /// shorter-duration window exists anywhere in the payload to show alongside it.
    /// Non-Gemini models and the generic prompt/flow credit counters are intentionally
    /// left out: the user only wants the Gemini-specific total.
    var rows: [AntigravityUsageRow] {
        let geminiConfigs = (cascadeModelConfigData?.clientModelConfigs ?? [])
            .filter { ($0.label ?? "").hasPrefix("Gemini") }

        guard let fraction = geminiConfigs.compactMap(\.quotaInfo?.remainingFraction).min() else {
            return []
        }
        let resetsAt = geminiConfigs.compactMap(\.quotaInfo?.resetTimeDate).first

        return [
            AntigravityUsageRow(
                id: "antigravity-gemini",
                displayTitle: "Gemini",
                percent: (1 - fraction) * 100,
                resetsAt: resetsAt
            )
        ]
    }
}

// Configured once and only ever read afterwards, so sharing across isolation
// domains is safe despite ISO8601DateFormatter not being Sendable.
nonisolated(unsafe) private let antigravityISOFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
