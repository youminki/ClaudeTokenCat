import Foundation
import Testing
@testable import UsageCore

struct JSONLParserTests {

    // docs/jsonl-schema.md의 실물 스키마를 그대로 축약한 픽스처
    static let validLine = """
    {"type":"assistant","timestamp":"2026-07-13T03:01:38.767Z","requestId":"req_011AAA","sessionId":"s1","uuid":"u1","entrypoint":"cli","message":{"id":"msg_01XYZ","model":"claude-sonnet-5","role":"assistant","usage":{"input_tokens":12804,"cache_creation_input_tokens":6154,"cache_read_input_tokens":28286,"output_tokens":260,"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":6154,"ephemeral_5m_input_tokens":0},"speed":"standard"}}}
    """

    @Test func parsesValidAssistantLine() throws {
        let event = try #require(JSONLParser.parse(line: Self.validLine))
        #expect(event.model == "claude-sonnet-5")
        #expect(event.requestId == "req_011AAA")
        #expect(event.messageId == "msg_01XYZ")
        #expect(event.inputTokens == 12804)
        #expect(event.outputTokens == 260)
        #expect(event.cacheCreationTokens == 6154)
        #expect(event.cacheReadTokens == 28286)
        #expect(event.totalTokens == 12804 + 260 + 6154 + 28286)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: event.timestamp)
        #expect([parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second] == [2026, 7, 13, 3, 1, 38])
    }

    @Test func skipsNonAssistantTypes() {
        for type in ["user", "system", "attachment", "file-history-snapshot", "mode"] {
            let line = #"{"type":"\#(type)","timestamp":"2026-07-13T03:01:38.767Z"}"#
            #expect(JSONLParser.parse(line: line) == nil, Comment(rawValue: "type=\(type) should be skipped"))
        }
    }

    @Test func skipsSyntheticModel() {
        let line = Self.validLine.replacingOccurrences(of: "claude-sonnet-5", with: "<synthetic>")
        #expect(JSONLParser.parse(line: line) == nil)
    }

    @Test func skipsMissingUsage() {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T03:01:38.767Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5"}}
        """
        #expect(JSONLParser.parse(line: line) == nil)
    }

    @Test func skipsMalformedJSON() {
        #expect(JSONLParser.parse(line: "not json at all") == nil)
        #expect(JSONLParser.parse(line: "{\"type\":\"assistant\", truncated") == nil)
    }

    @Test func parsesTimestampWithoutFractionalSeconds() {
        let line = Self.validLine.replacingOccurrences(of: "03:01:38.767Z", with: "03:01:38Z")
        #expect(JSONLParser.parse(line: line) != nil)
    }

    @Test func entrypointAndProgrammaticFlag() throws {
        let interactive = try #require(JSONLParser.parse(line: Self.validLine))
        #expect(interactive.entrypoint == "cli")
        #expect(!(interactive.isProgrammatic))

        let sdkLine = Self.validLine.replacingOccurrences(of: "\"entrypoint\":\"cli\"",
                                                          with: "\"entrypoint\":\"sdk-ts\"")
        let programmatic = try #require(JSONLParser.parse(line: sdkLine))
        #expect(programmatic.isProgrammatic)

        // entrypoint 없는 구버전 레코드도 파싱되고 인터랙티브 취급
        let noEntry = Self.validLine.replacingOccurrences(of: "\"entrypoint\":\"cli\",", with: "")
        let legacy = try #require(JSONLParser.parse(line: noEntry))
        #expect(legacy.entrypoint == nil)
        #expect(!(legacy.isProgrammatic))
    }

    @Test func missingTokenFieldsDefaultToZero() throws {
        let line = """
        {"type":"assistant","timestamp":"2026-07-13T03:01:38.767Z","requestId":"req_1","message":{"id":"msg_1","model":"claude-sonnet-5","usage":{"output_tokens":42}}}
        """
        let event = try #require(JSONLParser.parse(line: line))
        #expect(event.totalTokens == 42)
    }

    @Test func parsesClientVersion() throws {
        let line = Self.validLine.replacingOccurrences(of: #""entrypoint":"cli","#,
                                                       with: #""entrypoint":"cli","version":"2.1.283","#)
        #expect(try #require(JSONLParser.parse(line: line)).clientVersion == "2.1.283")
        #expect(try #require(JSONLParser.parse(line: Self.validLine)).clientVersion == nil)
    }

    @Test func nonStringVersionKeepsUsage() throws {
        let line = Self.validLine.replacingOccurrences(of: #""entrypoint":"cli","#,
                                                       with: #""entrypoint":"cli","version":2,"#)
        let event = try #require(JSONLParser.parse(line: line))
        #expect(event.clientVersion == nil)
        #expect(event.inputTokens == 12804)
    }
}
