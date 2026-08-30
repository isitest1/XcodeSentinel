import XCTest
@testable import SentinelCore

final class WebhookPayloadTests: XCTestCase {
    private let url = URL(string: "https://example.test/hook")!
    private let now = makeDate(2026, 8, 30, 14, 32, 0, timeZone: "UTC")

    private func build(_ preset: WebhookPreset, line: String = "Session limit reached.", template: String? = nil) -> WebhookRequest {
        WebhookPayloadBuilder.build(
            preset: preset, endpoint: url, targetName: "SampleApp",
            line: line, now: now, template: template
        )
    }

    func testNtfyPutsTitleInHeaderAndLineInBody() {
        let r = build(.ntfy)
        XCTAssertEqual(r.method, "POST")
        XCTAssertEqual(r.headers["Title"], "XcodeSentinel — SampleApp")
        XCTAssertEqual(r.bodyString, "Session limit reached.")
    }

    func testSlackAndDiscordUseTextField() {
        for preset in [WebhookPreset.slack, .discord] {
            let r = build(preset)
            XCTAssertEqual(r.headers["Content-Type"], "application/json")
            XCTAssertEqual(
                r.bodyString,
                #"{"text":"*XcodeSentinel — SampleApp*\nSession limit reached."}"#
            )
        }
    }

    func testPushoverHasTitleMessageTimestamp() {
        let r = build(.pushover)
        // sortedKeys → message, timestamp, title
        XCTAssertEqual(
            r.bodyString,
            #"{"message":"Session limit reached.","timestamp":"2026-08-30T14:32:00Z","title":"XcodeSentinel — SampleApp"}"#
        )
    }

    func testCustomTemplateSubstitutesAndEscapes() {
        let r = build(
            .custom,
            line: #"He said "stop" now"#,
            template: #"{"t":"{{title}}","m":"{{message}}","ts":"{{timestamp}}"}"#
        )
        XCTAssertEqual(
            r.bodyString,
            #"{"t":"XcodeSentinel — SampleApp","m":"He said \"stop\" now","ts":"2026-08-30T14:32:00Z"}"#
        )
    }

    func testCustomFallsBackToADefaultTemplate() {
        let r = build(.custom, template: nil)
        XCTAssertTrue(r.bodyString.contains("\"message\":\"Session limit reached.\""))
        XCTAssertTrue(r.bodyString.contains("\"timestamp\":\"2026-08-30T14:32:00Z\""))
    }

    func testJSONPayloadsExposeOnlyAllowlistedKeys() {
        // Guards the privacy contract (CLAUDE.md 8.2): the structured body may
        // only carry title / message / timestamp / text.
        let allowed: Set<String> = ["title", "message", "timestamp", "text"]
        for preset in [WebhookPreset.slack, .discord, .pushover] {
            let data = build(preset).body
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let keys = Set((obj ?? [:]).keys)
            XCTAssertTrue(keys.isSubset(of: allowed), "\(preset) exposed \(keys.subtracting(allowed))")
        }
    }

    func testPayloadBodyIsJustTheStatusLineForNtfy() {
        // No structured fields at all — the line is the whole body.
        XCTAssertEqual(build(.ntfy, line: "Weekly limit reached.").bodyString, "Weekly limit reached.")
    }
}
