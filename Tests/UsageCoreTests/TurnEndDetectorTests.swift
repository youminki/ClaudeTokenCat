import Foundation
import Testing
@testable import UsageCore

struct TurnEndDetectorTests {
    private static func line(stop: String, sidechain: String = "false", cwd: String = "/Users/me/GitHub/RunTime") -> String {
        JSONLParserTests.validLine
            .replacingOccurrences(of: #""entrypoint":"cli","#,
                                  with: #""entrypoint":"cli","cwd":"\#(cwd)","isSidechain":\#(sidechain),"#)
            .replacingOccurrences(of: #""role":"assistant","#, with: #""role":"assistant","stop_reason":\#(stop),"#)
    }

    @Test func parsesEndTurnAndProject() throws {
        let event = try #require(JSONLParser.parse(line: Self.line(stop: #""end_turn""#)))
        #expect(event.endsTurn)
        #expect(event.project == "RunTime")
    }

    @Test func toolUseSidechainAndOddValuesAreNotTurnEnds() throws {
        #expect(try #require(JSONLParser.parse(line: Self.line(stop: #""tool_use""#))).endsTurn == false)
        #expect(try #require(JSONLParser.parse(line: Self.line(stop: "null"))).endsTurn == false)
        #expect(try #require(JSONLParser.parse(line: Self.line(stop: #""end_turn""#, sidechain: "true"))).endsTurn == false)
        // 형식이 다른 부가 필드 때문에 사용량 레코드가 버려지면 안 된다
        let odd = try #require(JSONLParser.parse(line: Self.line(stop: "1", sidechain: #""yes""#)))
        #expect(odd.endsTurn == false)
        #expect(odd.totalTokens > 0)
    }

    @Test func announcesEachRecentMessageOnce() throws {
        let event = try #require(JSONLParser.parse(line: Self.line(stop: #""end_turn""#)))
        let now = event.timestamp.addingTimeInterval(5)
        var detector = TurnEndDetector()
        // 한 응답이 여러 줄로 기록된다
        #expect(detector.finishedTurns(in: [event, event], now: now).count == 1)
        #expect(detector.finishedTurns(in: [event], now: now).isEmpty)
    }

    @Test func ignoresOldHistoryReadAtLaunch() throws {
        let event = try #require(JSONLParser.parse(line: Self.line(stop: #""end_turn""#)))
        var detector = TurnEndDetector()
        #expect(detector.finishedTurns(in: [event], now: event.timestamp.addingTimeInterval(3600)).isEmpty)
    }
}
