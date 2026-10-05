import XCTest
@testable import UsageCore

final class UsageStoreTests: XCTestCase {

    private func event(minutesAgo: Double, tokens: Int, id: String, now: Date) -> UsageEvent {
        UsageEvent(timestamp: now.addingTimeInterval(-minutesAgo * 60),
                   model: "claude-sonnet-5",
                   requestId: "req_\(id)", messageId: "msg_\(id)",
                   inputTokens: tokens, outputTokens: 0,
                   cacheCreationTokens: 0, cacheReadTokens: 0)
    }

    func testDeduplicatesByMessageIdAndRequestId() {
        let store = UsageStore()
        let now = Date()
        let e = event(minutesAgo: 1, tokens: 500, id: "dup", now: now)
        // 실물 JSONL은 같은 응답을 최대 6줄로 중복 기록한다
        XCTAssertEqual(store.add([e, e, e, e, e, e]), 1)
        XCTAssertEqual(store.snapshot(now: now).todayTokens, 500)
    }

    func testTokensLast60s() {
        let store = UsageStore()
        let now = Date()
        store.add([
            event(minutesAgo: 0.5, tokens: 100, id: "a", now: now),
            event(minutesAgo: 0.9, tokens: 200, id: "b", now: now),
            event(minutesAgo: 2.0, tokens: 999, id: "c", now: now),
        ])
        XCTAssertEqual(store.snapshot(now: now).tokensLast60s, 300)
    }

    func testTodayTokensExcludesYesterday() {
        let store = UsageStore()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(3600) // 오늘 01:00
        store.add([
            event(minutesAgo: 30, tokens: 100, id: "today", now: now),
            event(minutesAgo: 120, tokens: 999, id: "yesterday", now: now), // 전날 23:00
        ])
        XCTAssertEqual(store.snapshot(now: now).todayTokens, 100)
    }

    func testWeeklyTokensAndModelShares() {
        let store = UsageStore()
        let now = Date()
        var opus = event(minutesAgo: 60, tokens: 300, id: "o", now: now)
        opus = UsageEvent(timestamp: opus.timestamp, model: "claude-opus-4-8",
                          requestId: opus.requestId, messageId: opus.messageId,
                          inputTokens: 300, outputTokens: 0, cacheCreationTokens: 0, cacheReadTokens: 0)
        store.add([
            opus,
            event(minutesAgo: 120, tokens: 700, id: "s", now: now),
            event(minutesAgo: 8 * 24 * 60, tokens: 999, id: "old", now: now), // 8일 전 → 롤링 7일 밖
        ])
        let snap = store.snapshot(now: now)
        XCTAssertEqual(snap.weeklyTokens, 1000)
        XCTAssertEqual(snap.weeklyModelTokens["claude-opus-4-8"], 300)
        XCTAssertEqual(snap.weeklyModelTokens["claude-sonnet-5"], 700)
    }

    func testWeeklyWindowWithCustomStart() {
        let store = UsageStore()
        let now = Date()
        store.add([
            event(minutesAgo: 30, tokens: 100, id: "in", now: now),
            event(minutesAgo: 90, tokens: 200, id: "out", now: now),
        ])
        let snap = store.snapshot(now: now, weeklySince: now.addingTimeInterval(-3600))
        XCTAssertEqual(snap.weeklyTokens, 100)
    }

    func testSparklineBuckets() {
        let store = UsageStore()
        let now = Date()
        store.add([
            event(minutesAgo: 0.5, tokens: 10, id: "a", now: now),   // 마지막 버킷
            event(minutesAgo: 5.5, tokens: 20, id: "b", now: now),   // 5분 전 버킷
            event(minutesAgo: 29.5, tokens: 30, id: "c", now: now),  // 첫 버킷
            event(minutesAgo: 31, tokens: 99, id: "d", now: now),    // 창 밖
        ])
        let spark = store.snapshot(now: now).sparkline
        XCTAssertEqual(spark.count, 30)
        XCTAssertEqual(spark[29], 10)
        XCTAssertEqual(spark[24], 20)
        XCTAssertEqual(spark[0], 30)
        XCTAssertEqual(spark.reduce(0, +), 60)
    }

    func testTokensSince() {
        let store = UsageStore()
        let now = Date()
        store.add([
            event(minutesAgo: 1, tokens: 100, id: "new", now: now),
            event(minutesAgo: 10, tokens: 200, id: "old", now: now),
        ])
        XCTAssertEqual(store.tokens(since: now.addingTimeInterval(-300), now: now), 100)
        XCTAssertEqual(store.tokens(since: now.addingTimeInterval(-3600), now: now), 300)
    }

    func testDailyTotalsAndProgrammaticSplit() {
        let store = UsageStore()
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date()).addingTimeInterval(2 * 3600) // 오늘 02:00
        let sdkEvent = UsageEvent(timestamp: now.addingTimeInterval(-1800), model: "claude-sonnet-5",
                                  requestId: "r_sdk", messageId: "m_sdk",
                                  inputTokens: 400, outputTokens: 0,
                                  cacheCreationTokens: 0, cacheReadTokens: 0,
                                  entrypoint: "sdk-py")
        store.add([
            event(minutesAgo: 60, tokens: 100, id: "t1", now: now),      // 오늘 01:00
            sdkEvent,                                                     // 오늘 01:30 (SDK)
            event(minutesAgo: 5 * 60, tokens: 200, id: "y1", now: now),  // 전날 21:00
        ])
        let snap = store.snapshot(now: now)
        XCTAssertEqual(snap.todayTokens, 500)
        XCTAssertEqual(snap.todayProgrammaticTokens, 400)
        XCTAssertEqual(snap.dailyTotals.count, 2)
        XCTAssertEqual(snap.dailyTotals[0].tokens, 500)   // 최신(오늘)부터
        XCTAssertEqual(snap.dailyTotals[1].tokens, 200)
        XCTAssertGreaterThan(snap.dailyTotals[0].costUSD, 0)
    }

    func testCostUsesPricingTable() {
        let store = UsageStore()
        let now = Date()
        // sonnet: input $3/MTok → 1M input = $3
        let e = UsageEvent(timestamp: now.addingTimeInterval(-60), model: "claude-sonnet-5",
                           requestId: "r", messageId: "m",
                           inputTokens: 1_000_000, outputTokens: 0,
                           cacheCreationTokens: 0, cacheReadTokens: 0)
        store.add([e])
        XCTAssertEqual(store.snapshot(now: now).todayCostUSD, 3.0, accuracy: 0.001)
    }

}
