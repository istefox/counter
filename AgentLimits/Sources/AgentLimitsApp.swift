import AppKit
import SwiftUI

@main
struct AgentLimitsApp: App {
    @State private var claudeMonitor = UsageMonitor()
    @State private var codexMonitor = CodexUsageMonitor()
    @State private var antigravityMonitor = AntigravityUsageMonitor()
    @State private var loginItemManager = LoginItemManager()

    var body: some Scene {
        MenuBarExtra("AgentLimits", systemImage: "gauge.with.dots.needle.67percent") {
            UsagePopoverView()
                .environment(claudeMonitor)
                .environment(codexMonitor)
                .environment(antigravityMonitor)
                .environment(loginItemManager)
                .task {
                    claudeMonitor.startPolling()
                    codexMonitor.startPolling()
                    antigravityMonitor.startPolling()
                    NotificationCenter.default.addObserver(
                        forName: NSApplication.willTerminateNotification,
                        object: nil,
                        queue: nil
                    ) { _ in
                        Task { await antigravityMonitor.shutdown() }
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
