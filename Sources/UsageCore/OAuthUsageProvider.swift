import Foundation

/// 공식 usage 엔드포인트 응답 (게이지 1순위 소스, docs/usage-endpoint.md).
public struct OfficialUsage: Equatable, Sendable {
    public let sessionPercent: Double?
    public let sessionResetsAt: Date?
    public let weeklyPercent: Double?
    public let weeklyResetsAt: Date?
    public let fetchedAt: Date

    public init(sessionPercent: Double?, sessionResetsAt: Date?,
                weeklyPercent: Double?, weeklyResetsAt: Date?, fetchedAt: Date) {
        self.sessionPercent = sessionPercent
        self.sessionResetsAt = sessionResetsAt
        self.weeklyPercent = weeklyPercent
        self.weeklyResetsAt = weeklyResetsAt
        self.fetchedAt = fetchedAt
    }
}

/// 비문서화 OAuth usage 엔드포인트 폴링 (180초 간격 준수).
/// ⚠ 토큰은 읽기 전용, Anthropic 외 어디에도 전송·로깅 금지.
/// 실패 시 호출측(엔진)이 추정 모드로 폴백한다.
///
/// 키체인 접근 설계 (프롬프트 최소화):
/// 1. 액세스 토큰은 메모리 캐시 — 만료 시에만 자격증명을 다시 읽는다 (매 폴링 금지).
/// 2. `~/.claude/.credentials.json` 파일이 있으면 키체인보다 먼저 사용.
/// 3. 키체인은 Security.framework 직접 호출 대신 `/usr/bin/security` 서브프로세스 —
///    ACL 승인("항상 허용")이 security 바이너리에 걸리므로 앱을 리빌드해도 유지된다.
/// 4. unlock-keychain 자동화·암호 저장류 편법 금지.
public final class OAuthUsageProvider {

    public enum ProviderError: Error {
        case tokenNotFound
        case http(Int)
        case badResponse
    }

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// User-Agent 필수 — 없으면 공격적 레이트리밋 버킷(429 지속). docs/usage-endpoint.md.
    static let userAgent = "claude-code/2.1.207"

    /// expiresAt이 없을 때의 보수적 토큰 수명 (~60분 만료 가정).
    static let defaultTokenLifetime: TimeInterval = 55 * 60
    /// 만료 이만큼 전부터는 새로 읽는다.
    static let expiryMargin: TimeInterval = 5 * 60

    private struct CachedToken {
        let token: String
        let expiresAt: Date
    }

    private var cachedToken: CachedToken?
    private let tokenLock = NSLock()

    public init() {}

    public func fetch() async throws -> OfficialUsage {
        do {
            return try await fetchOnce()
        } catch ProviderError.http(401) {
            // 토큰 만료/회전 — 캐시 무효화 후 새로 읽어 1회 재시도
            invalidateCachedToken()
            return try await fetchOnce()
        }
    }

    private func fetchOnce() async throws -> OfficialUsage {
        guard let token = accessToken() else { throw ProviderError.tokenNotFound }
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.badResponse }
        guard http.statusCode == 200 else { throw ProviderError.http(http.statusCode) }
        guard let usage = Self.parse(data: data, fetchedAt: Date()) else { throw ProviderError.badResponse }
        return usage
    }

    // MARK: - 토큰 캐시

    private func accessToken(now: Date = Date()) -> String? {
        tokenLock.lock()
        defer { tokenLock.unlock() }
        if let cached = cachedToken, now < cached.expiresAt.addingTimeInterval(-Self.expiryMargin) {
            return cached.token
        }
        guard let data = Self.fileCredentials() ?? Self.keychainCredentials(),
              let parsed = Self.parseCredentials(data, now: now)
        else { return nil }
        cachedToken = CachedToken(token: parsed.token, expiresAt: parsed.expiresAt)
        return parsed.token
    }

    private func invalidateCachedToken() {
        tokenLock.lock()
        cachedToken = nil
        tokenLock.unlock()
    }

    // MARK: - 응답 파싱 (스키마-관용적: 필드 누락 시 nil, 둘 다 없으면 실패)

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 실측 응답은 마이크로초 6자리("…00.300459+00:00") — ISO8601DateFormatter가 못 읽는 경우 대비.
    static let microsecondsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        return f
    }()

    private static func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFormatter.date(from: s)
            ?? isoFormatterNoFraction.date(from: s)
            ?? microsecondsFormatter.date(from: s)
    }

    private static func percent(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    public static func parse(data: Data, fetchedAt: Date) -> OfficialUsage? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        var sessionPct = percent((root["five_hour"] as? [String: Any])?["utilization"])
        var sessionReset = date((root["five_hour"] as? [String: Any])?["resets_at"])
        var weeklyPct = percent((root["seven_day"] as? [String: Any])?["utilization"])
        var weeklyReset = date((root["seven_day"] as? [String: Any])?["resets_at"])

        // 폴백: five_hour/seven_day가 없으면 limits[] 배열에서 추출
        if sessionPct == nil || weeklyPct == nil, let limits = root["limits"] as? [[String: Any]] {
            for limit in limits {
                switch limit["kind"] as? String {
                case "session" where sessionPct == nil:
                    sessionPct = percent(limit["percent"])
                    sessionReset = sessionReset ?? date(limit["resets_at"])
                case "weekly_all" where weeklyPct == nil:
                    weeklyPct = percent(limit["percent"])
                    weeklyReset = weeklyReset ?? date(limit["resets_at"])
                default: break
                }
            }
        }

        guard sessionPct != nil || weeklyPct != nil else { return nil }
        return OfficialUsage(sessionPercent: sessionPct, sessionResetsAt: sessionReset,
                             weeklyPercent: weeklyPct, weeklyResetsAt: weeklyReset,
                             fetchedAt: fetchedAt)
    }

    // MARK: - 자격증명 로드 (파일 우선 → 키체인 서브프로세스, docs/usage-endpoint.md)

    /// credentials JSON → (액세스 토큰, 만료 시각). expiresAt(epoch ms)이 없으면 ~60분 가정.
    static func parseCredentials(_ data: Data, now: Date = Date()) -> (token: String, expiresAt: Date)? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { return nil }
        let expiresAt = (oauth["expiresAt"] as? NSNumber)
            .map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            ?? now.addingTimeInterval(defaultTokenLifetime)
        return (token, expiresAt)
    }

    static func fileCredentials() -> Data? {
        let configDir = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        return try? Data(contentsOf: configDir.appendingPathComponent(".credentials.json"))
    }

    /// `/usr/bin/security find-generic-password -s "Claude Code-credentials" -a $USER -w`
    /// Security.framework 직접 호출 금지 — ACL이 앱 서명이 아닌 security 바이너리에 걸려
    /// 리빌드해도 "항상 허용" 승인이 유지된다.
    static func keychainCredentials() -> Data? {
        let base = ["find-generic-password", "-s", "Claude Code-credentials"]
        // 계정 지정 조회 → 실패 시 계정 생략 폴백 (관용)
        return runSecurity(base + ["-a", NSUserName(), "-w"])
            ?? runSecurity(base + ["-w"])
    }

    private static func runSecurity(_ arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()   // 에러 출력 무시 (토큰 관련 정보 로깅 금지)
        do {
            try process.run()
        } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()   // 첫 접근 시 키체인 프롬프트가 뜨면 사용자 응답까지 대기
        guard process.terminationStatus == 0 else { return nil }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
        else { return nil }
        return Data(text.utf8)
    }
}
