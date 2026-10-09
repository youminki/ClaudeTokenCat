import Foundation
import Testing
@testable import UsageCore

final class JSONLWatcherTests {

    private var tempDir: URL!

    init() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-test-\(UUID().uuidString)/proj-a")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: tempDir.deletingLastPathComponent())
    }

    private func line(id: String, tokens: Int) -> String {
        """
        {"type":"assistant","timestamp":"2026-07-14T03:00:00.000Z","requestId":"req_\(id)","message":{"id":"msg_\(id)","model":"claude-sonnet-5","usage":{"input_tokens":\(tokens),"output_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0}}}
        """
    }

    @Test func incrementalScan() throws {
        let file = tempDir.appendingPathComponent("session.jsonl")
        try (line(id: "1", tokens: 100) + "\n").write(to: file, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(rootDirectory: tempDir.deletingLastPathComponent())
        watcher.maxFileAge = .infinity  // 테스트 픽스처 mtime 무관하게 스캔

        let first = watcher.scan()
        #expect(first.count == 1)
        #expect(first[0].inputTokens == 100)

        // 같은 내용 재스캔 → 새 이벤트 없음 (오프셋 기억)
        #expect(watcher.scan().isEmpty)

        // 줄 추가 → 새 줄만 읽힘
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((line(id: "2", tokens: 200) + "\n").utf8))
        try handle.close()

        let second = watcher.scan()
        #expect(second.count == 1)
        #expect(second[0].inputTokens == 200)
    }

    @Test func partialLastLineNotConsumed() throws {
        let file = tempDir.appendingPathComponent("session.jsonl")
        let full = line(id: "1", tokens: 100) + "\n"
        let partial = String(line(id: "2", tokens: 200).prefix(40)) // 개행 없는 불완전 줄
        try (full + partial).write(to: file, atomically: true, encoding: .utf8)

        let watcher = JSONLWatcher(rootDirectory: tempDir.deletingLastPathComponent())
        watcher.maxFileAge = .infinity
        #expect(watcher.scan().count == 1)

        // 불완전 줄의 나머지가 마저 써지면 다음 스캔에서 읽힌다
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((String(line(id: "2", tokens: 200).dropFirst(40)) + "\n").utf8))
        try handle.close()

        let second = watcher.scan()
        #expect(second.count == 1)
        #expect(second[0].inputTokens == 200)
    }
}
