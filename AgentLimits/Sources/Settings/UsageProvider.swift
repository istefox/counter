import Foundation

enum UsageProvider: String, CaseIterable, Identifiable {
    case claudeCode
    case codex
    case antigravity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode:
            return "Claude Code"
        case .codex:
            return "Codex"
        case .antigravity:
            return "Antigravity (Gemini)"
        }
    }

    var defaultsKey: String {
        "providerVisibility.\(rawValue)"
    }
}
