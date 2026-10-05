import XCTest
@testable import UsageCore

final class JSONLParserTests: XCTestCase {

    // docs/jsonl-schema.md의 실물 스키마를 그대로 축약한 픽스처
    static let validLine = """
    {"type":"assistant","timestamp":"2026-07-13T03:01:38.767Z","requestId":"req_011AAA","sessionId":"s1","uuid":"u1","entrypoint":"cli","message":{"id":"msg_01XYZ","model":"claude-sonnet-5","role":"assistant","usage":{"input_tokens":12804,"cache_creation_input_tokens":6154,"cache_read_input_tokens":28286,"output_tokens":260,"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":6154,"ephemeral_5m_input_tokens":0},"speed":"standard"}}}
    """

    func testParsesValidAssistantLine() throws {
        let event = try XCTUnwrap(JSONLParser.parse(line: Self.validLine))
        XCTAssertEqual(event.model, "claude-sonnet-5")
        XCTAssertEqual(event.requestId, "req_011AAA")
        XCTAssertEqual(event.messageId, "msg_01XYZ")
        XCTAssertEqual(event.inputTokens, 12804)
        XCTAssertEqual(event.outputTokens, 260)
        XCTAssertEqual(event.cacheCreationTokens, 6154)
        XCTAssertEqual(event.cacheReadTokens, 28286)
        XCTAssertEqual(event.totalTokens, 12804 + 260 + 6154 + 28286)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.timestamp)
        XCTAssertEqual([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second],
                       [2026, 7, 13, 3, 1, 38])
    }

    func testSkipsNonAssistantTypes() {
        for type in ["user", "system", "attachment", "file-history-snapshot", "mode"] {
            let line = #"{"type":"\#(type)","timestamp":"2026-07-13T03:01:38.767Z"}"#
            XCTAssertNil(JSONLParser.parse(line: line), "type=\(type) should be skipped")
        }
    }

    func testSkipsSyntheticModel() {
        let line = Self.validLine.replacingOccurrences(of: "claude-sonnet-5", with: "<synthetic>")
        XCTAssertNil(JSONLParser.parse(line: line))
    }

    func testSkipsMissingUsage() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T03:01:38.767Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5"}}
        """
        XCTAssertNil(JSONLParser.parse(line: line))
    }

    func testSkipsMalformedJSON() {
        XCTAssertNil(JSONLParser.parse(line: "not json at all"))
        XCTAssertNil(JSONLParser.parse(line: "{\"type\":\"assistant\", truncated"))
    }

    func testParsesTimestampWithoutFractionalSeconds() {
        let line = Self.validLine.replacingOccurrences(of: "03:01:38.767Z", with: "03:01:38Z")
        XCTAssertNotNil(JSONLParser.parse(line: line))
    }

    func testEntrypointAndProgrammaticFlag() throws {
        let interactive = try XCTUnwrap(JSONLParser.parse(line: Self.validLine))
        XCTAssertEqual(interactive.entrypoint, "cli")
        XCTAssertFalse(interactive.isProgrammatic)

        let sdkLine = Self.validLine.replacingOccurrences(of: "\"entrypoint\":\"cli\"",
                                                          with: "\"entrypoint\":\"sdk-ts\"")
        let programmatic = try XCTUnwrap(JSONLParser.parse(line: sdkLine))
        XCTAssertTrue(programmatic.isProgrammatic)

        // entrypoint 없는 구버전 레코드도 파싱되고 인터랙티브 취급
        let noEntry = Self.validLine.replacingOccurrences(of: "\"entrypoint\":\"cli\",", with: "")
        let legacy = try XCTUnwrap(JSONLParser.parse(line: noEntry))
        XCTAssertNil(legacy.entrypoint)
        XCTAssertFalse(legacy.isProgrammatic)
    }

    func testMissingTokenFieldsDefaultToZero() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T03:01:38.767Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5","usage":{"output_tokens":42}}}
        """
        let event = try XCTUnwrap(JSONLParser.parse(line: line))
        XCTAssertEqual(event.totalTokens, 42)
    }
}
