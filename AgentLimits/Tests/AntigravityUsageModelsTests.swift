import XCTest
@testable import AgentLimits

final class AntigravityUsageModelsTests: XCTestCase {
    func testDecodesRealWorldGetUserStatusShape() throws {
        // Trimmed sample captured live in this session from a real Antigravity
        // `GetUserStatus` Connect-RPC response (see Project verification log). The
        // real payload also carries supportedMimeTypes, tags, etc. per model, none of
        // which this app reads — `Decodable` ignores the undeclared keys.
        let json = """
        {
            "userStatus": {
                "planStatus": {
                    "planInfo": {
                        "planName": "Pro",
                        "monthlyPromptCredits": 50000,
                        "monthlyFlowCredits": 150000
                    },
                    "availablePromptCredits": 500,
                    "availableFlowCredits": 100
                },
                "cascadeModelConfigData": {
                    "clientModelConfigs": [
                        {
                            "label": "Gemini 3.6 Flash (High)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M71" },
                            "quotaInfo": { "remainingFraction": 1, "resetTime": "2026-09-13T07:31:11Z" }
                        },
                        {
                            "label": "Gemini 3.1 Pro (High)",
                            "modelOrAlias": { "model": "MODEL_PLACEHOLDER_M16" },
                            "quotaInfo": { "remainingFraction": 0.4, "resetTime": "2026-09-13T07:31:11Z" }
                        }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: json)
        let rows = envelope.userStatus.rows

        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].displayTitle, "Gemini 3.6 Flash (High)")
        XCTAssertEqual(rows[0].percent, 0)
        XCTAssertNotNil(rows[0].resetsAt)
        XCTAssertEqual(rows[1].displayTitle, "Gemini 3.1 Pro (High)")
        XCTAssertEqual(rows[1].percent, 60, accuracy: 0.0001)
        XCTAssertEqual(rows[2].displayTitle, "Crediti prompt")
        XCTAssertEqual(rows[2].percent, 99, accuracy: 0.0001, "500 available of 50000 monthly => 99% used")
        XCTAssertEqual(rows[3].displayTitle, "Crediti flow")
    }

    func testSkipsModelsWithoutQuotaInfo() throws {
        let json = """
        {
            "userStatus": {
                "cascadeModelConfigData": {
                    "clientModelConfigs": [
                        { "label": "No Quota Model", "modelOrAlias": { "model": "MODEL_X" } }
                    ]
                }
            }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(TestEnvelope.self, from: json)

        XCTAssertTrue(envelope.userStatus.rows.isEmpty)
    }

    func testOmitsCreditRowsWhenPlanStatusMissing() throws {
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
