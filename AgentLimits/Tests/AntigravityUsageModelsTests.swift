import XCTest
@testable import AgentLimits

final class AntigravityUsageModelsTests: XCTestCase {
    func testAggregatesGeminiVariantsIntoASingleRow() throws {
        // Trimmed sample captured live in this session from a real Antigravity
        // `GetUserStatus` Connect-RPC response (see Project verification log). The
        // real payload also carries supportedMimeTypes, tags, etc. per model, none of
        // which this app reads — `Decodable` ignores the undeclared keys. Live
        // inspection confirmed every model (Gemini and non-Gemini alike) shares the
        // exact same `remainingFraction`/`resetTime` — one account-level quota pool.
        let json = """
        {
            "userStatus": {
                "cascadeModelConfigData": {
                    "clientModelConfigs": [
                        {
                            "label": "Gemini 3.6 Flash (High)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M71" },
                            "quotaInfo": { "remainingFraction": 0.4, "resetTime": "2026-09-13T07:31:11Z" }
                        },
                        {
                            "label": "Gemini 3.1 Pro (High)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M16" },
                            "quotaInfo": { "remainingFraction": 0.4, "resetTime": "2026-09-13T07:31:11Z" }
                        },
                        {
                            "label": "Claude Sonnet 4.6 (Thinking)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_CLAUDE" },
                            "quotaInfo": { "remainingFraction": 0.4, "resetTime": "2026-09-13T07:31:11Z" }
                        },
                        {
                            "label": "GPT-OSS 120B (Medium)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_GPT" },
                            "quotaInfo": { "remainingFraction": 0.4, "resetTime": "2026-09-13T07:31:11Z" }
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: json)
        let rows = envelope.userStatus.rows

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].displayTitle, "Gemini")
        XCTAssertEqual(rows[0].percent, 60, accuracy: 0.0001)
        XCTAssertNotNil(rows[0].resetsAt)
    }

    func testSkipsModelsWithoutQuotaInfo() throws {
        let json = """
        {
            "userStatus": {
                "cascadeModelConfigData": {
                    "clientModelConfigs": [
                        { "label": "Gemini No Quota", "modelOrAlias": { "model": "MODEL_X" } }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: json)

        XCTAssertTrue(envelope.userStatus.rows.isEmpty)
    }

    func testEmptyWhenNoGeminiModelsPresent() throws {
        let json = """
        {
            "userStatus": {
                "cascadeModelConfigData": {
                    "clientModelConfigs": [
                        {
                            "label": "Claude Sonnet 4.6 (Thinking)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_CLAUDE" },
                            "quotaInfo": { "remainingFraction": 1, "resetTime": "2026-09-13T07:31:11Z" }
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: json)

        XCTAssertTrue(envelope.userStatus.rows.isEmpty)
    }

    func testEmptyWhenCascadeModelConfigDataMissing() throws {
        let json = """
        { "userStatus": {} }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: json)

        XCTAssertTrue(envelope.userStatus.rows.isEmpty)
    }
}

private struct TestEnvelope: Decodable {
    let userStatus: AntigravityUserStatus
}
