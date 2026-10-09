import AppKit
import GameCore

/// 능력·꾸미기·파티클 같은 화면 효과.
extension GameSession {
    static func fillHeart(_ cg: CGContext, at c: CGPoint, size s: CGFloat, color: NSColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(c.x, c.y + s * 0.35))
        path.addCurve(to: CGPoint(c.x - s * 0.5, c.y - s * 0.1), control1: CGPoint(c.x - s * 0.1, c.y + s * 0.1),
                      control2: CGPoint(c.x - s * 0.5, c.y + s * 0.15))
        path.addArc(center: CGPoint(c.x - s * 0.25, c.y - s * 0.12), radius: s * 0.25, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addArc(center: CGPoint(c.x + s * 0.25, c.y - s * 0.12), radius: s * 0.25, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addCurve(to: CGPoint(c.x, c.y + s * 0.35), control1: CGPoint(c.x + s * 0.5, c.y + s * 0.15),
                      control2: CGPoint(c.x + s * 0.1, c.y + s * 0.1))
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    // MARK: 능력

    /// 보호막 방울과 글라이드 날개. 내 러너에만.
    func drawAbilities(_ cg: CGContext, groundY: CGFloat, time: Double) {
        guard game.phase == .playing, entrance >= 1 else { return }
        let center = CGPoint(runnerLeft + CGFloat(Self.runnerWidth) / 2, groundY - CGFloat(game.runnerY + Self.runnerHeight / 2))
        cg.saveGState()
        if game.shieldsLeft > 0 {
            let pulse = 1 + 0.04 * CGFloat(sin(time * 5))
            for k in 0..<game.shieldsLeft {
                let r = (27 + CGFloat(k) * 4) * pulse
                let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                cg.setFillColor(NSColor(hex: 0x8FD3FF).withAlphaComponent(k == 0 ? 0.08 : 0).cgColor)
                cg.fillEllipse(in: rect)
                cg.setStrokeColor(NSColor(hex: 0x8FD3FF).withAlphaComponent(0.55 - CGFloat(k) * 0.15).cgColor)
                cg.setLineWidth(1.2)
                cg.strokeEllipse(in: rect)
            }
        }
        if game.isGliding {
            // 머리 위 낙하산
            let top = CGPoint(center.x - 2, center.y - 40)
            let canopy = CGMutablePath()
            canopy.addArc(center: CGPoint(top.x, top.y + 6), radius: 17, startAngle: .pi * 1.08, endAngle: .pi * 1.92,
                          clockwise: false)
            canopy.closeSubpath()
            cg.setFillColor(NSColor(hex: 0xFF8FB8).withAlphaComponent(0.9).cgColor)
            cg.addPath(canopy)
            cg.fillPath()
            cg.setStrokeColor(NSColor.white.withAlphaComponent(0.7).cgColor)
            cg.setLineWidth(0.8)
            for dx in [-14.0, 0, 14] {
                cg.move(to: CGPoint(top.x + CGFloat(dx), top.y + 1))
                cg.addLine(to: CGPoint(center.x - 2, center.y - 14))
            }
            cg.strokePath()
        }
        cg.restoreGState()
    }

    // MARK: 꾸미기

    var dustColors: [NSColor] {
        switch GameWallet.shared.equipped(.dust) {
        case .rainbowDust: SpriteEffects.rainbow
        case let dust?: [dust.color]
        case nil: [NSColor(white: 0.85, alpha: 1)]
        }
    }

    /// 부딪힌 순간. 기본은 흰 별, 상점 효과를 달면 그 모양으로 터진다.
    func crashBurst(at center: CGPoint) {
        switch GameWallet.shared.equipped(.crash) {
        case .fireworksCrash:
            for (k, dx) in [-18.0, 0, 20].enumerated() {
                let point = CGPoint(center.x + CGFloat(dx), center.y + 18 + CGFloat(k % 2) * 10)
                burst(at: point, count: 14, colors: SpriteEffects.rainbow.shuffled(), shape: .spark, speed: 110,
                      life: 0.9, drift: 0, spread: 2)
            }
        case .heartCrash:
            burst(at: center, count: 12, colors: [NSColor(hex: 0xFF8FB8), NSColor(hex: 0xFF5C8A)], shape: .heart,
                  speed: 120, life: 0.9, drift: 0, spread: 2, size: 2.2...3.4)
        case .coinCrash:
            burst(at: center, count: 16, colors: [.white], shape: .coin, speed: 170, life: 1.1, drift: 0.3,
                  size: 1.6...2.4)
        default:
            burst(at: center, count: 12, color: .white, speed: 120, life: 0.55, drift: 0)
        }
    }

    func updateTrail(_ k: CGFloat) {
        guard game.phase == .playing, GameWallet.shared.equipped(.trail) != nil else {
            if !trail.isEmpty { trail.removeFirst() }
            return
        }
        let shift = CGFloat(game.speed) * k
        for i in trail.indices { trail[i].x -= shift }
        let height = Self.runnerHeight * (game.isDucking ? 0.3 : 0.45)
        trail.append(CGPoint(runnerLeft + 2, CGFloat(game.runnerY + height)))
        if trail.count > 22 { trail.removeFirst(trail.count - 22) }
    }

    func drawTrail(_ cg: CGContext, groundY: CGFloat, time: Double) {
        guard let item = GameWallet.shared.equipped(.trail), trail.count > 1 else { return }
        let points = trail.map { CGPoint($0.x, groundY - $0.y) }
        cg.saveGState()
        cg.setLineCap(.round)
        switch item {
        case .rainbowTrail:
            for (band, color) in SpriteEffects.rainbow.enumerated() {
                let dy = (CGFloat(band) - 2.5) * 2.2
                for i in 1..<points.count {
                    let t = CGFloat(i) / CGFloat(points.count)
                    cg.setStrokeColor(color.withAlphaComponent(0.85 * t).cgColor)
                    cg.setLineWidth(2.4)
                    cg.move(to: CGPoint(points[i - 1].x, points[i - 1].y + dy))
                    cg.addLine(to: CGPoint(points[i].x, points[i].y + dy))
                    cg.strokePath()
                }
            }
        case .cometTrail:
            for i in 1..<points.count {
                let t = CGFloat(i) / CGFloat(points.count)
                cg.setStrokeColor(item.color.withAlphaComponent(0.7 * t).cgColor)
                cg.setLineWidth(1 + 7 * t)
                cg.move(to: points[i - 1])
                cg.addLine(to: points[i])
                cg.strokePath()
            }
        case .fireTrail:
            // 꼬리 쪽으로 갈수록 노랗고 작아지며 흔들린다
            for (i, point) in points.enumerated() {
                let t = CGFloat(i) / CGFloat(points.count)
                let flicker = CGFloat(sin(time * 23 + Double(i) * 1.7)) * 1.2
                let r = 1 + 4 * t
                let color = NSColor(hex: 0xFFE14D).blended(withFraction: t, of: NSColor(hex: 0xFF5A1F)) ?? item.color
                cg.setFillColor(color.withAlphaComponent(0.25 + 0.6 * t).cgColor)
                cg.fillEllipse(in: CGRect(x: point.x - r, y: point.y - r + flicker, width: r * 2, height: r * 2))
            }
        case .noteTrail, .heartTrail:
            for (i, point) in points.enumerated() where i % 5 == 1 {
                let t = CGFloat(i) / CGFloat(points.count)
                let bob = CGFloat(sin(time * 6 + Double(i))) * 3
                let p = CGPoint(point.x, point.y - 6 + bob)
                let color = item.color.withAlphaComponent(0.3 + 0.7 * t)
                if item == .heartTrail {
                    Self.fillHeart(cg, at: p, size: 4 + 3 * t, color: color)
                } else {
                    // 음표: 기운 머리와 기둥
                    let s = 0.8 + 0.5 * t
                    cg.setFillColor(color.cgColor)
                    cg.fillEllipse(in: CGRect(x: p.x - 2.4 * s, y: p.y + 1.5 * s, width: 3.6 * s, height: 2.6 * s))
                    cg.setStrokeColor(color.cgColor)
                    cg.setLineWidth(1.1 * s)
                    cg.move(to: CGPoint(p.x + 1.1 * s, p.y + 2.6 * s))
                    cg.addLine(to: CGPoint(p.x + 1.1 * s, p.y - 4 * s))
                    cg.addLine(to: CGPoint(p.x + 3.2 * s, p.y - 2.6 * s))
                    cg.strokePath()
                }
            }
        default:
            for (i, point) in points.enumerated() where i % 3 == 0 {
                let t = CGFloat(i) / CGFloat(points.count)
                let twinkle = 0.7 + 0.3 * CGFloat(sin(time * 9 + Double(i)))
                SpriteEffects.sparkle(cg, at: point, radius: (1.5 + 3 * t) * twinkle, color: item.color.withAlphaComponent(t))
            }
        }
        cg.restoreGState()
    }

    // MARK: 화면 효과

    /// 바닥 위 높이(y 위로)로 잰 점 주변에 작은 점을 흩뿌린다.
    func burst(at point: CGPoint, count: Int, color: NSColor, speed: CGFloat, life: CGFloat, drift: CGFloat) {
        burst(at: point, count: count, colors: [color], speed: speed, life: life, drift: drift)
    }

    /// `spread`가 1이면 위쪽 반원, 2면 사방으로 흩어진다.
    func burst(at point: CGPoint, count: Int, colors: [NSColor], shape: Particle.Shape = .dot, speed: CGFloat,
                       life: CGFloat, drift: CGFloat, spread: CGFloat = 1, size: ClosedRange<CGFloat> = 1.4...2.6) {
        for i in 0..<count {
            let angle = CGFloat(i) / CGFloat(count) * .pi * spread + .pi * 0.05 + CGFloat.random(in: -0.2...0.2)
            let v = speed * CGFloat.random(in: 0.6...1.1)
            particles.append(Particle(position: point, velocity: CGPoint(-cos(angle) * v, sin(angle) * v),
                                      gravity: -220, life: life * CGFloat.random(in: 0.7...1), total: life,
                                      color: colors[i % colors.count], size: CGFloat.random(in: size), drift: drift,
                                      shape: shape))
        }
    }

    struct Particle {
        var position: CGPoint   // x는 화면, y는 바닥 위 높이
        var velocity: CGPoint
        var gravity: CGFloat
        var life: CGFloat
        let total: CGFloat
        let color: NSColor
        let size: CGFloat
        /// 땅을 따라 뒤로 흘러가는 정도 (먼지 1, 터지는 별 0).
        let drift: CGFloat
        var shape: Shape = .dot

        enum Shape { case dot, heart, coin, spark }
    }

    struct Popup {
        let text: String
        var position: CGPoint
        var life: CGFloat
    }
}
