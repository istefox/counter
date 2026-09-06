import XCTest
@testable import AgentLimits

final class CodexUsageModelsTests: XCTestCase {
    func testMergesRealWorldRateLimitsAndByLimitIdShapes() throws {
        // Sample captured from a real `account/rateLimits/read` JSON-RPC response
        // (see Project verification log — codex app-server over stdio, no daemon).
        // The default `rateLimits` bucket only reported a weekly window here; the 5h
        // session window only showed up under a `rateLimitsByLimitId` bucket labeled
        // with an unrelated model name — the two must be merged by window duration.
        let json = """
        {
            "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": { "usedPercent": 1, "windowDurationMins": 10080, "resetsAt": 1789234801 },
                "secondary": null,
                "planType": "pro"
            },
            "rateLimitsByLimitId": {
                "codex_bengalfox": {
                    "limitId": "codex_bengalfox",
                    "limitName": "GPT-5.3-Codex-Spark",
                    "primary": { "usedPercent": 0, "windowDurationMins": 300, "resetsAt": 1788694889 },
                    "secondary": { "usedPercent": 0, "windowDurationMins": 10080, "resetsAt": 1789231890 },
                    "planType": "pro"
                }
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(CodexAccountRateLimits.self, from: json)
        let rows = result.rows

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].id, "codex-300")
        XCTAssertEqual(rows[0].displayTitle, "Finestra 5 ore")
        XCTAssertEqual(rows[0].percent, 0)
        XCTAssertEqual(rows[1].id, "codex-10080")
        XCTAssertEqual(rows[1].displayTitle, "Limite settimanale")
        XCTAssertEqual(rows[1].percent, 1, "weekly window: the higher of the two reported percentages (1% vs 0%) wins")
    }

    func testDecodesWithoutRateLimitsByLimitId() throws {
        let json = """
        {
            "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": { "usedPercent": 5, "windowDurationMins": 300, "resetsAt": 1789000000 },
                "secondary": null,
                "planType": "plus"
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(CodexAccountRateLimits.self, from: json)
        let rows = result.rows

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].displayTitle, "Finestra 5 ore")
        XCTAssertEqual(rows[0].percent, 5)
    }

    func testHandlesMissingResetsAtAndUnrecognizedWindowDuration() throws {
        let json = """
        {
            "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": { "usedPercent": 10, "windowDurationMins": 1440 },
                "secondary": null,
                "planType": null
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(CodexAccountRateLimits.self, from: json)
        let rows = result.rows

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].displayTitle, "Finestra 24 ore")
        XCTAssertNil(rows[0].resetsAt)
    }

    func testIgnoresWindowsWithoutADuration() throws {
        let json = """
        {
            "rateLimits": {
                "limitId": "codex",
                "limitName": null,
                "primary": { "usedPercent": 10 },
                "secondary": null,
                "planType": null
            }
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder().decode(CodexAccountRateLimits.self, from: json)

        XCTAssertTrue(result.rows.isEmpty)
    }
}
