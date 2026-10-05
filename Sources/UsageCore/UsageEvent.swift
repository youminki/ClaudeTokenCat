import Foundation

/// 어시스턴트 응답 1건의 토큰 사용량 (JSONL 1레코드에서 추출, 중복 제거 전).
public struct UsageEvent: Equatable, Sendable {
    public let timestamp: Date
    public let model: String
    public let requestId: String
    public let messageId: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreationTokens: Int
    public let cacheReadTokens: Int
    /// 레코드 최상위 entrypoint (실측: "cli", "claude-desktop"). 프로그래매틱 구분용.
    public let entrypoint: String?

    /// 프로그래매틱 사용 추정 (Agent SDK 등 — 2026-06-15부터 별도 크레딧 풀).
    /// 실측 데이터에 SDK 레코드가 없어 "sdk" 포함 여부로 관용 판별 (docs/jsonl-schema.md).
    public var isProgrammatic: Bool {
        entrypoint?.lowercased().contains("sdk") == true
    }

    /// 중복 제거 키. docs/jsonl-schema.md: 같은 응답이 최대 6줄로 중복 기록됨.
    public var dedupKey: String { "\(messageId):\(requestId)" }

    /// 총 토큰 = 4개 필드 합 (ccusage와 동일 규칙).
    public var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens
    }

    public init(timestamp: Date, model: String, requestId: String, messageId: String,
                inputTokens: Int, outputTokens: Int,
                cacheCreationTokens: Int, cacheReadTokens: Int,
                entrypoint: String? = nil) {
        self.timestamp = timestamp
        self.model = model
        self.requestId = requestId
        self.messageId = messageId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.entrypoint = entrypoint
    }
}
