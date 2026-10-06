import AppKit
import UsageCore

// 디버그/수용기준 검증용: GUI 없이 1회 풀스캔 집계를 출력하고 종료.
// ccusage blocks 결과와 대조하는 데 사용 (§7 오차 2% 기준).
if CommandLine.arguments.contains("--report") {
    let watcher = JSONLWatcher()
    let store = UsageStore()
    let start = Date()
    store.add(watcher.scan())
    let snap = store.snapshot()
    print("scan: \(String(format: "%.0f", Date().timeIntervalSince(start) * 1000))ms, events(dedup): \(snap.totalEventCount)")
    print("today: \(snap.todayTokens) tokens, $\(String(format: "%.2f", snap.todayCostUSD)) (추정)")
    if let block = snap.currentBlock {
        let iso = ISO8601DateFormatter()
        print("current block: \(iso.string(from: block.start)) ~ \(iso.string(from: block.end))")
        print("current block tokens: \(block.totalTokens) (entries: \(block.eventCount))")
    } else {
        print("current block: none")
    }
    print("last 60s: \(snap.tokensLast60s) tokens")
    print("weekly(rolling 7d): \(snap.weeklyTokens) tokens, models: \(snap.weeklyModelTokens)")

    // 공식 % 1회 조회 (§7: /usage 표시값과 일치 검증용)
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        do {
            let usage = try await OAuthUsageProvider().fetch(clientVersion: snap.latestClientVersion)
            print("official: session \(usage.sessionPercent.map { "\($0)%" } ?? "-")"
                + " (resets \(usage.sessionResetsAt.map { ISO8601DateFormatter().string(from: $0) } ?? "-"))"
                + ", weekly \(usage.weeklyPercent.map { "\($0)%" } ?? "-")")
        } catch {
            print("official: FAILED (\(error)) → 추정 모드 폴백")
        }
        semaphore.signal()
    }
    semaphore.wait()
    exit(0)
}

// 디자인 점검용: 모든 러너의 대표 장면을 PNG로 저장하고 종료.
if let index = CommandLine.arguments.firstIndex(of: "--sprite-sheet") {
    let args = Array(CommandLine.arguments.dropFirst(index + 1))
    let path = args.first ?? "sprite-sheet"
    let filter = args.dropFirst().first
    let runners = filter.map { $0.split(separator: ",").compactMap { Runner(rawValue: String($0)) } }
    do {
        if filter == "pack" {
            try SpriteSheet.writePack(to: URL(fileURLWithPath: path))
        } else {
            try SpriteSheet.write(to: URL(fileURLWithPath: path), runners: runners ?? Runner.allCases)
        }
        print("saved: \(path)")
        exit(0)
    } catch {
        print("failed: \(error)")
        exit(1)
    }
}

// README GIF 생성: 러너 몇 마리가 차례로 달리는 애니메이션.
if let index = CommandLine.arguments.firstIndex(of: "--hero-gif") {
    let path = CommandLine.arguments.dropFirst(index + 1).first ?? "tokencat-run.gif"
    try? SpriteSheet.writeHeroGIF(to: URL(fileURLWithPath: path))
    print("saved: \(path)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // Dock 아이콘 없이 메뉴바 전용
app.run()
