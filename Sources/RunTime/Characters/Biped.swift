import AppKit

/// 두 발로 걷는 새 (병아리·오리·펭귄). 다리는 가늘고, 뛸 때 날개를 퍼덕이며 몸을 좌우로 흔든다.
struct Bird: CharacterRig {
    enum Beak { case short, flat, pointy }

    var palette: CharacterPalette
    var bodyRx: CGFloat
    var bodyRy: CGFloat
    /// 몸 기울기 (음수 = 앞이 들림). 펭귄은 거의 선 자세.
    var tilt: CGFloat = 0
    var headR: CGFloat
    var headOffset: CGPoint
    var neck = false
    var beak: Beak
    var legLength: CGFloat = 2.8
    var waddle: CGFloat = 0.06
    var tuft = false
    var bellyPatch = false
    var tailFeathers = true

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let sitting = pose.activity == .sit || pose.activity == .sleep
        var stride: CGFloat = 0, lift: CGFloat = 0, bob: CGFloat = 0, sway: CGFloat = 0, flap: CGFloat = 0
        switch pose.activity {
        case .stand:
            bob = 0.15 * sin(tau * u)
        case .walk:
            stride = 1.4; lift = 1.2
            bob = -0.4 * abs(sin(tau * u))
            sway = waddle * sin(tau * u)
        case .run:
            stride = 2.3 * pose.speed; lift = 1.9
            bob = -0.9 * abs(sin(tau * u)) * pose.speed
            sway = waddle * 1.3 * sin(tau * u)
            flap = sin(tau * u * 2)
        case .sit:
            bob = 0.2 * sin(tau * u * 2)
        case .sleep:
            bob = 0.12 * sin(tau * u)
        }

        let groundY = Stage.ground - 0.6
        let lift0: CGFloat = sitting ? -legLength + 0.6 : 0
        let center = CGPoint(16.5, groundY - legLength - bodyRy * 0.9 + bob - lift0)
        let pitch = tilt + sway + (pose.activity == .run ? -0.08 : 0)
        let body = BodyFrame(center: center, pitch: pitch)

        // 다리
        if !sitting {
            let hip = body.point(bodyRx * 0.05, bodyRy * 0.8)
            for (offset, far) in [(CGFloat(0.5), true), (CGFloat(0), false)] {
                let step = Gait.foot(u + offset, stride: stride, lift: lift, duty: 0.55)
                let hipAt = hip + CGPoint(far ? -0.8 : 0.4, 0)
                let foot = CGPoint(hipAt.x + step.dx, groundY - step.lift)
                s.limb(hip: hipAt, foot: foot, length: legLength * 1.15, width: 0.85, kneeForward: false, .accent,
                       far: far)
                s.polygon([foot + CGPoint(-0.7, 0.3), foot + CGPoint(1.6, 0.35), foot + CGPoint(0.2, -0.5)],
                          round: 0.3, .accent, far: far)
            }
        }

        // 꼬리 깃
        if tailFeathers {
            let root = body.point(-bodyRx * 0.85, -bodyRy * 0.15)
            let wag = 0.15 * sin(tau * u * 2)
            s.polygon([root + CGPoint(1, -0.8), root + CGPoint.polar(-2.6 + wag, 2.6), root + CGPoint(0.8, 1.2)],
                      round: 0.4)
        }

        s.ellipse(center, bodyRx, bodyRy, rotation: pitch)
        if bellyPatch {
            s.ellipse(body.point(bodyRx * 0.3, bodyRy * 0.12), bodyRx * 0.68, bodyRy * 0.82, rotation: pitch, .belly)
        }

        // 머리
        let sleeping = pose.activity == .sleep
        var head = body.point(headOffset.x, headOffset.y) + CGPoint(0, -bob * 0.3)
        if sleeping { head = head + CGPoint(-0.6, 1.4) }
        if neck {
            s.capsule([body.point(bodyRx * 0.55, -bodyRy * 0.3), head + CGPoint(-0.4, 0.8)], width: headR * 1.25)
        }
        s.circle(head, headR)
        if bellyPatch {
            s.ellipse(head + CGPoint(headR * 0.3, headR * 0.15), headR * 0.7, headR * 0.72, .belly)
        }
        if tuft {
            for k in 0..<3 {
                let root = head + CGPoint.polar(-1.75 + CGFloat(k) * 0.28, headR * 0.92)
                let tip = root + CGPoint.polar(-1.9 + CGFloat(k) * 0.45 + 0.1 * sin(tau * u + CGFloat(k)), 1.5)
                s.capsule([root, tip], width: 0.55)
            }
        }

        // 날개
        let wingRoot = body.point(-bodyRx * 0.05, -bodyRy * 0.15)
        let wingRot = pitch + (sitting ? 0.35 : 0.2) - flap * 0.55
        s.ellipse(wingRoot + CGPoint(-bodyRx * 0.18, bodyRy * 0.15).rotated(wingRot), bodyRx * 0.55, bodyRy * 0.5,
                  rotation: wingRot, bellyPatch ? .body : .body, own: true)

        // 부리
        let beakBase = head + CGPoint(headR * 0.85, headR * 0.12)
        let open: CGFloat = pose.mouthOpen ? 0.55 * (0.5 + 0.5 * sin(tau * u * 2)) : 0
        switch beak {
        case .short:
            s.polygon([beakBase + CGPoint(-0.3, -0.9), beakBase + CGPoint(1.7, -0.1 - open),
                       beakBase + CGPoint(-0.3, 0.7)], round: 0.35, .accent)
            if open > 0 {
                s.polygon([beakBase + CGPoint(-0.3, 0.2), beakBase + CGPoint(1.4, 0.4 + open),
                           beakBase + CGPoint(-0.3, 0.9)], round: 0.3, .accent)
            }
        case .flat:
            let tip = beakBase + CGPoint(2.6, 0.3)
            s.capsule([beakBase + CGPoint(-0.4, 0), tip], width: 1.5, .accent)
            if open > 0 { s.capsule([beakBase + CGPoint(-0.4, 0.8), tip + CGPoint(-0.2, 0.9 + open)], width: 1.0, .accent) }
        case .pointy:
            s.polygon([beakBase + CGPoint(-0.4, -0.6), beakBase + CGPoint(1.9, 0.15 + open * 0.4),
                       beakBase + CGPoint(-0.4, 0.6 + open)], round: 0.25, .accent)
        }

        s.eye(head + CGPoint(headR * 0.3, -headR * 0.15), headR * 0.26)
        s.detailEllipse(head + CGPoint(headR * 0.15, headR * 0.45), 0.85, 0.5, .pink)
    }

    static let chick = Bird(
        palette: CharacterPalette(body: NSColor(hex: 0xFFD84D), belly: NSColor(hex: 0xFFF0A8),
                                  dark: NSColor(hex: 0xE5B52E)),
        bodyRx: 5.0, bodyRy: 4.4, headR: 3.7, headOffset: CGPoint(2.2, -3.9),
        beak: .short, legLength: 2.6, waddle: 0.08, tuft: true, tailFeathers: false
    )

    static let duck = Bird(
        palette: CharacterPalette(body: NSColor(hex: 0xFBFBFB), belly: NSColor(hex: 0xFFFFFF),
                                  dark: NSColor(hex: 0xD6D9DE), accent: NSColor(hex: 0xFF9B2E)),
        bodyRx: 6.0, bodyRy: 3.6, tilt: -0.08, headR: 3.1, headOffset: CGPoint(4.4, -5.0), neck: true,
        beak: .flat, legLength: 2.6, waddle: 0.07
    )

    static let penguin = Bird(
        palette: CharacterPalette(body: NSColor(hex: 0x2F3646), belly: NSColor(hex: 0xFAFAFA),
                                  dark: NSColor(hex: 0x1C2130), accent: NSColor(hex: 0xFF9F2E)),
        bodyRx: 4.4, bodyRy: 5.6, tilt: 0, headR: 3.5, headOffset: CGPoint(0.9, -5.4),
        beak: .pointy, legLength: 1.6, waddle: 0.16, bellyPatch: true, tailFeathers: false
    )
}

/// 공룡과 드래곤: 굵은 꼬리로 균형을 잡는 두 발 파충류. 드래곤은 날개를 퍼덕이며 떠서 난다.
struct Reptile: CharacterRig {
    var palette: CharacterPalette
    var flying = false
    var spikes = true

    func draw(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let activity = pose.activity
        let groundY = Stage.ground - 0.8
        var bob: CGFloat = 0, stride: CGFloat = 0, lift: CGFloat = 0, pitch: CGFloat = -0.18
        switch activity {
        case .stand: bob = 0.2 * sin(tau * u)
        case .walk: stride = 1.8; lift = 1.4; bob = -0.4 * abs(sin(tau * u))
        case .run:
            stride = 2.8 * pose.speed; lift = 2.2
            bob = -1.0 * abs(sin(tau * u)) * pose.speed
            pitch = -0.05
        case .sit: pitch = -0.45
        case .sleep: pitch = 0
        }
        let airborne = flying && (activity == .walk || activity == .run || activity == .stand)
        let hover: CGFloat = airborne ? -3.2 + 1.0 * sin(tau * u) : 0
        let legLength: CGFloat = flying ? 4.2 : 5.2
        let lowered: CGFloat
        switch activity {
        case .sit: lowered = 2.4
        case .sleep: lowered = 4.6
        default: lowered = 0
        }
        let center = CGPoint(14.6, groundY - legLength - 2.2 + bob + hover + lowered)
        let body = BodyFrame(center: center, pitch: pitch)
        let bodyRx: CGFloat = 5.0, bodyRy: CGFloat = 3.7

        // 먼 쪽 날개
        if flying { wing(s, body, u: u, airborne: airborne, far: true) }

        // 다리
        let hip = body.point(-0.6, bodyRy * 0.55)
        if activity != .sleep {
            for (offset, far) in [(CGFloat(0.5), true), (CGFloat(0), false)] {
                let hipAt = hip + CGPoint(far ? -0.9 : 0, 0)
                let foot: CGPoint
                if airborne {
                    let dangle = 0.4 * sin(tau * u + offset * tau)
                    foot = hipAt + CGPoint(-1.2 + dangle, legLength * 0.85)
                } else if activity == .sit {
                    foot = CGPoint(hipAt.x + 2.6, groundY)
                } else {
                    let step = Gait.foot(u + offset, stride: stride, lift: lift, duty: 0.55)
                    foot = CGPoint(hipAt.x + step.dx, groundY - step.lift)
                }
                s.limb(hip: hipAt, foot: foot, length: legLength * 1.15, width: 2.6, kneeForward: true, .body,
                       far: far, own: !far)
                s.ellipse(foot + CGPoint(0.6, 0.15), 1.6, 0.85, .body, far: far)
            }
        }

        // 꼬리
        let tailRoot = body.point(-bodyRx * 0.75, -bodyRy * 0.05)
        var tail = [tailRoot]
        var angle: CGFloat = activity == .sleep ? 3.1 : (activity == .run ? 2.95 : 2.75)
        for k in 1...8 {
            angle += (activity == .sleep ? 0.02 : 0.04) + 0.09 * sin(tau * u - CGFloat(k) * 0.5)
            tail.append(tail[k - 1] + CGPoint.polar(angle, 1.15))
        }
        s.tapered(tail, from: 4.0, to: 0.7)
        if flying, let tip = tail.last, tail.count > 1 {
            let dir = (tip - tail[tail.count - 2]).normalized
            let n = CGPoint(-dir.y, dir.x)
            s.polygon([tip + n * 1.1, tip + dir * 1.8, tip - n * 1.1, tip - dir * 0.3], round: 0.25, .extra)
        }

        s.ellipse(center, bodyRx, bodyRy, rotation: pitch)
        s.ellipse(body.point(bodyRx * 0.25, bodyRy * 0.45), bodyRx * 0.62, bodyRy * 0.48, rotation: pitch, .belly)

        // 등 가시
        if spikes {
            let count = 6
            for k in 0..<count {
                let t = CGFloat(k) / CGFloat(count - 1)
                let a = (205 + t * 115) * CGFloat.pi / 180
                let base = body.point(cos(a) * bodyRx * 0.92, sin(a) * bodyRy * 0.92)
                let out = (base - body.center).normalized
                let side = CGPoint(-out.y, out.x) * 0.75
                s.polygon([base + side, base + out * 1.6, base - side], round: 0.25, .dark)
            }
        }

        // 머리
        let sleeping = activity == .sleep
        let headBob = activity == .run ? 0.4 * sin(tau * u * 2) : 0
        var head = body.point(bodyRx * 0.85, -bodyRy * 1.05) + CGPoint(0.6, headBob)
        if sleeping { head = CGPoint(center.x + bodyRx + 1.2, groundY - 2.6) }
        s.capsule([body.point(bodyRx * 0.5, -bodyRy * 0.3), head + CGPoint(-1, 0.6)], width: 3.4)
        s.ellipse(head, 3.9, 3.1, rotation: 0.05)
        let jawOpen: CGFloat = pose.mouthOpen ? 0.6 + 0.4 * sin(tau * u * 2) : 0
        s.ellipse(head + CGPoint(2.0, 1.2 + jawOpen * 0.6), 2.4, 1.5, rotation: 0.1 + jawOpen * 0.2)
        if flying {
            for k in 0..<2 {
                let root = head + CGPoint(-1.0 - CGFloat(k) * 1.4, -2.4 + CGFloat(k) * 0.3)
                s.polygon([root + CGPoint(-0.6, 0.4), root + CGPoint(-1.6, -2.0), root + CGPoint(0.6, 0.2)],
                          round: 0.3, .horn, far: k == 1)
            }
        }
        // 짧은 팔
        if !sleeping {
            let shoulder = body.point(bodyRx * 0.62, bodyRy * 0.15)
            let wave = activity == .run ? 0.5 * sin(tau * u * 2) : 0
            s.capsule([shoulder, shoulder + CGPoint(1.4, 0.9 + wave), shoulder + CGPoint(2.2, 0.4 + wave)],
                      width: 1.2, own: true)
        }
        if flying { wing(s, body, u: u, airborne: airborne, far: false) }

        s.eye(head + CGPoint(0.9, -0.9), 0.95)
        s.detailEllipse(head + CGPoint(3.6, 0.5), 0.35, 0.25, .ink)
        s.detailEllipse(head + CGPoint(0.2, 0.8), 0.9, 0.5, .pink)
        if !pose.mouthOpen {
            s.detailCurve(head + CGPoint(1.6, 1.6), control: head + CGPoint(2.8, 2.2), head + CGPoint(3.9, 1.5),
                          width: 0.3, .ink)
        }
    }

    /// 박쥐 날개: 위·아래로 퍼덕인다.
    private func wing(_ s: Sketch, _ body: BodyFrame, u: CGFloat, airborne: Bool, far: Bool) {
        let root = body.point(0.4, -3.0)
        let beat = airborne ? sin(tau * u * (s.pose.activity == .run ? 2 : 1)) : -0.6
        let spread = -1.25 + beat * 0.85 + (far ? -0.25 : 0)
        let tip = root + CGPoint.polar(spread - 0.5, 9)
        let mid = root + CGPoint.polar(spread + 0.2, 6.6)
        let back = root + CGPoint(-4.8, 0.8)
        let path = CGMutablePath()
        path.move(to: root + CGPoint(1, 0.5))
        path.addLine(to: tip)
        path.addQuadCurve(to: mid, control: (tip + mid) * 0.5 + CGPoint(0.4, 1.2))
        path.addQuadCurve(to: back, control: (mid + back) * 0.5 + CGPoint(0.6, 1.4))
        path.closeSubpath()
        s.shape(path, round: 0.25, .extra, far: far, own: !far)
        if !far {
            s.detailLine([root + CGPoint(0.6, 0.3), mid], width: 0.3, .dark)
        }
    }

    static let dino = Reptile(
        palette: CharacterPalette(body: NSColor(hex: 0x7CC96B), belly: NSColor(hex: 0xE3F5C8),
                                  dark: NSColor(hex: 0x3F8C4A))
    )

    static let dragon = Reptile(
        palette: CharacterPalette(body: NSColor(hex: 0x9A6BE0), belly: NSColor(hex: 0xF5DB8C),
                                  dark: NSColor(hex: 0x6B44B0), horn: NSColor(hex: 0xFFF1C9),
                                  extra: NSColor(hex: 0x7C55D6)),
        flying: true
    )
}
