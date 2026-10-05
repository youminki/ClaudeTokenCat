import Foundation

/// Claude Code 설정 폴더. `CLAUDE_CONFIG_DIR`이 있으면 그 경로를 쓰는 Claude Code 관례를 따른다.
public enum ClaudePaths {

    public static var configDirectory: URL {
        ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }
}

/// JSONL과 usage 응답의 시각 문자열 파싱.
/// usage 응답은 마이크로초 6자리("…00.300459+00:00")라 ISO8601DateFormatter가 못 읽을 때가 있다.
enum ISODate {

    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let microseconds: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string) ?? microseconds.date(from: string)
    }
}
