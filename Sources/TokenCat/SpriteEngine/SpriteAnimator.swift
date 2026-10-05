import AppKit
import UsageCore

/// 표시 상태별 프레임 시퀀스를 상태별 간격으로 순환 재생.
/// 프레임은 현재 appearance로 1회 래스터라이즈해 캐시 — 재생 중 CPU 최소화.
final class SpriteAnimator {

    var onFrame: ((NSImage) -> Void)?
    /// 래스터라이즈에 사용할 appearance 공급자 (상태바 버튼의 effectiveAppearance).
    var appearanceProvider: () -> NSAppearance? = { nil }
    /// 러너 색상 테마 공급자 (설정).
    var themeProvider: () -> SpriteTheme = { .auto }

    private var timer: Timer?
    private var frames: [NSImage] = []
    private var frameIndex = 0
    private(set) var display: SpriteDisplay?
    private var rasterCache: [String: [NSImage]] = [:]

    init() {
        // 다크/라이트 테마 전환 → 래스터 캐시 무효화 후 다시 그리기
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(themeChanged),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
    }

    func set(display newDisplay: SpriteDisplay) {
        guard newDisplay != display else { return }
        display = newDisplay
        frames = rasterizedFrames(for: newDisplay)
        frameIndex = 0
        restartTimer(interval: newDisplay.frameInterval)
    }

    @objc private func themeChanged() {
        DispatchQueue.main.async { [self] in reloadFrames() }
    }

    /// 캐시를 비우고 현재 표시 상태의 프레임을 다시 만든다 (macOS 테마·러너 색상 변경 시).
    func reloadFrames() {
        rasterCache.removeAll()
        guard let current = display else { return }
        frames = rasterizedFrames(for: current)
    }

    private func rasterizedFrames(for display: SpriteDisplay) -> [NSImage] {
        let appearance = appearanceProvider()
        let theme = themeProvider()
        let cacheKey = "\(display.key)|\(theme.rawValue)|\(appearance?.name.rawValue ?? "default")"
        if let cached = rasterCache[cacheKey] { return cached }
        let rasterized = SpriteFrames.frames(for: display, theme: theme).map {
            SpriteRasterizer.rasterize($0, size: SpriteFrames.spriteSize, appearance: appearance)
        }
        rasterCache[cacheKey] = rasterized
        return rasterized
    }

    private func restartTimer(interval: TimeInterval) {
        timer?.invalidate()
        advance()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.advance()
        }
        RunLoop.main.add(timer, forMode: .common)   // 메뉴 열림 중에도 애니메이션 유지
        self.timer = timer
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        onFrame?(frames[frameIndex])
        frameIndex = (frameIndex + 1) % frames.count
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
