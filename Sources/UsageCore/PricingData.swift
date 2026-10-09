// scripts/update-prices.py가 만든 파일이다. 손으로 고치지 말고 스크립트를 다시 돌린다.
// 출처: LiteLLM model_prices_and_context_window.json (MIT), 2026-10-10

extension PricingTable {
    /// 모델 이름별 단가 (USD / 1M tokens). 캐시 쓰기는 5분 TTL 단가.
    static let generated: [(prefix: String, rates: Rates)] = [
        ("claude-fable-5",        Rates(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1)),
        ("claude-fable-5-1",      Rates(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25)),
        ("claude-haiku-4-5",      Rates(input: 1, output: 5, cacheWrite: 1.25, cacheRead: 0.1)),
        ("claude-haiku-5-5",      Rates(input: 0.1, output: 0.5, cacheWrite: 0.125, cacheRead: 0.01)),
        ("claude-mythos-5",       Rates(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1)),
        ("claude-mythos-5-1",     Rates(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 0.25)),
        ("claude-mythos-preview", Rates(input: 10, output: 50, cacheWrite: 12.5, cacheRead: 1)),
        ("claude-opus-4-5",       Rates(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
        ("claude-opus-4-6",       Rates(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
        ("claude-opus-4-7",       Rates(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
        ("claude-opus-4-8",       Rates(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
        ("claude-opus-5",         Rates(input: 5, output: 25, cacheWrite: 6.25, cacheRead: 0.5)),
        ("claude-opus-5-5",       Rates(input: 4, output: 20, cacheWrite: 5, cacheRead: 0.2)),
        ("claude-sonnet-4-5",     Rates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)),
        ("claude-sonnet-4-6",     Rates(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3)),
        ("claude-sonnet-5",       Rates(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.2)),
        ("claude-sonnet-5-5",     Rates(input: 2, output: 10, cacheWrite: 2.5, cacheRead: 0.1)),
    ]
}
