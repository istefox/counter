import XCTest
@testable import ClaudeLimits

final class UsageModelsTests: XCTestCase {
    func testDecodesRealWorldLimitsArrayShape() throws {
        // Sample captured from a real GET /api/oauth/usage response (see Project verification log).
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-09-06T01:50:00.023790+00:00" },
            "seven_day": { "utilization": 17.0, "resets_at": "2026-09-12T06:00:00.023811+00:00" },
            "limits": [
                {
                    "kind": "session",
                    "group": "session",
                    "percent": 1,
                    "resets_at": "2026-09-06T01:50:00.023790+00:00",
                    "scope": null,
                    "is_active": false
                },
                {
                    "kind": "weekly_all",
                    "group": "weekly",
                    "percent": 17,
                    "resets_at": "2026-09-12T06:00:00.023811+00:00",
                    "scope": null,
                    "is_active": true
                },
                {
                    "kind": "weekly_scoped",
                    "group": "weekly",
                    "percent": 3,
                    "resets_at": "2026-09-12T06:00:00.024040+00:00",
                    "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
                    "is_active": false
                }
            ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeUsageDecoder.decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.limits.count, 3)
        XCTAssertEqual(response.limits[0].displayTitle, "Finestra 5 ore")
        XCTAssertEqual(response.limits[1].displayTitle, "Limite settimanale")
        XCTAssertEqual(response.limits[2].displayTitle, "Settimanale Fable")
        XCTAssertEqual(response.limits[2].percent, 3)
        XCTAssertNotNil(response.limits[2].resetsAt)
    }

    func testDecodesResetsAtWithMicrosecondPrecisionAndOffset() throws {
        let json = """
        { "limits": [
            { "kind": "session", "percent": 5, "resets_at": "2026-09-06T01:50:00.023790+00:00" }
        ] }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeUsageDecoder.decode(UsageResponse.self, from: json)

        XCTAssertNotNil(response.limits[0].resetsAt)
    }

    func testDecodesNullResetsAtAndScope() throws {
        let json = """
        { "limits": [
            { "kind": "weekly_all", "percent": 0, "resets_at": null, "scope": null }
        ] }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeUsageDecoder.decode(UsageResponse.self, from: json)

        XCTAssertNil(response.limits[0].resetsAt)
        XCTAssertEqual(response.limits[0].displayTitle, "Limite settimanale")
    }

    func testFallsBackToHumanizedKindWhenUnrecognized() throws {
        let json = """
        { "limits": [
            { "kind": "monthly_credits", "percent": 42, "resets_at": null }
        ] }
        """.data(using: .utf8)!

        let response = try JSONDecoder.claudeUsageDecoder.decode(UsageResponse.self, from: json)

        XCTAssertEqual(response.limits[0].displayTitle, "Monthly Credits")
    }
}
