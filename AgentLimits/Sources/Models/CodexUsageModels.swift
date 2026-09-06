import Foundation

/// One primary/secondary window inside a `codex app-server` `account/rateLimits/read`
/// response. Field names match the JSON-RPC wire format verbatim (camelCase, unlike
/// Claude's snake_case REST API) since this is the app-server's own protocol, not a
/// third-party HTTP API. `resetsAt` is Unix seconds, unlike Claude's ISO8601 strings.
struct CodexRateLimitWindow: Decodable {
    let usedPercent: Int
    let windowDurationMins: Int?
    private let resetsAt: Int64?

    var resetsAtDate: Date? {
        resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

struct CodexRateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: CodexRateLimitWindow?
    let secondary: CodexRateLimitWindow?
    let planType: String?
}

/// Result of `account/rateLimits/read`. Verified live that the two bucket sources
/// disagree on which windows they report: the backward-compatible `rateLimits` bucket
/// only carried a weekly window (no 5h session window) on this account, while a
/// `rateLimitsByLimitId` bucket carried both the 5h and weekly windows but under a
/// `limitId`/`limitName` that is an opaque backend metering category unrelated to the
/// locally configured model (`codex_bengalfox` / "GPT-5.3-Codex-Spark" showed up while
/// `~/.codex/config.toml` had `model = "gpt-5.6-terra"`). So both sources are merged by
/// window duration rather than picking one bucket wholesale, and the confusing
/// per-bucket label is never surfaced — only the generic window kind (5h / weekly).
struct CodexAccountRateLimits: Decodable {
    let rateLimits: CodexRateLimitSnapshot
    let rateLimitsByLimitId: [String: CodexRateLimitSnapshot]?
}

struct CodexUsageRow: Identifiable, UsageLimitDisplayable {
    let id: String
    let displayTitle: String
    let percent: Double
    let resetsAt: Date?
}

extension CodexAccountRateLimits {
    /// One row per distinct window duration seen across every bucket, keeping the
    /// highest usage percent reported for that duration — the most useful signal when
    /// monitoring for an upcoming rate limit.
    var rows: [CodexUsageRow] {
        let allSnapshots = [rateLimits] + (rateLimitsByLimitId?.values.map { $0 } ?? [])
        let allWindows = allSnapshots.flatMap { [$0.primary, $0.secondary] }.compactMap { $0 }

        var bestByDuration: [Int: CodexRateLimitWindow] = [:]
        for window in allWindows {
            guard let duration = window.windowDurationMins else { continue }
            if let existing = bestByDuration[duration], existing.usedPercent >= window.usedPercent {
                continue
            }
            bestByDuration[duration] = window
        }

        return bestByDuration.sorted { $0.key < $1.key }.map { duration, window in
            CodexUsageRow(
                id: "codex-\(duration)",
                displayTitle: Self.windowLabel(for: duration),
                percent: Double(window.usedPercent),
                resetsAt: window.resetsAtDate
            )
        }
    }

    private static func windowLabel(for minutes: Int) -> String {
        switch minutes {
        case 300: return "Finestra 5 ore"
        case 10080: return "Limite settimanale"
        default: return "Finestra \(minutes / 60) ore"
        }
    }
}
