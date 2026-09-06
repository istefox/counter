import SwiftUI

@main
struct AgentLimitsApp: App {
    @State private var claudeMonitor = UsageMonitor()
    @State private var codexMonitor = CodexUsageMonitor()
    @State private var loginItemManager = LoginItemManager()

    var body: some Scene {
        MenuBarExtra("AgentLimits", systemImage: "gauge.with.dots.needle.67percent") {
            UsagePopoverView()
                .environment(claudeMonitor)
                .environment(codexMonitor)
                .environment(loginItemManager)
                .task {
                    claudeMonitor.startPolling()
                    codexMonitor.startPolling()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
