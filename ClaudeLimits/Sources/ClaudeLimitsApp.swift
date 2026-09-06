import SwiftUI

@main
struct ClaudeLimitsApp: App {
    @State private var monitor = UsageMonitor()
    @State private var loginItemManager = LoginItemManager()

    var body: some Scene {
        MenuBarExtra("ClaudeLimits", systemImage: "gauge.with.dots.needle.67percent") {
            UsagePopoverView()
                .environment(monitor)
                .environment(loginItemManager)
                .task {
                    monitor.startPolling()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
