import AppKit
import SwiftUI

@main
struct AgentLimitsApp: App {
    @State private var coordinator = ProviderCoordinator()
    @State private var loginItemManager = LoginItemManager()
    @State private var windowPresenter = AppWindowPresenter()

    var body: some Scene {
        MenuBarExtra("AgentLimits", systemImage: "gauge.with.dots.needle.67percent") {
            UsagePopoverView()
                .environment(coordinator)
                .environment(loginItemManager)
                .environment(windowPresenter)
                .task {
                    coordinator.startPollingForVisibleProviders()
                    NotificationCenter.default.addObserver(
                        forName: NSApplication.willTerminateNotification,
                        object: nil,
                        queue: nil
                    ) { _ in
                        Task { await coordinator.antigravity.shutdown() }
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
