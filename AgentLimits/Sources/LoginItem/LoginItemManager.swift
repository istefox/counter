import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LoginItemManager {
    private(set) var lastError: Error?

    var isEnabled: Bool {
        get {
            SMAppService.mainApp.status == .enabled
        }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                lastError = nil
            } catch {
                lastError = error
            }
        }
    }
}
