import Foundation
import Testing
@testable import UsageCore

struct BurnRateMeterTests {

    @Test func eMASmoothing() {
        let meter = BurnRateMeter(alpha: 0.3)
        #expect(abs((meter.update(tokensInLastMinute: 1000)) - (300)) <= 0.001)
        #expect(abs((meter.update(tokensInLastMinute: 1000)) - (510)) <= 0.001)
        #expect(abs((meter.update(tokensInLastMinute: 0)) - (357)) <= 0.001)
    }

    @Test func stateMachineThresholds() {
        let t = Thresholds()
        #expect(t.state(burnRate: 0, idleSeconds: 301) == .sleeping)
        #expect(t.state(burnRate: 0, idleSeconds: 10) == .walking)
        #expect(t.state(burnRate: 500, idleSeconds: 10) == .walking)
        #expect(t.state(burnRate: 5_000, idleSeconds: 10) == .running)
        #expect(t.state(burnRate: 15_000, idleSeconds: 10) == .dashing)
        #expect(t.state(burnRate: 50_000, idleSeconds: 10) == .rainbow)
    }

    @Test func sensitivityPresets() {
        let high = Thresholds.preset(sensitivity: .high)
        #expect(high.state(burnRate: 1_500, idleSeconds: 0) == .running) // run 경계 1000으로 하향
        let low = Thresholds.preset(sensitivity: .low)
        #expect(low.state(burnRate: 3_000, idleSeconds: 0) == .walking) // run 경계 4000으로 상향
    }
}
