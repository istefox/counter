import XCTest
@testable import AgentLimits

final class LoginItemManagerTests: XCTestCase {
    func testDerivedDataBuildIsNotInstalled() {
        let url = URL(fileURLWithPath: "/Users/stefer/Library/Developer/Xcode/DerivedData/AgentLimits-abc/Build/Products/Debug/AgentLimits.app")
        XCTAssertFalse(LoginItemManager.isInstalledLocation(url))
    }

    func testApplicationsIsInstalled() {
        let url = URL(fileURLWithPath: "/Applications/AgentLimits.app")
        XCTAssertTrue(LoginItemManager.isInstalledLocation(url))
    }

    func testUserApplicationsIsInstalled() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications", isDirectory: true)
            .appendingPathComponent("AgentLimits.app")
        XCTAssertTrue(LoginItemManager.isInstalledLocation(url))
    }

    func testDownloadsIsNotInstalled() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
            .appendingPathComponent("AgentLimits.app")
        XCTAssertFalse(LoginItemManager.isInstalledLocation(url))
    }
}
