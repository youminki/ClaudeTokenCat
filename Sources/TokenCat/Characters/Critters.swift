import AppKit

// 골격이 저마다 다른 동물들: 개구리(점프), 거북이·달팽이(느릿), 문어·고래(헤엄).

/// 개구리: 웅크렸다가 뒷다리를 펴며 뛰어오른다.
struct Frog: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0x6CC24A), belly: NSColor(hex: 0xDDF5B8),
                                   dark: NSColor(hex: 0x3E8E2F))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let groundY = Stage.ground
        var air: CGFloat = 0, squash: CGFloat = 0, pitch: CGFloat = 0, extend: CGFloat = 0
        switch pose.activity {
        case .walk, .run:
            let height: CGFloat = pose.activity == .run ? 5.5 * pose.speed : 2.6
            if u < 0.22 {
                squash = 0.18 * sin(.pi / 2 * u / 0.22)
            } else if u < 0.78 {
                let k = (u - 0.22) / 0.56
                air = height * sin(.pi * k)
                pitch = -0.32 * cos(.pi * k)
                extend = sin(.pi * min(k * 1.6, 1))
            } else {
                squash = 0.16 * sin(.pi * (u - 0.78) / 0.22)
            }
        case .stand:
            squash = 0.03 * sin(tau * u)
        case .sit:
            squash = 0.12 + 0.03 * sin(tau * u * 2)
        case .sleep:
            squash = 0.26 + 0.03 * sin(tau * u)
        }
        let rx = 5.4 * (1 + squash * 0.6)
        let ry = 3.6 * (1 - squash)
        let center = CGPoint(16, groundY - ry - 1.0 - air)
        let body = BodyFrame(center: center, pitch: pitch)

        // 뒷다리: 웅크리면 접히고, 뛰면 뒤로 쭉 편다
        let hip = body.point(-rx * 0.45, ry * 0.4)
        for far in [true, false] {
            let shift = CGPoint(far ? 1.0 : 0, 0)
            if extend > 0.05 {
                let foot = hip + CGPoint(-4.5 * extend - 1, 2.5 + 1.5 * extend) + shift
                s.limb(hip: hip + shift, foot: foot, length: 6, width: 2.2, kneeForward: true, far: far)
                s.ellipse(foot + CGPoint(-0.8, 0.3), 1.8, 0.7, rotation: -0.3, far: far)
            } else if pose.activity != .sleep {
                s.ellipse(hip + shift + CGPoint(0.2, 0.6), 2.6, 2.1, rotation: -0.4, far: far, own: !far)
                s.ellipse(CGPoint(hip.x + shift.x + 1.6, groundY - 0.6), 2.2, 0.7, far: far)
            }
        }
        s.ellipse(center, rx, ry, rotation: pitch)
        s.ellipse(body.point(rx * 0.25, ry * 0.45), rx * 0.62, ry * 0.5, rotation: pitch, .belly)
        // 앞다리
        if pose.activity != .sleep {
            let shoulder = body.point(rx * 0.55, ry * 0.4)
            // 공중에선 앞발을 앞으로 모으고, 땅에선 짚는다
            let foot = air > 0.5
                ? shoulder + CGPoint(1.9, 1.3)
                : CGPoint(shoulder.x + 0.8, groundY - 0.5)
            s.capsule([shoulder, foot], width: 1.5, own: true)
            s.ellipse(foot + CGPoint(0.5, 0), 1.0, 0.5)
        }
        // 툭 튀어나온 눈
        for far in [true, false] {
            let at = body.point(rx * (far ? 0.12 : 0.5), -ry * 0.95)
            s.circle(at, 1.9, far: far)
            if !far { s.eye(at + CGPoint(0.3, -0.1), 1.0) }
        }
        let mouthL = body.point(rx * 0.35, ry * 0.05)
        let mouthR = body.point(rx * 0.98, -ry * 0.2)
        if pose.mouthOpen {
            s.detailEllipse((mouthL + mouthR) * 0.5 + CGPoint(0, 0.4), 1.3, 0.8, .ink)
            s.detailEllipse((mouthL + mouthR) * 0.5 + CGPoint(0, 0.8), 0.9, 0.45, .pink)
        } else {
            s.detailCurve(mouthL, control: (mouthL + mouthR) * 0.5 + CGPoint(0, 1.3), mouthR, width: 0.35, .ink)
        }
        s.detailEllipse(body.point(rx * 0.55, -ry * 0.15), 0.9, 0.5, .pink)
        for k in 0..<3 {
            s.detailEllipse(body.point(-rx * 0.35 + CGFloat(k) * 1.6, -ry * 0.55 + CGFloat(k % 2) * 0.6),
                            0.55, 0.45, .dark)
        }
    }
}

/// 거북이: 등껍질은 그대로, 짧은 네 다리로 엉금엉금.
struct Turtle: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0x8CC36B), belly: NSColor(hex: 0xF2E3B3),
                                   dark: NSColor(hex: 0x4E8A3E), extra: NSColor(hex: 0xB8DE9A))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let groundY = Stage.ground - 0.5
        let moving = pose.activity == .walk || pose.activity == .run
        let stride: CGFloat = pose.activity == .run ? 1.6 * pose.speed : (moving ? 1.0 : 0)
        let tucked = pose.activity == .sleep
        let resting = pose.activity == .sit || tucked
        let bob: CGFloat = moving ? -0.35 * abs(sin(tau * u)) : 0.1 * sin(tau * u)
        let shellBottom = groundY - (resting ? 0.8 : 2.2) + bob
        let center = CGPoint(15.2, shellBottom)
        let rx: CGFloat = 6.3, ry: CGFloat = 5.2

        // 다리
        if !tucked {
            let hips: [(CGFloat, Bool, CGFloat)] = [(-3.8, true, 0.5), (2.6, true, 0), (-4.4, false, 0), (3.4, false, 0.5)]
            for (x, far, offset) in hips {
                let hip = CGPoint(center.x + x, shellBottom - 0.6)
                let foot: CGPoint
                if resting {
                    foot = CGPoint(hip.x + (x > 0 ? 1.4 : -1.4), groundY)
                } else {
                    let step = Gait.foot(u + offset, stride: stride, lift: 0.9, duty: 0.55)
                    foot = CGPoint(hip.x + step.dx, groundY - step.lift)
                }
                s.capsule([hip, foot], width: 2.3, .extra, far: far)
                s.ellipse(foot + CGPoint(0.3, 0), 1.3, 0.6, .extra, far: far)
            }
        }
        // 꼬리와 머리
        s.polygon([center + CGPoint(-rx + 0.6, -0.8), center + CGPoint(-rx - 1.6, 0.2), center + CGPoint(-rx + 0.8, 0.2)],
                  round: 0.3, .extra)
        let neckOut: CGFloat = tucked ? 0.2 : (pose.activity == .sit ? 1.6 : 2.6 + (moving ? 0.4 * sin(tau * u * 2) : 0))
        let headDrop: CGFloat = pose.activity == .sit ? 1.6 : 0
        let head = CGPoint(center.x + rx + neckOut - 0.6, center.y - 2.4 + headDrop + (tucked ? 1.2 : 0))
        if !tucked {
            s.capsule([center + CGPoint(rx - 1.5, -1.2), head + CGPoint(-0.6, 0.5)], width: 2.4, .extra)
        }
        s.ellipse(head, 2.6, 2.3, .extra)

        // 등껍질
        let shell = CGMutablePath()
        shell.move(to: center + CGPoint(-rx, 0))
        shell.addCurve(to: center + CGPoint(0, -ry), control1: center + CGPoint(-rx, -ry * 0.7),
                       control2: center + CGPoint(-rx * 0.55, -ry))
        shell.addCurve(to: center + CGPoint(rx, 0), control1: center + CGPoint(rx * 0.55, -ry),
                       control2: center + CGPoint(rx, -ry * 0.7))
        shell.closeSubpath()
        s.shape(shell, round: 0.3)
        s.capsule([center + CGPoint(-rx + 0.4, 0.1), center + CGPoint(rx - 0.4, 0.1)], width: 1.5, .belly)
        // 등딱지 무늬
        let hex: [CGPoint] = [(-1.4, -3.6), (1.4, -3.6), (2.4, -2.0), (1.4, -0.6), (-1.4, -0.6), (-2.4, -2.0)]
            .map { center + CGPoint($0.0, $0.1) }
        s.detailLine(hex + [hex[0]], width: 0.4, .dark)
        for (a, b) in [(hex[2], CGPoint(rx - 1.0, -1.6)), (hex[5], CGPoint(-rx + 1.0, -1.6)),
                       (hex[0], CGPoint(-2.6, -ry + 0.4)), (hex[1], CGPoint(2.6, -ry + 0.4))] {
            s.detailLine([a, center + b], width: 0.4, .dark)
        }

        s.eye(head + CGPoint(0.9, -0.5), 0.75)
        s.detailEllipse(head + CGPoint(0.5, 0.9), 0.7, 0.4, .pink)
        s.detailCurve(head + CGPoint(1.2, 0.8), control: head + CGPoint(1.8, 1.2), head + CGPoint(2.4, 0.6),
                      width: 0.25, .ink)
    }
}

/// 달팽이: 배발을 늘였다 줄이며 기어가고, 눈은 더듬이 끝에 있다.
struct Snail: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0xE59A5C), belly: NSColor(hex: 0xF3DDBB),
                                   dark: NSColor(hex: 0xA35A2E))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let groundY = Stage.ground - 0.3
        let moving = pose.activity == .walk || pose.activity == .run
        let stretch: CGFloat = moving ? (pose.activity == .run ? 1.6 : 1.0) * sin(tau * u) : 0
        let hidden = pose.activity == .sleep
        let droop = pose.activity == .sit

        // 배발
        let tailX: CGFloat = 6.5 - stretch * 0.4
        let headX: CGFloat = hidden ? 18 : 25 + stretch * 0.6
        let foot = CGMutablePath()
        foot.move(to: CGPoint(tailX, groundY))
        foot.addQuadCurve(to: CGPoint(headX - 3, groundY - 2.2), control: CGPoint(tailX + 4, groundY - 2.4))
        if !hidden {
            foot.addCurve(to: CGPoint(headX, groundY - 4.8), control1: CGPoint(headX - 2, groundY - 2.2),
                          control2: CGPoint(headX - 1.6, groundY - 5))
            foot.addQuadCurve(to: CGPoint(headX + 1.4, groundY), control: CGPoint(headX + 2.4, groundY - 3.4))
        } else {
            foot.addQuadCurve(to: CGPoint(headX, groundY), control: CGPoint(headX + 0.8, groundY - 1.6))
        }
        foot.closeSubpath()
        s.shape(foot, round: 0.4, .belly)

        // 더듬이와 눈
        if !hidden {
            let top = CGPoint(headX + 0.2, groundY - 4.4)
            for far in [true, false] {
                let wiggle = 0.15 * sin(tau * u * 2 + (far ? 1 : 0))
                let angle: CGFloat = droop ? (far ? -0.35 : 0.1) : (far ? -1.85 : -1.3) + wiggle
                let tip = top + CGPoint(far ? -0.5 : 0, 0) + CGPoint.polar(angle, droop ? 3.4 : 4.2)
                s.capsule([top + CGPoint(far ? -0.5 : 0, 0), tip], width: 0.7, .belly, far: far)
                s.circle(tip, 1.05, .belly, far: far)
                if !far { s.eye(tip + CGPoint(0.15, 0), 0.62) }
            }
            s.detailEllipse(CGPoint(headX + 0.5, groundY - 2.2), 0.6, 0.35, .pink)
            s.detailCurve(CGPoint(headX + 0.4, groundY - 1.4), control: CGPoint(headX + 1, groundY - 0.9),
                          CGPoint(headX + 1.5, groundY - 1.5), width: 0.25, .ink)
        }

        // 등껍질 + 소용돌이
        let wobble: CGFloat = moving ? 0.3 * sin(tau * u + 0.8) : 0
        let shellCenter = CGPoint(hidden ? 14 : 13.6 + stretch * 0.15, groundY - 5.6 + wobble * 0.3)
        let r: CGFloat = 5.2
        s.circle(shellCenter, r)
        let spiral = CGMutablePath()
        var first = true
        var angle: CGFloat = 0
        while angle < tau * 2.3 {
            let radius = r * 0.82 * (1 - angle / (tau * 2.6))
            let p = shellCenter + CGPoint(-0.4, 0.3) + CGPoint.polar(angle + .pi + wobble, radius)
            first ? spiral.move(to: p) : spiral.addLine(to: p)
            first = false
            angle += 0.2
        }
        s.add(Part(path: spiral, fill: false, stroke: 0.7, role: .dark, layer: .detail))
    }
}

/// 문어: 머리를 흔들며 다리 다섯 개가 물결친다.
struct Octopus: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0xFF7F7F), belly: NSColor(hex: 0xFFC4C4),
                                   dark: NSColor(hex: 0xD94F5C))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let moving = pose.activity == .walk || pose.activity == .run
        let fast = pose.activity == .run
        let bob: CGFloat = moving ? -1.0 * sin(tau * u) : 0.3 * sin(tau * u)
        let lowered: CGFloat = pose.activity == .sleep ? 3.4 : (pose.activity == .sit ? 1.8 : 0)
        let lean: CGFloat = fast ? 0.32 : (moving ? 0.12 : 0)
        let pulse = 1 + (moving ? 0.06 * sin(tau * u + 0.6) : 0.02 * sin(tau * u))
        let center = CGPoint(17, 10.2 + bob + lowered)
        let rx: CGFloat = 5.0 * pulse, ry: CGFloat = 4.7 / pulse

        // 다리
        let base = CGPoint(center.x - 0.6, center.y + ry * 0.6)
        for k in 0..<5 {
            let spread = CGFloat(k) / 4 - 0.5
            var points = [base + CGPoint(spread * rx * 1.4, 0)]
            var angle: CGFloat = .pi / 2 - spread * 1.1 + (fast ? 0.9 : lean * 2)
            if pose.activity == .sleep { angle = .pi / 2 - spread * 2.6 }
            for i in 1...6 {
                let wave = (moving ? 0.5 : 0.25) * sin(tau * u * (fast ? 2 : 1) - CGFloat(i) * 0.7 + CGFloat(k))
                angle += wave * 0.35 + (pose.activity == .sleep ? -spread * 0.25 : 0)
                points.append(points[i - 1] + CGPoint.polar(angle, fast ? 1.25 : 1.05))
            }
            let near = k % 2 == 0
            s.tapered(points.map { CGPoint($0.x, min($0.y, Stage.ground - 0.4)) }, from: 2.0, to: 0.6, far: !near)
            if near {
                for i in [2, 4] where i < points.count {
                    s.detailEllipse(points[i] + CGPoint(0, 0.3), 0.32, 0.32, .belly)
                }
            }
        }
        s.ellipse(center, rx, ry, rotation: lean)
        let face = BodyFrame(center: center, pitch: lean)
        s.detailEllipse(face.point(-rx * 0.45, -ry * 0.45), 0.8, 0.6, .belly)
        s.detailEllipse(face.point(-rx * 0.15, -ry * 0.7), 0.5, 0.4, .belly)
        s.eye(face.point(rx * 0.15, ry * 0.05), 0.95)
        s.eye(face.point(rx * 0.62, ry * 0.0), 0.85)
        s.detailEllipse(face.point(rx * 0.35, ry * 0.4), 0.7, 0.45, .ink)
        s.detailEllipse(face.point(-rx * 0.1, ry * 0.45), 0.9, 0.5, .pink)
    }
}

/// 고래: 꼬리를 위아래로 치며 헤엄치고 가끔 물을 뿜는다.
struct Whale: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0x4F93DE), belly: NSColor(hex: 0xD3E8FF),
                                   dark: NSColor(hex: 0x2F6DB5), extra: NSColor(hex: 0x8ED8FF))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let moving = pose.activity == .walk || pose.activity == .run
        let fast = pose.activity == .run
        let flapRate: CGFloat = fast ? 1 : (moving ? 1 : 0.5)
        let flap = sin(tau * u * flapRate)
        let bob: CGFloat = moving ? 0.9 * sin(tau * u * flapRate + 1.2) : 0.4 * sin(tau * u)
        let sink: CGFloat = pose.activity == .sleep ? 3.6 : (pose.activity == .sit ? 2.2 : 0)
        let center = CGPoint(19.5, 12.4 + bob + sink)
        let pitch: CGFloat = (moving ? -0.08 * flap : 0) + (pose.activity == .sit ? 0.12 : 0)
        let body = BodyFrame(center: center, pitch: pitch)
        let rx: CGFloat = 8.4, ry: CGFloat = 5.0

        // 꼬리자루와 꼬리지느러미
        let tailBase = body.point(-rx * 0.7, -0.2)
        var tail = [tailBase]
        var angle: CGFloat = .pi + 0.15
        for i in 1...5 {
            angle += -0.12 * flap * CGFloat(i) * 0.4
            tail.append(tail[i - 1] + CGPoint.polar(angle, 1.25))
        }
        s.tapered(tail, from: 4.6, to: 1.6)
        if let tip = tail.last {
            let rot = angle - .pi - 0.6 * flap
            let up = tip + CGPoint(-1.2, -2.6).rotated(rot)
            let down = tip + CGPoint(-1.2, 2.6).rotated(rot)
            let notch = tip + CGPoint(-0.6, 0).rotated(rot)
            s.polygon([tip + CGPoint(0.6, -0.5).rotated(rot), up, notch, down, tip + CGPoint(0.6, 0.5).rotated(rot)],
                      round: 0.6)
        }

        s.ellipse(center, rx, ry, rotation: pitch)
        s.ellipse(body.point(rx * 0.15, ry * 0.5), rx * 0.78, ry * 0.5, rotation: pitch, .belly)
        for k in 0..<3 {
            let x = rx * (-0.1 + CGFloat(k) * 0.22)
            s.detailLine([body.point(x, ry * 0.42), body.point(x + 1.2, ry * 0.78)], width: 0.35, .dark)
        }
        // 가슴지느러미
        let fin = body.point(rx * 0.15, ry * 0.55)
        let finRot: CGFloat = 0.5 + 0.35 * sin(tau * u * flapRate + 0.5)
        s.ellipse(fin + CGPoint(-1.0, 1.0).rotated(finRot), 2.0, 0.95, rotation: finRot + pitch, own: true)

        // 물 뿜기 (움직이는 동안 한 주기의 앞쪽)
        let spoutT = u * (fast ? 2 : 1)
        let spoutPhase = spoutT - floor(spoutT)
        if pose.activity != .sleep && spoutPhase < 0.55 {
            let k = spoutPhase / 0.55
            let hole = body.point(rx * 0.32, -ry * 0.98)
            let height = 4.6 * sin(.pi * min(k * 1.3, 1))
            s.capsule([hole, hole + CGPoint(0.2, -height)], width: 0.9, .extra)
            for side in [-1.0, 1.0] as [CGFloat] {
                let drop = hole + CGPoint(side * (0.6 + k * 2.2), -height + k * k * 3.5)
                s.circle(drop, 0.65 * (1 - k * 0.4), .extra)
            }
        }

        s.eye(body.point(rx * 0.6, ry * 0.05), 0.9)
        s.detailEllipse(body.point(rx * 0.55, ry * 0.42), 0.9, 0.5, .pink)
        s.detailCurve(body.point(rx * 0.72, ry * 0.28), control: body.point(rx * 0.85, ry * 0.45),
                      body.point(rx * 0.96, ry * 0.18), width: 0.3, .ink)
    }
}
