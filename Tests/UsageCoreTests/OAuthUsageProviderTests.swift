import XCTest
@testable import UsageCore

final class OAuthUsageProviderTests: XCTestCase {

    // docs/usage-endpoint.md의 실측 응답을 축약한 픽스처
    static let realResponse = """
    {
      "five_hour": { "utilization": 61.0, "resets_at": "2026-07-14T11:50:00.300459+00:00",
                     "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
      "seven_day": { "utilization": 42.0, "resets_at": "2026-07-19T11:00:00.300485+00:00",
                     "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
      "seven_day_opus": null,
      "limits": [
        { "kind": "session", "group": "session", "percent": 61, "severity": "normal",
          "resets_at": "2026-07-14T11:50:00.300459+00:00", "scope": null, "is_active": true },
        { "kind": "weekly_all", "group": "weekly", "percent": 42, "severity": "normal",
          "resets_at": "2026-07-19T11:00:00.300485+00:00", "scope": null, "is_active": false }
      ],
      "extra_usage": { "is_enabled": false },
      "member_dashboard_available": false
    }
    """

    func testParsesRealResponse() throws {
        let usage = try XCTUnwrap(OAuthUsageProvider.parse(
            data: Data(Self.realResponse.utf8), fetchedAt: Date()))
        XCTAssertEqual(usage.sessionPercent, 61.0)
        XCTAssertEqual(usage.weeklyPercent, 42.0)

        let iso = ISO8601DateFormatter()
        let sessionReset = try XCTUnwrap(usage.sessionResetsAt)
        let weeklyReset = try XCTUnwrap(usage.weeklyResetsAt)
        XCTAssertEqual(sessionReset.timeIntervalSince(iso.date(from: "2026-07-14T11:50:00Z")!), 0.3, accuracy: 0.01)
        XCTAssertEqual(weeklyReset.timeIntervalSince(iso.date(from: "2026-07-19T11:00:00Z")!), 0.3, accuracy: 0.01)
    }

    func testFallsBackToLimitsArray() throws {
        // five_hour/seven_day가 사라져도 limits[]에서 복원 (스키마 변경 대비)
        let json = """
        { "limits": [
            { "kind": "session", "percent": 30, "resets_at": "2026-07-14T11:50:00Z" },
            { "kind": "weekly_all", "percent": 55, "resets_at": "2026-07-19T11:00:00Z" }
        ] }
        """
        let usage = try XCTUnwrap(OAuthUsageProvider.parse(data: Data(json.utf8), fetchedAt: Date()))
        XCTAssertEqual(usage.sessionPercent, 30)
        XCTAssertEqual(usage.weeklyPercent, 55)
        XCTAssertNotNil(usage.sessionResetsAt)
    }

    func testRejectsResponseWithoutAnyPercent() {
        XCTAssertNil(OAuthUsageProvider.parse(data: Data("{}".utf8), fetchedAt: Date()))
        XCTAssertNil(OAuthUsageProvider.parse(data: Data("not json".utf8), fetchedAt: Date()))
    }

    // MARK: 자격증명 파싱 (토큰 값은 픽스처 — 실제 토큰 아님)

    func testParseCredentialsWithExpiry() throws {
        let json = #"{"claudeAiOauth":{"accessToken":"tok_fixture","expiresAt":1789400000000}}"#
        let parsed = try XCTUnwrap(OAuthUsageProvider.parseCredentials(Data(json.utf8)))
        XCTAssertEqual(parsed.token, "tok_fixture")
        XCTAssertEqual(parsed.expiresAt, Date(timeIntervalSince1970: 1_789_400_000))
    }

    func testParseCredentialsWithoutExpiryAssumesOneHour() throws {
        let now = Date()
        let json = #"{"claudeAiOauth":{"accessToken":"tok_fixture"}}"#
        let parsed = try XCTUnwrap(OAuthUsageProvider.parseCredentials(Data(json.utf8), now: now))
        XCTAssertEqual(parsed.expiresAt, now.addingTimeInterval(OAuthUsageProvider.defaultTokenLifetime))
    }

    func testParseCredentialsRejectsMissingToken() {
        XCTAssertNil(OAuthUsageProvider.parseCredentials(Data("{}".utf8)))
        XCTAssertNil(OAuthUsageProvider.parseCredentials(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)))
        XCTAssertNil(OAuthUsageProvider.parseCredentials(Data("garbage".utf8)))
    }
}
