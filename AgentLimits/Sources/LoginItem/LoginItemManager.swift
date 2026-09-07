import Foundation
import Observation
import ServiceManagement

enum LoginItemError: Error {
    case notInstalledInApplications(URL)
}

@MainActor
@Observable
final class LoginItemManager {
    private(set) var lastError: Error?

    /// A login item registered from outside /Applications loses its keychain
    /// "Always Allow" grant on every rebuild, because Debug builds are re-signed
    /// with a new identity each time. Only an installed copy gets a stable one.
    nonisolated static func isInstalledLocation(_ url: URL) -> Bool {
        let resolved = url.resolvingSymlinksInPath().path
        let applicationsRoots = [
            "/Applications/",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications", isDirectory: true).path + "/",
        ]
        return applicationsRoots.contains { resolved.hasPrefix($0) }
    }

    var canRegisterLoginItem: Bool {
        Self.isInstalledLocation(Bundle.main.bundleURL)
    }

    var hasStaleRegistration: Bool {
        SMAppService.mainApp.status == .enabled && !canRegisterLoginItem
    }

    var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            guard newValue else {
                do {
                    try SMAppService.mainApp.unregister()
                    lastError = nil
                } catch {
                    lastError = error
                }
                return
            }

            guard canRegisterLoginItem else {
                lastError = LoginItemError.notInstalledInApplications(Bundle.main.bundleURL)
                return
            }

            do {
                try SMAppService.mainApp.register()
                lastError = nil
            } catch {
                lastError = error
            }
        }
    }

    func removeStaleRegistration() {
        do {
            try SMAppService.mainApp.unregister()
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
