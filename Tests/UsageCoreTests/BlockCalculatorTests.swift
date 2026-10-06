import Foundation
import Testing
@testable import UsageCore

struct BlockCalculatorTests {

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: iso)!
    }

    private func event(at iso: String, tokens: Int = 100, id: String = UUID().uuidString) -> UsageEvent {
        UsageEvent(timestamp: date(iso), model: "claude-sonnet-5",
                   requestId: "req_\(id)", messageId: "msg_\(id)",
                   inputTokens: tokens, outputTokens: 0,
                   cacheCreationTokens: 0, cacheReadTokens: 0)
    }

    @Test func blockStartFlooredToUTCHour() {
        let blocks = BlockCalculator.blocks(from: [event(at: "2026-07-13T03:47:12Z")])
        #expect(blocks.count == 1)
        #expect(blocks[0].start == date("2026-07-13T03:00:00Z"))
        #expect(blocks[0].end == date("2026-07-13T08:00:00Z"))
    }

    @Test func eventsWithinFiveHoursShareBlock() {
        let blocks = BlockCalculator.blocks(from: [
            event(at: "2026-07-13T03:30:00Z", tokens: 100),
            event(at: "2026-07-13T07:59:59Z", tokens: 200),
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].totalTokens == 300)
    }

    @Test func eventAfterBlockEndStartsNewBlock() {
        let blocks = BlockCalculator.blocks(from: [
            event(at: "2026-07-13T03:30:00Z"),
            event(at: "2026-07-13T08:00:01Z"),
        ])
        #expect(blocks.count == 2)
        #expect(blocks[1].start == date("2026-07-13T08:00:00Z"))
    }

    @Test func currentBlockNilWhenExpired() {
        let events = [event(at: "2026-07-13T03:30:00Z")]
        #expect(BlockCalculator.currentBlock(from: events, now: date("2026-07-13T07:00:00Z")) != nil)
        #expect(BlockCalculator.currentBlock(from: events, now: date("2026-07-13T08:00:00Z")) == nil)
    }

    @Test func unsortedInputHandled() {
        let blocks = BlockCalculator.blocks(from: [
            event(at: "2026-07-13T07:00:00Z", tokens: 1),
            event(at: "2026-07-13T03:30:00Z", tokens: 2),
        ])
        #expect(blocks.count == 1)
        #expect(blocks[0].start == date("2026-07-13T03:00:00Z"))
        #expect(blocks[0].totalTokens == 3)
    }
}
