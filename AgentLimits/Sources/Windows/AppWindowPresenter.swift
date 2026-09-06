import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppWindowPresenter {
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var closeObservers: [ObjectIdentifier: NSObjectProtocol] = [:]

    func showSettings(coordinator: ProviderCoordinator, loginItemManager: LoginItemManager) {
        if let settingsWindow {
            activate(settingsWindow)
            return
        }

        let window = makeWindow(title: "Impostazioni") {
            SettingsWindowView()
                .environment(coordinator)
                .environment(loginItemManager)
        }
        settingsWindow = window
        observeClose(of: window) { [weak self] in
            self?.settingsWindow = nil
        }
        activate(window)
    }

    func showAbout() {
        if let aboutWindow {
            activate(aboutWindow)
            return
        }

        let window = makeWindow(title: "About AgentLimits") {
            AboutView()
        }
        aboutWindow = window
        observeClose(of: window) { [weak self] in
            self?.aboutWindow = nil
        }
        activate(window)
    }

    private func makeWindow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> NSWindow {
        let hosting = NSHostingController(rootView: content())
        let window = NSWindow(contentViewController: hosting)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        return window
    }

    private func observeClose(of window: NSWindow, onClose: @escaping @MainActor () -> Void) {
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                onClose()
                self?.restoreActivationPolicyIfNeeded()
            }
        }
        closeObservers[ObjectIdentifier(window)] = token
    }

    private func activate(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func restoreActivationPolicyIfNeeded() {
        if settingsWindow == nil && aboutWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
