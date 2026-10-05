import XCTest
@testable import UsageCore

final class BlockCalculatorTests: XCTestCase {

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

    func testBlockStartFlooredToUTCHour() {
        let blocks = BlockCalculator.blocks(from: [event(at: "2026-07-13T03:47:12Z")])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].start, date("2026-07-13T03:00:00Z"))
        XCTAssertEqual(blocks[0].end, date("2026-07-13T08:00:00Z"))
    }

    func testEventsWithinFiveHoursShareBlock() {
        let blocks = BlockCalculator.blocks(from: [
            event(at: "2026-07-13T03:30:00Z", tokens: 100),
            event(at: "2026-07-13T07:59:59Z", tokens: 200),
        ])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].totalTokens, 300)
    }

    func testEventAfterBlockEndStartsNewBlock() {
        let blocks = BlockCalculator.blocks(from: [
            event(at: "2026-07-13T03:30:00Z"),
            event(at: "2026-07-13T08:00:01Z"),
        ])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].start, date("2026-07-13T08:00:00Z"))
    }

    func testCurrentBlockNilWhenExpired() {
        let events = [event(at: "2026-07-13T03:30:00Z")]
        XCTAssertNotNil(BlockCalculator.currentBlock(from: events, now: date("2026-07-13T07:00:00Z")))
        XCTAssertNil(BlockCalculator.currentBlock(from: events, now: date("2026-07-13T08:00:00Z")))
    }

    func testUnsortedInputHandled() {
        let blocks = BlockCalculator.blocks(from: [
            event(at: "2026-07-13T07:00:00Z", tokens: 1),
            event(at: "2026-07-13T03:30:00Z", tokens: 2),
        ])
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].start, date("2026-07-13T03:00:00Z"))
        XCTAssertEqual(blocks[0].totalTokens, 3)
    }
}
