import AppKit

/// 러너 주변 효과. 설계 좌표(36×22)에 그리며 메뉴바 프레임과 팝오버 무대가 함께 쓴다.
/// `phase`는 0~1 주기라 프레임을 몇 장으로 나누든 끊김 없이 이어진다.
enum SpriteEffects {

    static let rainbow: [NSColor] = [
        NSColor(hex: 0xFF4D4D), NSColor(hex: 0xFF9E3D), NSColor(hex: 0xFFE14D),
        NSColor(hex: 0x5BD86B), NSColor(hex: 0x4DA3FF), NSColor(hex: 0xA77BFF),
    ]

    /// 무지개 꼬리. 띠마다 물결이 조금씩 늦게 따라온다.
    static func rainbowTrail(_ cg: CGContext, from x0: CGFloat, to x1: CGFloat, centerY: CGFloat,
                             band: CGFloat, phase: CGFloat, alpha: CGFloat = 1) {
        guard x1 > x0 else { return }
        let top = centerY - band * 3
        let step: CGFloat = 0.5
        for (i, color) in rainbow.enumerated() {
            let path = CGMutablePath()
            var x = x1
            var first = true
            while x >= x0 {
                let distance = x1 - x
                let wave = sin(tau * phase * 2 - distance * 0.55) * band * 0.45 * min(distance / 4, 1)
                let y = top + CGFloat(i) * band + wave
                first ? path.move(to: CGPoint(x, y)) : path.addLine(to: CGPoint(x, y))
                first = false
                x -= step
            }
            var back: [CGPoint] = []
            x = x0
            while x <= x1 {
                let distance = x1 - x
                let wave = sin(tau * phase * 2 - distance * 0.55) * band * 0.45 * min(distance / 4, 1)
                back.append(CGPoint(x, top + CGFloat(i + 1) * band + wave))
                x += step
            }
            back.forEach { path.addLine(to: $0) }
            path.closeSubpath()
            // 뒤로 갈수록 옅어진다
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            let faded = color.withAlphaComponent(0)
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                         colors: [faded.cgColor, color.withAlphaComponent(alpha).cgColor] as CFArray,
                                         locations: [0, 0.6]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x0, 0), end: CGPoint(x1, 0), options: [])
            }
            cg.restoreGState()
        }
    }

    /// 네 갈래 반짝이.
    static func sparkle(_ cg: CGContext, at c: CGPoint, radius r: CGFloat, color: NSColor) {
        guard r > 0.05 else { return }
        let path = CGMutablePath()
        let inner = r * 0.28
        for k in 0..<8 {
            let angle = CGFloat(k) * .pi / 4 - .pi / 2
            let p = c + CGPoint.polar(angle, k % 2 == 0 ? r : inner)
            k == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    /// 뒤로 흘러가는 반짝이들.
    static func sparkleField(_ cg: CGContext, phase: CGFloat, width: CGFloat, height: CGFloat, color: NSColor? = nil) {
        let seeds: [(x: CGFloat, y: CGFloat, size: CGFloat, speed: CGFloat)] = [
            (0.15, 0.18, 1.3, 1), (0.55, 0.08, 1.0, 2), (0.85, 0.32, 0.9, 1),
            (0.35, 0.86, 1.1, 2), (0.7, 0.92, 0.8, 1),
        ]
        for (i, seed) in seeds.enumerated() {
            let t = (phase * seed.speed + seed.x).truncatingRemainder(dividingBy: 1)
            let x = width * (1 - t) - 2
            let twinkle = 0.5 + 0.5 * sin(tau * (phase * 2 * seed.speed) + CGFloat(i))
            let tint = color ?? rainbow[(i * 2) % rainbow.count].tinted(by: 0.35)
            sparkle(cg, at: CGPoint(x, height * seed.y), radius: seed.size * (0.6 + 0.5 * twinkle), color: tint)
        }
    }

    /// 질주할 때 뒤로 스치는 바람 줄.
    static func speedLines(_ cg: CGContext, phase: CGFloat, maxX: CGFloat, color: NSColor) {
        let lines: [(y: CGFloat, length: CGFloat, offset: CGFloat)] = [(6.5, 7, 0), (11.5, 9, 0.4), (16, 6, 0.7)]
        cg.setLineCap(.round)
        for line in lines {
            let t = (phase + line.offset).truncatingRemainder(dividingBy: 1)
            let head = maxX - t * (maxX + line.length)
            let alpha = sin(.pi * t)
            cg.setStrokeColor(color.withAlphaComponent(0.55 * alpha).cgColor)
            cg.setLineWidth(0.8)
            cg.move(to: CGPoint(head, line.y))
            cg.addLine(to: CGPoint(head + line.length, line.y))
            cg.strokePath()
        }
    }

    /// 발밑 먼지.
    static func dust(_ cg: CGContext, at origin: CGPoint, phase: CGFloat, color: NSColor) {
        for k in 0..<3 {
            let t = (phase + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
            let c = origin + CGPoint(-t * 7, -t * 2.4)
            let r = 0.5 + t * 1.3
            cg.setFillColor(color.withAlphaComponent(0.42 * (1 - t)).cgColor)
            cg.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        }
    }

    /// 머리 위로 떠오르는 Z.
    static func zzz(_ cg: CGContext, from origin: CGPoint, phase: CGFloat, color: NSColor) {
        cg.setLineCap(.round)
        cg.setLineJoin(.round)
        for k in 0..<3 {
            let t = (phase + CGFloat(k) / 3).truncatingRemainder(dividingBy: 1)
            let size = 1.4 + t * 1.9
            let c = origin + CGPoint(t * 4.2 + sin(t * tau) * 0.6, -t * 8.5)
            let alpha = sin(.pi * min(t * 1.15, 1))
            cg.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
            cg.setLineWidth(0.55 + t * 0.3)
            cg.move(to: c + CGPoint(-size / 2, -size / 2))
            cg.addLine(to: c + CGPoint(size / 2, -size / 2))
            cg.addLine(to: c + CGPoint(-size / 2, size / 2))
            cg.addLine(to: c + CGPoint(size / 2, size / 2))
            cg.strokePath()
        }
    }

    /// 이마에서 흘러내리는 땀방울.
    static func sweat(_ cg: CGContext, at origin: CGPoint, phase: CGFloat) {
        for k in 0..<2 {
            let t = (phase + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
            let c = origin + CGPoint(CGFloat(k) * 1.6 + t * 0.8, t * 5)
            let alpha = t < 0.15 ? t / 0.15 : (1 - t) / 0.85
            drop(cg, at: c, size: 1.25, color: NSColor(hex: 0x5AC8FA).withAlphaComponent(alpha))
        }
    }

    static func drop(_ cg: CGContext, at c: CGPoint, size: CGFloat, color: NSColor) {
        let path = CGMutablePath()
        path.move(to: c + CGPoint(0, -size * 1.3))
        path.addQuadCurve(to: c + CGPoint(size * 0.75, size * 0.2), control: c + CGPoint(size * 0.7, -size * 0.4))
        path.addArc(center: c + CGPoint(0, size * 0.2), radius: size * 0.75, startAngle: 0, endAngle: .pi,
                    clockwise: false)
        path.addQuadCurve(to: c + CGPoint(0, -size * 1.3), control: c + CGPoint(-size * 0.7, -size * 0.4))
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    /// 느낌표.
    static func exclaim(_ cg: CGContext, at c: CGPoint, height h: CGFloat, color: NSColor) {
        cg.setFillColor(color.cgColor)
        let w = h * 0.3
        let bar = CGPath(roundedRect: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h * 0.62),
                         cornerWidth: w / 2, cornerHeight: w / 2, transform: nil)
        cg.addPath(bar)
        cg.fillPath()
        cg.fillEllipse(in: CGRect(x: c.x - w * 0.55, y: c.y + h * 0.27, width: w * 1.1, height: w * 1.1))
    }

    static func heart(_ cg: CGContext, at c: CGPoint, size s: CGFloat, color: NSColor) {
        let path = CGMutablePath()
        path.move(to: c + CGPoint(0, s * 0.9))
        path.addCurve(to: c + CGPoint(-s, -s * 0.15), control1: c + CGPoint(-s * 0.5, s * 0.55),
                      control2: c + CGPoint(-s, s * 0.25))
        path.addArc(center: c + CGPoint(-s * 0.5, -s * 0.2), radius: s * 0.5, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addArc(center: c + CGPoint(s * 0.5, -s * 0.2), radius: s * 0.5, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addCurve(to: c + CGPoint(0, s * 0.9), control1: c + CGPoint(s, s * 0.25),
                      control2: c + CGPoint(s * 0.5, s * 0.55))
        cg.setFillColor(color.cgColor)
        cg.addPath(path)
        cg.fillPath()
    }

    /// 8분음표.
    static func note(_ cg: CGContext, at c: CGPoint, size s: CGFloat, color: NSColor) {
        cg.setFillColor(color.cgColor)
        cg.setStrokeColor(color.cgColor)
        cg.fillEllipse(in: CGRect(x: c.x - s * 0.55, y: c.y + s * 0.35, width: s * 0.75, height: s * 0.55))
        cg.setLineWidth(s * 0.16)
        cg.move(to: c + CGPoint(s * 0.13, s * 0.6))
        cg.addLine(to: c + CGPoint(s * 0.13, -s * 0.8))
        cg.addQuadCurve(to: c + CGPoint(s * 0.6, -s * 0.1), control: c + CGPoint(s * 0.65, -s * 0.55))
        cg.strokePath()
    }
}
