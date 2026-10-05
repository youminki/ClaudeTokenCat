import Foundation

/// JSONL 한 줄 → UsageEvent. 스키마-관용적: 필요한 필드가 없으면 nil 반환(skip).
/// 스킵 규칙은 docs/jsonl-schema.md 참조.
public enum JSONLParser {

    private struct Record: Decodable {
        let type: String
        let timestamp: String?
        let requestId: String?
        let entrypoint: String?
        let message: Message?

        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
        }
    }

    private static let decoder = JSONDecoder()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(line: Data) -> UsageEvent? {
        guard let record = try? decoder.decode(Record.self, from: line) else { return nil }
        guard record.type == "assistant",
              let message = record.message,
              let usage = message.usage,
              let model = message.model, model != "<synthetic>",
              let messageId = message.id,
              let requestId = record.requestId,
              let timestampString = record.timestamp,
              let timestamp = isoFormatter.date(from: timestampString)
                ?? isoFormatterNoFraction.date(from: timestampString)
        else { return nil }

        return UsageEvent(
            timestamp: timestamp,
            model: model,
            requestId: requestId,
            messageId: messageId,
            inputTokens: usage.input_tokens ?? 0,
            outputTokens: usage.output_tokens ?? 0,
            cacheCreationTokens: usage.cache_creation_input_tokens ?? 0,
            cacheReadTokens: usage.cache_read_input_tokens ?? 0,
            entrypoint: record.entrypoint
        )
    }

    public static func parse(line: String) -> UsageEvent? {
        parse(line: Data(line.utf8))
    }
}
