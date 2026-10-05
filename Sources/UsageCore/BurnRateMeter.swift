import Foundation

/// burn rate = 최근 60초 토큰 소모량(tokens/min), EMA(α=0.3)로 스무딩.
public final class BurnRateMeter {
    public let alpha: Double
    public private(set) var smoothedRate: Double = 0

    public init(alpha: Double = 0.3) {
        self.alpha = alpha
    }

    /// 폴링 틱마다 호출. 최근 60초 토큰 수를 넣으면 스무딩된 tokens/min을 반환.
    @discardableResult
    public func update(tokensInLastMinute: Int) -> Double {
        let raw = Double(tokensInLastMinute)
        smoothedRate = alpha * raw + (1 - alpha) * smoothedRate
        return smoothedRate
    }

    public func reset() {
        smoothedRate = 0
    }
}
