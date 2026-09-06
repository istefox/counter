import Foundation

/// Common shape a provider's usage row must expose to be rendered by `UsageProgressRow`,
/// so the popover can show Claude Code and Codex rows through the same view.
protocol UsageLimitDisplayable: Identifiable {
    var displayTitle: String { get }
    var percent: Double { get }
    var resetsAt: Date? { get }
}
