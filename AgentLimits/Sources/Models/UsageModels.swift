import Foundation

struct ClaudeCredentialsFile: Codable {
    struct OAuth: Codable {
        let accessToken: String
    }

    let claudeAiOauth: OAuth
}

struct UsageLimitScope: Codable {
    struct Model: Codable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }

    let model: Model?
}

/// One row of `UsageResponse.limits`. The API exposes this as a flat, self-describing
/// array (kind/group/scope) rather than fixed fields per model, so new model-scoped
/// limits (e.g. a weekly cap for "Fable") show up automatically without a schema change.
struct UsageLimit: Codable, Identifiable, UsageLimitDisplayable {
    let kind: String
    let group: String?
    let percent: Double
    let resetsAt: Date?
    let scope: UsageLimitScope?
    let isActive: Bool?

    var id: String { kind + (scope?.model?.displayName ?? "") }

    enum CodingKeys: String, CodingKey {
        case kind, group, percent, scope
        case resetsAt = "resets_at"
        case isActive = "is_active"
    }

    var displayTitle: String {
        if let modelName = scope?.model?.displayName {
            return "Settimanale \(modelName)"
        }
        switch kind {
        case "session":
            return "Finestra 5 ore"
        case "weekly_all":
            return "Limite settimanale"
        default:
            return kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

struct UsageResponse: Codable {
    let limits: [UsageLimit]
}

extension JSONDecoder {
    static var claudeUsageDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseISO8601(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized ISO8601 date: \(value)"
            )
        }
        return decoder
    }
}

/// The API returns microsecond-precision fractional seconds (e.g. "...023790+00:00"),
/// which `ISO8601DateFormatter`'s `.withFractionalSeconds` option (fixed to milliseconds)
/// fails to parse. Sub-second precision isn't shown anywhere in the UI, so the fractional
/// part is simply dropped before parsing rather than reimplementing a stricter formatter.
private func parseISO8601(_ value: String) -> Date? {
    if let date = isoFormatter.date(from: value) {
        return date
    }
    guard let dotIndex = value.firstIndex(of: ".") else { return nil }
    let offsetStart = value[dotIndex...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
    let withoutFraction: String
    if let offsetStart {
        withoutFraction = String(value[..<dotIndex]) + String(value[offsetStart...])
    } else {
        withoutFraction = String(value[..<dotIndex])
    }
    return isoFormatter.date(from: withoutFraction)
}

// Configured once and only ever read afterwards, so sharing across isolation
// domains is safe despite ISO8601DateFormatter not being Sendable.
nonisolated(unsafe) private let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
