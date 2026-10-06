import AppKit

// 판타지 러너. 특정 작품의 캐릭터를 베끼지 않고 장르의 전형(유령, 슬라임, 로봇, UFO, 닌자)만 따서 그렸다.

/// 유령: 둥실 떠서 치맛단이 물결친다. 잘 때는 수면 모자를 쓴다.
struct Ghost: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0xF4F5FF), belly: NSColor(hex: 0xFFFFFF),
                                   dark: NSColor(hex: 0xC9CCF2), extra: NSColor(hex: 0x7B83EB))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let moving = pose.activity == .walk || pose.activity == .run
        let fast = pose.activity == .run
        let float: CGFloat = 1.1 * sin(tau * u)
        let sink: CGFloat = pose.activity == .sleep ? 2.6 : (pose.activity == .sit ? 1.6 : 0)
        let lean: CGFloat = fast ? 0.22 : (moving ? 0.1 : 0)
        let top = CGPoint(17, 3.2 + float + sink)
        let width: CGFloat = 9.6, height: CGFloat = pose.activity == .sleep ? 11 : 13.4
        let bottom = top.y + height
        let trail: CGFloat = fast ? 4.5 : (moving ? 2.2 : 0.6)

        let path = CGMutablePath()
        let left = top.x - width / 2, right = top.x + width / 2
        path.move(to: CGPoint(left, top.y + width / 2))
        path.addArc(center: CGPoint(top.x, top.y + width / 2), radius: width / 2, startAngle: .pi, endAngle: 0,
                    clockwise: false)
        path.addLine(to: CGPoint(right, bottom - 1.6))
        // 치맛단: 물결이 뒤로 흘러가고, 달릴수록 뒤로 길게 끌린다
        let bumps = 4
        for i in 0...bumps * 4 {
            let t = CGFloat(i) / CGFloat(bumps * 4)
            let x = right - t * (width + trail)
            let wave = 1.1 * sin(t * CGFloat(bumps) * tau + tau * u * 2)
            path.addLine(to: CGPoint(x, bottom - 1.2 + wave - t * trail * 0.25))
        }
        path.addQuadCurve(to: CGPoint(left, top.y + width / 2), control: CGPoint(left - trail * 0.3, bottom - 3))
        path.closeSubpath()
        var tilt = CGAffineTransform(translationX: top.x, y: bottom).rotated(by: lean).translatedBy(x: -top.x, y: -bottom)
        let leaned = path.copy(using: &tilt) ?? path
        let frame = BodyFrame(center: CGPoint(top.x, bottom), pitch: lean)

        // 작은 팔
        let wave = moving ? 0.5 * sin(tau * u * 2) : 0.25 * sin(tau * u)
        s.ellipse(frame.point(-width * 0.5, -height * 0.42), 1.1, 1.8, rotation: lean - 0.7 + wave, far: true)
        s.shape(leaned, round: 0.2)
        s.ellipse(frame.point(width * 0.5, -height * 0.45), 1.1, 1.8, rotation: lean + 0.7 - wave, own: true)

        let face = frame.point(width * 0.12, -height * 0.66)
        s.eye(face + CGPoint(-1.4, 0), 1.0)
        s.eye(face + CGPoint(1.6, 0), 1.0)
        if pose.mouthOpen || pose.activity == .stand {
            s.detailEllipse(face + CGPoint(0.2, 2.0), 0.8, pose.mouthOpen ? 0.9 : 0.55, .ink)
        } else {
            s.detailCurve(face + CGPoint(-0.6, 1.8), control: face + CGPoint(0.2, 2.6), face + CGPoint(1.0, 1.8),
                          width: 0.3, .ink)
        }
        s.detailEllipse(face + CGPoint(-2.6, 1.4), 0.9, 0.5, .pink)
        s.detailEllipse(face + CGPoint(3.0, 1.4), 0.9, 0.5, .pink)

        if pose.activity == .sleep {
            // 수면 모자
            let capBase = frame.point(-0.5, -height + 0.6)
            let tip = capBase + CGPoint(-5.2, 2.6)
            s.polygon([capBase + CGPoint(-4.2, 1.2), capBase + CGPoint(3.6, -0.4), tip], round: 0.4, .extra)
            s.circle(tip, 1.1, .belly)
            s.capsule([capBase + CGPoint(-4.4, 1.6), capBase + CGPoint(3.8, 0)], width: 1.4, .belly)
        }
    }
}

/// 슬라임: 찌그러졌다 늘어나며 통통 튄다.
struct Slime: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0x5CC8F5), belly: NSColor(hex: 0xBFEFFF),
                                   dark: NSColor(hex: 0x2E8FC9))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        var air: CGFloat = 0, squash: CGFloat = 0
        switch pose.activity {
        case .walk, .run:
            let height: CGFloat = pose.activity == .run ? 5.2 * pose.speed : 2.4
            if u < 0.25 {
                squash = 0.28 * sin(.pi * u / 0.25)
            } else if u < 0.8 {
                let k = (u - 0.25) / 0.55
                air = height * sin(.pi * k)
                squash = -0.18 * sin(.pi * min(k * 2, 1)) * (k < 0.5 ? 1 : 0.5)
            } else {
                squash = 0.32 * sin(.pi * (u - 0.8) / 0.2)
            }
        case .stand: squash = 0.06 * sin(tau * u)
        case .sit: squash = 0.32 + 0.05 * sin(tau * u * 2)
        case .sleep: squash = 0.45 + 0.04 * sin(tau * u)
        }
        let w: CGFloat = 11.5 * (1 + squash * 0.7)
        let h: CGFloat = 10.5 * (1 - squash)
        let base = CGPoint(16.5, Stage.ground - 0.4 - air)
        let lean: CGFloat = pose.activity == .run ? 0.12 : 0

        let path = CGMutablePath()
        let l = base.x - w / 2, r = base.x + w / 2
        path.move(to: CGPoint(l + 1.2, base.y))
        path.addCurve(to: CGPoint(base.x - 0.6, base.y - h), control1: CGPoint(l - 1.2, base.y - h * 0.15),
                      control2: CGPoint(l + w * 0.12, base.y - h * 0.85))
        // 꼭지
        path.addQuadCurve(to: CGPoint(base.x + 0.4, base.y - h - 1.6 + squash * 1.2),
                          control: CGPoint(base.x - 0.2, base.y - h - 0.6))
        path.addQuadCurve(to: CGPoint(base.x + 1.2, base.y - h + 0.3), control: CGPoint(base.x + 0.4, base.y - h - 0.2))
        path.addCurve(to: CGPoint(r - 1.2, base.y), control1: CGPoint(r - w * 0.12, base.y - h * 0.85),
                      control2: CGPoint(r + 1.2, base.y - h * 0.15))
        path.closeSubpath()
        var tilt = CGAffineTransform(translationX: base.x, y: base.y).rotated(by: lean).translatedBy(x: -base.x, y: -base.y)
        s.shape(path.copy(using: &tilt) ?? path, round: 0.3)

        let frame = BodyFrame(center: base, pitch: lean)
        s.detailEllipse(frame.point(-w * 0.22, -h * 0.68), 1.3, 0.8, rotation: -0.6, .white)
        s.detailEllipse(frame.point(-w * 0.32, -h * 0.45), 0.45, 0.45, .white)
        let eyeY = -h * 0.45
        s.eye(frame.point(w * 0.08, eyeY), 1.0)
        s.eye(frame.point(w * 0.3, eyeY), 1.0)
        let mouth = frame.point(w * 0.19, eyeY + 2.0)
        if pose.mouthOpen {
            s.detailEllipse(mouth + CGPoint(0, 0.3), 0.8, 0.7, .ink)
        } else {
            s.detailCurve(mouth + CGPoint(-0.8, 0), control: mouth + CGPoint(0, 1.0), mouth + CGPoint(0.8, 0),
                          width: 0.3, .ink)
        }
        s.detailEllipse(frame.point(-w * 0.05, eyeY + 1.6), 0.8, 0.45, .pink)
        s.detailEllipse(frame.point(w * 0.43, eyeY + 1.6), 0.8, 0.45, .pink)
    }
}

/// 로봇: 무한궤도로 굴러가고 안테나 불빛이 깜빡인다.
struct Robot: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0xC3CCD8), belly: NSColor(hex: 0xEEF2F7),
                                   dark: NSColor(hex: 0x4A5563), accent: NSColor(hex: 0xFF5A5F),
                                   horn: NSColor(hex: 0x5BE0FF))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let moving = pose.activity == .walk || pose.activity == .run
        let fast = pose.activity == .run
        let rumble: CGFloat = moving ? 0.18 * sin(tau * u * 4) : 0
        let slump: CGFloat = pose.activity == .sleep ? 0.35 : (pose.activity == .sit ? 0.18 : 0)
        let lean: CGFloat = fast ? 0.12 : 0
        let groundY = Stage.ground

        // 무한궤도
        let tread = CGRect(x: 9, y: groundY - 4.0, width: 14, height: 4.0)
        s.shape(CGPath(roundedRect: tread, cornerWidth: 2, cornerHeight: 2, transform: nil), round: 0.1, .dark)
        let roll = u * (fast ? 2 : 1) * (moving ? 1 : 0)
        for k in 0..<3 {
            let c = CGPoint(tread.minX + 2.2 + CGFloat(k) * 4.8, tread.midY)
            s.detailEllipse(c, 1.35, 1.35, .body)
            let a = -tau * roll * 2 + CGFloat(k)
            s.detailLine([c + CGPoint.polar(a, 1.1), c - CGPoint.polar(a, 1.1)], width: 0.35, .dark)
        }
        for k in 0..<7 {
            let x = tread.minX + 1 + (CGFloat(k) * 2.1 - roll * 2.1 * 3).truncatingRemainder(dividingBy: 14.7)
            let xx = x < tread.minX + 0.6 ? x + 14.7 : x
            if xx < tread.maxX - 0.8 {
                s.detailLine([CGPoint(xx, tread.minY + 0.2), CGPoint(xx + 0.8, tread.minY + 0.2)], width: 0.4, .belly)
            }
        }

        let frame = BodyFrame(center: CGPoint(16, groundY - 4.2 + rumble), pitch: lean)
        // 팔 (먼 쪽)
        let swing = moving ? 0.6 * sin(tau * u * 2) : 0.1 * sin(tau * u)
        let shoulder = frame.point(-1.0, -4.6)
        s.capsule([shoulder, shoulder + CGPoint.polar(1.9 + swing, 3.4)], width: 1.3, .dark, far: true)
        // 몸통
        var bodyT = CGAffineTransform(translationX: frame.center.x, y: frame.center.y).rotated(by: lean)
        let torso = CGPath(roundedRect: CGRect(x: -5, y: -6.6, width: 10, height: 6.8), cornerWidth: 1.8,
                           cornerHeight: 1.8, transform: &bodyT)
        s.shape(torso, round: 0.1)
        s.detail(CGPath(roundedRect: CGRect(x: -3.2, y: -5.2, width: 4.6, height: 3.6), cornerWidth: 0.8,
                        cornerHeight: 0.8, transform: &bodyT), .belly)
        let light = u.truncatingRemainder(dividingBy: 0.5) < 0.25
        s.detailEllipse(frame.point(2.6, -4.4), 0.55, 0.55, light ? .accent : .horn)
        s.detailEllipse(frame.point(2.6, -2.6), 0.55, 0.55, light ? .horn : .accent)

        // 머리
        let neck = frame.point(0.6, -6.4)
        let headCenter = neck + CGPoint(0.8, -3.6 + slump * 6) + CGPoint(0, pose.activity == .stand ? 0.2 * sin(tau * u) : 0)
        let headTilt = lean + slump
        var headT = CGAffineTransform(translationX: headCenter.x, y: headCenter.y).rotated(by: headTilt)
        s.capsule([neck, headCenter + CGPoint(0, 2.6)], width: 1.6, .dark)
        // 안테나
        let antennaBase = headCenter + CGPoint(-0.5, -3.6).rotated(headTilt)
        let antennaTip = antennaBase + CGPoint.polar(-1.75 - slump * 2 + 0.12 * sin(tau * u * 2), 2.6)
        s.capsule([antennaBase, antennaTip], width: 0.5, .dark)
        s.circle(antennaTip, 0.9, light || pose.activity == .sleep ? .accent : .horn)
        s.shape(CGPath(roundedRect: CGRect(x: -4.6, y: -3.8, width: 9.2, height: 7.2), cornerWidth: 2.2,
                       cornerHeight: 2.2, transform: &headT), round: 0.1)
        s.detail(CGPath(roundedRect: CGRect(x: -3.4, y: -2.4, width: 7.4, height: 4.0), cornerWidth: 1.6,
                        cornerHeight: 1.6, transform: &headT), .belly)
        let face = BodyFrame(center: headCenter, pitch: headTilt)
        s.eye(face.point(-0.6, -0.4), 0.95)
        s.eye(face.point(2.2, -0.4), 0.95)
        s.detailLine([face.point(0.2, 1.0), face.point(1.4, 1.0)], width: 0.35, .dark)
        s.detailEllipse(face.point(-4.7, 0), 0.6, 1.2, .dark)
        // 팔 (가까운 쪽)
        let near = frame.point(0.8, -5.0)
        let elbow = near + CGPoint.polar(1.75 - swing * 1.4, 2.4)
        let hand = elbow + CGPoint.polar(1.0 - swing, 2.2)
        s.capsule([near, elbow, hand], width: 1.8, .dark, own: true)
        s.circle(hand, 1.1, .dark, own: true)
    }
}

/// UFO: 둥실 떠서 기울고, 테두리 불빛이 빙글 돈다. 유리 돔 안에 외계인이 탄다.
struct UFO: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0xB4BFCC), belly: NSColor(hex: 0x8794A5),
                                   dark: NSColor(hex: 0x5C6878), accent: NSColor(hex: 0xFF9F2E),
                                   horn: NSColor(hex: 0xFFE14D), pink: NSColor(hex: 0xFF7DB0),
                                   extra: NSColor(hex: 0x7CE07C))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let moving = pose.activity == .walk || pose.activity == .run
        let fast = pose.activity == .run
        let landed = pose.activity == .sleep
        let hover: CGFloat = landed ? 0 : 1.2 * sin(tau * u)
        let tilt: CGFloat = fast ? 0.18 : (moving ? 0.08 + 0.04 * sin(tau * u) : 0.04 * sin(tau * u))
        let center = CGPoint(17, (landed ? 16.2 : (pose.activity == .sit ? 14 : 12.6)) + hover)
        let frame = BodyFrame(center: center, pitch: tilt)

        if landed {
            for x in [-4.5, 4.5] as [CGFloat] {
                let top = frame.point(x * 0.7, 1.4)
                s.capsule([top, CGPoint(top.x + x * 0.3, Stage.ground - 0.4)], width: 0.7, .dark)
                s.ellipse(CGPoint(top.x + x * 0.3, Stage.ground - 0.4), 0.9, 0.4, .dark)
            }
        }
        // 빔
        if pose.activity == .stand || pose.activity == .sit {
            let beam = [frame.point(-2.4, 2.4), frame.point(2.4, 2.4),
                        CGPoint(center.x + 5, Stage.ground), CGPoint(center.x - 5, Stage.ground)]
            s.polygon(beam, round: 0, .glass, layer: .detail)
        }
        // 외계인과 유리 돔
        let alien = frame.point(0.4, -3.2)
        let bounce: CGFloat = moving ? 0.25 * sin(tau * u * 2) : 0
        s.capsule([alien + CGPoint(-0.8, -1.6), alien + CGPoint(-1.4, -3.0 + bounce)], width: 0.4, .extra)
        s.circle(alien + CGPoint(-1.4, -3.0 + bounce), 0.55, .horn)
        s.ellipse(alien + CGPoint(0, bounce), 2.5, 2.2, .extra)
        s.eye(alien + CGPoint(0.9, -0.2 + bounce), 0.75)
        s.ellipse(frame.point(0, -1.4), 4.5, 4.2, rotation: tilt, .glass)
        s.detailEllipse(frame.point(-2.0, -3.2), 1.0, 0.55, rotation: -0.6, .white)
        // 접시
        s.ellipse(frame.point(0, 1.4), 5.4, 1.8, rotation: tilt, .belly)
        s.ellipse(center, 9.2, 2.5, rotation: tilt)
        s.detailEllipse(frame.point(0, -0.4), 8.0, 0.8, rotation: tilt, .belly)
        // 테두리 불빛: 앞쪽 절반만 보인다
        let colors: [Role] = [.horn, .accent, .pink]
        for k in 0..<8 {
            let a = CGFloat(k) / 8 * tau + tau * u * (fast ? 2 : 1)
            guard sin(a) > -0.1 else { continue }
            let p = frame.point(cos(a) * 7.6, 0.6 + sin(a) * 0.9)
            let on = !landed && (k + Int(u * 8)) % 2 == 0
            s.detailEllipse(p, 0.6, 0.5, on ? colors[k % 3] : .dark)
        }
    }
}

/// 닌자: 팔을 뒤로 젖히고 달리며 머리띠 끈이 펄럭인다.
struct Ninja: CharacterRig {
    let palette = CharacterPalette(body: NSColor(hex: 0x353849), belly: NSColor(hex: 0xF5CFA8),
                                   dark: NSColor(hex: 0x23252F), extra: NSColor(hex: 0xE5484D))

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let activity = pose.activity
        let fast = activity == .run
        let moving = activity == .walk || fast
        let groundY = Stage.ground - 0.5
        let legLength: CGFloat = 4.6
        var bob: CGFloat = 0, lean: CGFloat = 0, stride: CGFloat = 0, lift: CGFloat = 0
        switch activity {
        case .walk: stride = 1.6; lift = 1.2; bob = -0.4 * abs(sin(tau * u)); lean = 0.1
        case .run: stride = 2.8 * pose.speed; lift = 2.2; bob = -1.0 * abs(sin(tau * u)); lean = 0.42
        case .stand: bob = 0.15 * sin(tau * u)
        case .sit: lean = 0.3
        case .sleep: lean = 0.08
        }
        let crouch: CGFloat = activity == .sit ? 2.2 : (activity == .sleep ? 3.4 : 0)
        let hip = CGPoint(15.5, groundY - legLength + bob + crouch)
        let torso = BodyFrame(center: hip, pitch: lean)
        let shoulder = torso.point(0, -4.2)

        // 다리
        for (offset, far) in [(CGFloat(0.5), true), (CGFloat(0), false)] {
            let hipAt = hip + CGPoint(far ? -0.6 : 0.3, 0)
            let foot: CGPoint
            switch activity {
            case .sit: foot = CGPoint(hipAt.x + (far ? -1.2 : 2.2), groundY)
            case .sleep: foot = CGPoint(hipAt.x + (far ? -2.8 : 3.0), groundY - 0.2)
            default:
                let step = Gait.foot(u + offset, stride: stride, lift: lift, duty: 0.5)
                foot = CGPoint(hipAt.x + step.dx, groundY - step.lift)
            }
            s.limb(hip: hipAt, foot: foot, length: legLength * 1.15, width: 1.8, kneeForward: true, far: far,
                   own: !far)
            s.ellipse(foot + CGPoint(0.5, 0.1), 1.2, 0.6, .dark, far: far)
        }
        // 먼 쪽 팔
        let armBack: CGFloat = fast ? 2.75 : (moving ? 1.6 + 0.7 * sin(tau * u + .pi) : 1.75)
        s.capsule([shoulder, shoulder + CGPoint.polar(armBack + lean * 0.5, 3.6)], width: 1.4, far: true)
        // 몸통
        s.capsule([hip, shoulder], width: 4.2)
        s.capsule([torso.point(-1.6, -1.6), torso.point(1.6, -1.6)], width: 1.0, .dark)
        // 머리와 머리띠 끈
        let head = shoulder + CGPoint(0.6, -3.6).rotated(lean * 0.5) + CGPoint(0, activity == .sleep ? 1.2 : 0)
        let knot = head + CGPoint(-3.6, -1.4)
        for k in 0..<2 {
            var points = [knot]
            var angle: CGFloat = .pi - 0.1 + CGFloat(k) * 0.35
            for i in 1...5 {
                let flutter = (fast ? 0.45 : 0.22) * sin(tau * u * 2 - CGFloat(i) * 0.8 + CGFloat(k))
                angle += flutter * 0.4 + (fast ? 0 : 0.12)
                points.append(points[i - 1] + CGPoint.polar(angle, fast ? 1.3 : 1.0))
            }
            s.tapered(points, from: 1.2, to: 0.5, .extra, far: k == 1)
        }
        s.circle(head, 4.0)
        s.detail(CGPath(roundedRect: CGRect(x: head.x - 1.4, y: head.y - 1.5, width: 5.0, height: 2.6),
                        cornerWidth: 1.2, cornerHeight: 1.2, transform: nil), .belly)
        s.capsule([head + CGPoint(-3.8, -1.6), head + CGPoint(3.6, -2.4)], width: 1.2, .extra)
        s.detailEllipse(head + CGPoint(1.2, -2.2), 0.7, 0.5, .horn)
        s.eye(head + CGPoint(0.6, -0.2), 0.75)
        s.eye(head + CGPoint(2.6, -0.2), 0.75)
        // 가까운 쪽 팔
        let armFront: CGFloat = fast ? 2.55 : (moving ? 1.6 + 0.7 * sin(tau * u) : (activity == .sleep ? 0.9 : 1.3))
        s.capsule([shoulder, shoulder + CGPoint.polar(armFront + lean * 0.5, 3.6)], width: 1.4, own: true)
    }
}
