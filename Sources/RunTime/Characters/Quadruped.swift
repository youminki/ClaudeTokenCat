import AppKit

/// 네 발 동물 공용 골격. 몸통·머리·귀·꼬리 모양과 비율만 바꿔 고양이부터 유니콘까지 만든다.
/// 다리는 2관절이고 발은 땅을 짚는 동안 뒤로 밀고 드는 동안 앞으로 내딛는다 (`Gait.foot`).
struct Quadruped: CharacterRig {
    enum Ears { case pointy(CGFloat), floppy, round, long, none }
    enum Tail { case curl, bushy, stub, wisp, puff, none }

    var palette: CharacterPalette
    var bodyRx: CGFloat = 5.8
    var bodyRy: CGFloat = 3.6
    var legLength: CGFloat = 4.8
    var legWidth: CGFloat = 2.3
    var headRx: CGFloat = 4.7
    var headRy: CGFloat = 4.2
    /// 몸통 중심에서 머리 중심까지 (몸통 기울기 적용 전).
    var headOffset = CGPoint(6.0, -4.2)
    var headTilt: CGFloat = 0
    /// 주둥이: 머리 중심 기준 위치와 반지름.
    var snout: (offset: CGPoint, rx: CGFloat, ry: CGFloat)?
    var ears: Ears = .pointy(3)
    var tail: Tail = .curl
    var tailLength: CGFloat = 9
    var legRole: Role = .body
    /// 앉을 때 몸을 젖히는 각도 (고슴도치처럼 둥근 몸은 덜 젖힌다).
    var sitPitch: CGFloat = -1.0
    var earRole: Role = .body
    /// 토끼처럼 뒷다리 두 개를 함께 민다.
    var hop = false
    var paw: CGFloat = 1
    /// 몸통을 그린 뒤, 앞다리를 그리기 전 (판다 어깨띠, 고슴도치 가시).
    var overlay: ((Sketch, Anchors) -> Void)?
    /// 머리까지 그린 뒤 (뿔, 갈기, 줄무늬, 수염).
    var decorate: ((Sketch, Anchors) -> Void)?

    /// 장식이 붙을 기준점.
    struct Anchors {
        var body: BodyFrame
        var bodyRx: CGFloat
        var bodyRy: CGFloat
        var head: CGPoint
        var headRx: CGFloat
        var headRy: CGFloat
        var headTilt: CGFloat
        var pose: CharacterPose

        func headPoint(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            head + CGPoint(x, y).rotated(headTilt)
        }

        /// 머리 타원 둘레의 점 (각도는 y 아래 좌표 기준, -90° = 정수리).
        func headEdge(_ degrees: CGFloat, _ extra: CGFloat = 0) -> CGPoint {
            let a = degrees * .pi / 180
            return headPoint(cos(a) * (headRx + extra), sin(a) * (headRy + extra))
        }
    }

    func draw(_ s: Sketch) {
        switch s.pose.activity {
        case .stand, .walk, .run: drawUpright(s)
        case .sit: drawSit(s)
        case .sleep: drawSleep(s)
        }
    }

    // MARK: 서기·걷기·달리기

    private func drawUpright(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let speed = pose.speed

        var stride: CGFloat = 0, lift: CGFloat = 0, duty: CGFloat = 0.5
        var pitch: CGFloat = 0, bob: CGFloat = 0, stretch: CGFloat = 0
        var offsets: [CGFloat] = [0, 0.5, 0.25, 0.75]   // 뒷다리 앞쪽, 뒷다리 뒤쪽, 앞다리 앞쪽, 앞다리 뒤쪽
        switch pose.activity {
        case .stand:
            bob = 0.18 * sin(tau * u)
        case .walk:
            stride = legLength * 0.30
            lift = legLength * 0.22
            duty = 0.6
            bob = -0.35 * (0.5 - 0.5 * cos(2 * tau * u))
            pitch = 0.025 * sin(2 * tau * u)
        default:
            stride = legLength * 0.52 * speed
            lift = legLength * 0.36
            duty = hop ? 0.38 : 0.45
            offsets = hop ? [0, 0.03, 0.42, 0.46] : [0, 0.08, 0.46, 0.56]
            pitch = -0.11 * speed * sin(tau * u + 0.6)
            bob = (hop ? -2.2 : -1.0) * speed * max(0, sin(tau * u - 0.4))
            stretch = 0.08 * speed * sin(tau * u + 0.6)
        }

        let rx = bodyRx * (1 + stretch)
        let hipDrop = bodyRy * 0.35
        let groundY = Stage.ground - legWidth * 0.5
        let center = CGPoint(17 - headOffset.x * 0.25, groundY - legLength - hipDrop + bob)
        let body = BodyFrame(center: center, pitch: pitch)
        let hindHip = body.point(-rx * 0.58, hipDrop)
        let frontHip = body.point(rx * 0.55, hipDrop)
        let reach = legLength * 1.1

        func foot(_ hip: CGPoint, _ offset: CGFloat) -> CGPoint {
            let step = Gait.foot(u + offset, stride: stride, lift: lift, duty: duty)
            return CGPoint(hip.x + step.dx, groundY - step.lift)
        }

        // 먼 쪽 다리 (어둡게)
        let farHindFoot = foot(hindHip + CGPoint(0.9, 0), offsets[1])
        let farFrontFoot = foot(frontHip + CGPoint(-0.9, 0), offsets[3])
        s.limb(hip: hindHip + CGPoint(0.9, 0), foot: farHindFoot, length: reach, width: legWidth * 0.92,
               kneeForward: false, legRole, far: true)
        s.limb(hip: frontHip + CGPoint(-0.9, 0), foot: farFrontFoot, length: reach, width: legWidth * 0.92,
               kneeForward: true, legRole, far: true)
        pawShape(s, farHindFoot, far: true, hind: true)
        pawShape(s, farFrontFoot, far: true, hind: false)

        let headCenter = body.point(headOffset.x, headOffset.y)
            + CGPoint(0, -bob * 0.35 + (pose.activity == .stand ? 0.1 * sin(tau * u + 1) : 0))
        let anchors = Anchors(body: body, bodyRx: rx, bodyRy: bodyRy, head: headCenter,
                              headRx: headRx, headRy: headRy, headTilt: headTilt + pitch * 0.4, pose: pose)

        drawTail(s, anchors, running: pose.activity == .run)
        drawEars(s, anchors, far: true)
        s.ellipse(body.center, rx, bodyRy, rotation: pitch)
        overlay?(s, anchors)

        let nearHindFoot = foot(hindHip, offsets[0])
        let nearFrontFoot = foot(frontHip, offsets[2])
        s.limb(hip: hindHip, foot: nearHindFoot, length: reach, width: legWidth, kneeForward: false, legRole,
               own: true)
        s.limb(hip: frontHip, foot: nearFrontFoot, length: reach, width: legWidth, kneeForward: true, legRole,
               own: true)
        pawShape(s, nearHindFoot, far: false, hind: true)
        pawShape(s, nearFrontFoot, far: false, hind: false)

        drawHead(s, anchors, neckFrom: body.point(rx * 0.6, -bodyRy * 0.25))
    }

    private func pawShape(_ s: Sketch, _ foot: CGPoint, far: Bool, hind: Bool) {
        let size = legWidth * paw * (hind && hop ? 1.5 : 1)
        s.ellipse(foot + CGPoint(size * 0.28, 0.05), size * 0.62, legWidth * 0.48, legRole, far: far)
    }

    // MARK: 앉기 (지침)

    private func drawSit(_ s: Sketch) {
        let pose = s.pose
        let u = pose.cycle
        let pant = pose.mouthOpen ? 0.25 * sin(tau * u * 2) : 0
        let groundY = Stage.ground - legWidth * 0.5
        let haunchR = bodyRy * 0.98
        let haunch = CGPoint(13.4, Stage.ground - haunchR)
        // 몸통을 뒤로 젖혀 세운다: 엉덩이 위에서 앞쪽이 위를 향한다
        let body = BodyFrame(center: CGPoint(15.0, Stage.ground - bodyRy * 1.55 + pant * 0.4), pitch: sitPitch)
        let headCenter = body.point(bodyRx * 0.95, 0) + CGPoint(1.0, -headRy * 0.5 + pant)
        let anchors = Anchors(body: body, bodyRx: bodyRx * 0.85, bodyRy: bodyRy, head: headCenter,
                              headRx: headRx, headRy: headRy, headTilt: headTilt * 0.5 + 0.1, pose: pose)
        let chest = body.point(bodyRx * 0.45, bodyRy * 0.55)

        // 먼 쪽 앞다리, 꼬리
        s.capsule([chest + CGPoint(-0.9, 0), CGPoint(chest.x - 0.6, groundY)], width: legWidth * 0.92, legRole,
                  far: true)
        pawShape(s, CGPoint(chest.x - 0.6, groundY), far: true, hind: false)
        drawSittingTail(s, root: CGPoint(haunch.x - haunchR * 0.7, Stage.ground - 1.3), u: u)
        drawEars(s, anchors, far: true)

        s.ellipse(body.center, bodyRx * 0.85, bodyRy, rotation: body.pitch)
        s.ellipse(haunch, haunchR * 1.08, haunchR, rotation: -0.25, legRole == .dark ? .dark : .body)
        overlay?(s, anchors)
        s.ellipse(CGPoint(haunch.x + haunchR * 0.95, groundY + 0.15), legWidth * 0.95, legWidth * 0.48, legRole)
        s.capsule([chest, CGPoint(chest.x + 0.3, groundY)], width: legWidth, legRole, own: true)
        pawShape(s, CGPoint(chest.x + 0.3, groundY), far: false, hind: false)
        drawHead(s, anchors, neckFrom: body.point(bodyRx * 0.5, 0))
    }

    /// 앉았을 때 꼬리는 바닥에 늘어뜨리고 끝만 살랑인다.
    private func drawSittingTail(_ s: Sketch, root: CGPoint, u: CGFloat) {
        switch tail {
        case .none, .stub:
            return
        case .puff:
            s.circle(root + CGPoint(0, -0.6), 1.7, .belly)
            return
        default:
            break
        }
        let flick = 0.6 * sin(tau * u)
        let points = (0...8).map { i -> CGPoint in
            let t = CGFloat(i) / 8
            let x = root.x - t * tailLength * 0.7
            let curl = t > 0.6 ? pow((t - 0.6) / 0.4, 2) * (3.2 + flick) : 0
            return CGPoint(x - curl * 0.3, Stage.ground - 0.9 - curl)
        }
        switch tail {
        case .bushy:
            s.tapered(points, from: 2.2, to: 2.0)
            if let tip = points.last { s.ellipse(tip, 1.6, 1.3, .belly) }
        case .wisp:
            s.tapered(points, from: 2.0, to: 0.7, .pink)
        default:
            s.tapered(points, from: 1.6, to: 1.0)
        }
    }

    // MARK: 잠자기

    private func drawSleep(_ s: Sketch) {
        let pose = s.pose
        let breath = sin(tau * pose.cycle)
        let ry = bodyRy * (0.95 + 0.045 * breath)
        let center = CGPoint(15.5, Stage.ground - ry)
        let body = BodyFrame(center: center, pitch: 0)
        let headCenter = CGPoint(center.x + bodyRx * 0.82, Stage.ground - headRy * 0.88 - 0.15 * breath)
        let anchors = Anchors(body: body, bodyRx: bodyRx, bodyRy: ry, head: headCenter,
                              headRx: headRx, headRy: headRy, headTilt: 0.12, pose: pose)

        drawEars(s, anchors, far: true)
        s.ellipse(center, bodyRx * 1.02, ry)
        overlay?(s, anchors)
        // 몸을 감싼 꼬리
        if case .none = tail {} else if case .stub = tail {} else if case .puff = tail {
            s.circle(body.point(-bodyRx * 0.95, -ry * 0.1), 1.6, .belly)
        } else {
            let start = body.point(-bodyRx * 0.85, ry * 0.2)
            let points = (0...8).map { i -> CGPoint in
                let t = CGFloat(i) / 8
                return CGPoint(start.x + t * bodyRx * 1.7, Stage.ground - 0.9 - sin(t * .pi) * 0.6)
            }
            let width: CGFloat = tail == .bushy ? 2.6 : 1.5
            s.tapered(points, from: width, to: width * 0.6, tail == .wisp ? .pink : .body)
            if tail == .bushy, let tip = points.last { s.circle(tip, 1.1, .belly) }
        }
        s.ellipse(CGPoint(headCenter.x - headRx * 0.55, Stage.ground - 0.75), legWidth * 0.9, 0.75, legRole)
        drawHead(s, anchors, neckFrom: nil)
    }

    // MARK: 머리·귀·꼬리

    private func drawHead(_ s: Sketch, _ a: Anchors, neckFrom: CGPoint?) {
        if let neckFrom {
            s.capsule([neckFrom, a.headPoint(-a.headRx * 0.2, a.headRy * 0.2)], width: min(headRy, bodyRy) * 1.5)
        }
        s.ellipse(a.head, headRx, headRy, rotation: a.headTilt)
        if let snout {
            s.ellipse(a.headPoint(snout.offset.x, snout.offset.y), snout.rx, snout.ry, rotation: a.headTilt)
        }
        drawEars(s, a, far: false)
        decorate?(s, a)

        // 얼굴
        let eye = a.headPoint(headRx * 0.36, -headRy * 0.1)
        s.eye(eye, headRy * 0.23)
        let noseAt: CGPoint
        if let snout {
            noseAt = a.headPoint(snout.offset.x + snout.rx * 0.85, snout.offset.y - snout.ry * 0.35)
        } else {
            noseAt = a.headPoint(headRx * 0.92, headRy * 0.12)
        }
        s.detailEllipse(noseAt, 0.5, 0.38, .ink)
        s.detailEllipse(a.headPoint(headRx * 0.18, headRy * 0.45), 0.9, 0.5, .pink)
        if a.pose.mouthOpen {
            let mouth = noseAt + CGPoint(-0.5, 1.0)
            s.detailEllipse(mouth, 0.7, 0.55, .ink)
            s.detailEllipse(mouth + CGPoint(0.1, 0.45), 0.5, 0.4, .pink)
        }
    }

    private func drawEars(_ s: Sketch, _ a: Anchors, far: Bool) {
        let u = a.pose.cycle
        let flick = a.pose.activity == .run ? 0.12 * sin(tau * u) : 0.04 * sin(tau * u * 2)
        let sleeping = a.pose.activity == .sleep
        switch ears {
        case .none:
            break
        case .pointy(let height):
            let base: CGFloat = far ? -118 : -78
            let lean: CGFloat = sleeping ? -14 : 0
            let left = a.headEdge(base - 22 + lean, -0.3)
            let right = a.headEdge(base + 18 + lean, -0.3)
            let tipAngle = (base + lean - 8) * .pi / 180 + flick
            let tip = a.headPoint(0, 0) + CGPoint.polar(tipAngle + a.headTilt, max(headRx, headRy) + height)
            s.polygon([left, tip, right], round: 0.35, earRole, far: far)
            if !far {
                let inner = [left + (tip - left) * 0.25 + (right - left) * 0.2,
                             tip + (left + right - tip * 2) * 0.22,
                             right + (tip - right) * 0.25 + (left - right) * 0.2]
                s.detail(polygonPath(inner), .pink)
            }
        case .floppy:
            let pivot = a.headEdge(far ? -130 : -105, -0.6)
            let swing = (a.pose.activity == .run ? 0.35 : 0.1) * sin(tau * u - 0.8)
            let rot = (sleeping ? 1.1 : 0.35) + swing
            let c = pivot + CGPoint(0, 2.5).rotated(rot)
            s.ellipse(c, 1.5, 2.8, rotation: rot, earRole, far: far)
        case .round:
            let at = a.headEdge(far ? -128 : -72, -0.5)
            s.circle(at, 1.45, earRole, far: far)
        case .long:
            let root = a.headEdge(far ? -112 : -92, -0.8)
            let sway = (a.pose.activity == .run ? 0.25 : 0.06) * sin(tau * u - 0.5)
            let angle = (sleeping ? -168 : (far ? -116 : -104)) * CGFloat.pi / 180 + sway
            let mid = root + CGPoint.polar(angle, 3.4)
            let tip = mid + CGPoint.polar(angle - 0.12 - sway * 0.6, 3.2)
            s.capsule([root, mid, tip], width: 2.1, earRole, far: far)
            if !far { s.detailLine([root + (mid - root) * 0.4, mid, tip + (mid - tip) * 0.3], width: 0.8, .pink) }
        }
    }

    private func drawTail(_ s: Sketch, _ a: Anchors, running: Bool) {
        let u = a.pose.cycle
        let root = a.body.point(-a.bodyRx * 0.9, -a.bodyRy * 0.25)
        switch tail {
        case .none:
            return
        case .puff:
            s.circle(root + CGPoint(-0.4, 0.2), 1.7, .belly)
            return
        default:
            break
        }
        let count = 9
        let wagSpeed: CGFloat = tail == .stub ? 3 : 1
        let start: CGFloat
        let curl: CGFloat
        let sway: CGFloat
        var length = tailLength
        switch tail {
        case .curl:
            start = running ? -2.75 : -2.25
            curl = running ? 0.05 : 0.2
            sway = running ? 0.12 : 0.18
        case .bushy:
            start = running ? -2.75 : -2.35
            curl = running ? 0.02 : 0.1
            sway = 0.1
        case .stub:
            start = -2.1
            curl = 0.05
            sway = 0.35
            length = 3.6
        default:   // wisp
            start = running ? -2.9 : -2.35
            curl = running ? -0.04 : -0.12
            sway = 0.12
        }
        var points = [root]
        var angle = start
        for k in 1...count {
            angle += curl + sway * sin(tau * u * wagSpeed - CGFloat(k) * 0.55) * 0.35
            points.append(points[k - 1] + CGPoint.polar(angle, length / CGFloat(count)))
        }
        switch tail {
        case .bushy:
            s.tapered(points, from: 2.4, to: 2.0)
            if let tip = points.last, points.count > 2 {
                s.ellipse(tip, 1.9, 1.4, rotation: angle, .belly)
            }
        case .wisp:
            let droop = points.enumerated().map { i, p in p + CGPoint(0, pow(CGFloat(i) / CGFloat(count), 2) * 2.5) }
            s.tapered(droop, from: 2.4, to: 0.7, .pink)
            let lower = droop.enumerated().map { i, p in p + CGPoint(0.2, CGFloat(i) * 0.18) }
            s.tapered(lower, from: 1.5, to: 0.4, .extra)
        default:
            s.tapered(points, from: tail == .stub ? 1.8 : 1.6, to: 0.9)
        }
    }
}

func polygonPath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points)
    path.closeSubpath()
    return path
}

// MARK: - 네 발 동물

extension Quadruped {
    static let cat = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xF4A259), belly: NSColor(hex: 0xFFE9CF),
                                  dark: NSColor(hex: 0xB86A2E)),
        snout: (CGPoint(2.6, 1.2), 1.7, 1.25),
        decorate: { s, a in
            guard a.pose.activity != .sleep else { return }
            // 등 줄무늬와 수염
            for k in 0..<3 {
                let x = -a.bodyRx * 0.45 + CGFloat(k) * 1.9
                s.detailCurve(a.body.point(x, -a.bodyRy * 0.98), control: a.body.point(x + 0.7, -a.bodyRy * 0.55),
                              a.body.point(x + 0.2, -a.bodyRy * 0.2), width: 0.7, .dark)
            }
            let muzzle = a.headPoint(a.headRx * 0.85, a.headRy * 0.3)
            s.detailLine([muzzle, muzzle + CGPoint(2.2, -0.5)], width: 0.2, .ink)
            s.detailLine([muzzle + CGPoint(0, 0.4), muzzle + CGPoint(2.2, 0.6)], width: 0.2, .ink)
        }
    )

    // MARK: 호랑이, 너구리, 곰, 양, 검은 고양이, 황금 고양이

    static let tiger = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xF08A24), belly: NSColor(hex: 0xFFF1DC),
                                  dark: NSColor(hex: 0x2B1D14)),
        bodyRx: 6.5, bodyRy: 3.7,
        legLength: 5.2, legWidth: 2.4,
        headRx: 4.6, headRy: 4.0,
        snout: (CGPoint(2.6, 1.3), 1.9, 1.35),
        ears: .round, tail: .curl, tailLength: 9.5,
        decorate: { s, a in
            guard a.pose.activity != .sleep else { return }
            for k in 0..<5 {
                let x = -a.bodyRx * 0.75 + CGFloat(k) * 1.75
                s.detailCurve(a.body.point(x, -a.bodyRy * 0.98), control: a.body.point(x + 0.7, -a.bodyRy * 0.4),
                              a.body.point(x + 0.1, a.bodyRy * 0.15), width: 0.85, .dark)
            }
            s.detailLine([a.headPoint(-a.headRx * 0.15, -a.headRy * 0.9), a.headPoint(0, -a.headRy * 0.5)], width: 0.6, .dark)
            s.detailLine([a.headPoint(-a.headRx * 0.45, -a.headRy * 0.75), a.headPoint(-a.headRx * 0.3, -a.headRy * 0.45)],
                         width: 0.5, .dark)
        }
    )

    static let raccoon = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0x9A9AA6), belly: NSColor(hex: 0xE9E9EE),
                                  dark: NSColor(hex: 0x34313D)),
        bodyRx: 6.0, bodyRy: 3.5,
        legLength: 4.6, legWidth: 2.2,
        headRx: 4.4, headRy: 3.8,
        snout: (CGPoint(2.8, 1.2), 1.9, 1.2),
        ears: .round, tail: .bushy, tailLength: 8,
        legRole: .dark, earRole: .dark,
        decorate: { s, a in
            // 눈가 검은 띠
            s.detailEllipse(a.headPoint(a.headRx * 0.32, -a.headRy * 0.08), 1.9, 1.05, rotation: a.headTilt + 0.15, .dark)
            s.detailEllipse(a.headPoint(a.headRx * 0.1, -a.headRy * 0.5), 1.6, 0.5, rotation: a.headTilt, .belly)
        }
    )

    static let bear = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0x8D5B3A), belly: NSColor(hex: 0xD9B48F),
                                  dark: NSColor(hex: 0x4A2E1E)),
        bodyRx: 7.0, bodyRy: 4.2,
        legLength: 4.6, legWidth: 2.8,
        headRx: 4.6, headRy: 4.2,
        snout: (CGPoint(2.7, 1.3), 2.0, 1.5),
        ears: .round, tail: .puff,
        decorate: { s, a in
            guard a.pose.activity != .sleep else { return }
            s.detailEllipse(a.body.point(a.bodyRx * 0.5, a.bodyRy * 0.25), 2.2, 1.9, .belly)
        }
    )

    static let sheep = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xFBF8F1), belly: NSColor(hex: 0xFFFFFF),
                                  dark: NSColor(hex: 0x3C3842)),
        bodyRx: 6.2, bodyRy: 4.0,
        legLength: 4.8, legWidth: 1.8,
        headRx: 3.6, headRy: 3.4,
        snout: (CGPoint(2.4, 1.0), 1.6, 1.2),
        ears: .floppy, tail: .puff, legRole: .dark, earRole: .dark,
        overlay: { s, a in
            // 뭉게뭉게 털
            for k in 0..<5 {
                let x = -a.bodyRx * 0.75 + CGFloat(k) * a.bodyRx * 0.38
                s.circle(a.body.point(x, -a.bodyRy * 0.75), 1.7, .body)
            }
        },
        decorate: { s, a in
            s.detailEllipse(a.headPoint(a.headRx * 0.2, a.headRy * 0.1), 2.6, 2.2, rotation: a.headTilt, .dark)
            s.circle(a.headPoint(-a.headRx * 0.2, -a.headRy * 0.85), 1.3, .body)
        }
    )

    static let blackCat = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0x2C2833), belly: NSColor(hex: 0x4A4553),
                                  dark: NSColor(hex: 0x17151C), extra: NSColor(hex: 0xF2C14E)),
        snout: (CGPoint(2.6, 1.2), 1.7, 1.25),
        decorate: { s, a in
            guard a.pose.activity != .sleep else { return }
            let neck = a.headPoint(-a.headRx * 0.55, a.headRy * 0.75)
            s.detailEllipse(neck + CGPoint(0.3, 1.2), 0.65, 0.65, .extra)   // 방울
        }
    )

    static let goldenCat = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xF7C948), belly: NSColor(hex: 0xFFF4C2),
                                  dark: NSColor(hex: 0xC48A12), extra: NSColor(hex: 0xFFFFFF)),
        snout: (CGPoint(2.6, 1.2), 1.7, 1.25),
        decorate: { s, a in
            guard a.pose.activity != .sleep else { return }
            for k in 0..<3 {
                let x = -a.bodyRx * 0.45 + CGFloat(k) * 1.9
                s.detailCurve(a.body.point(x, -a.bodyRy * 0.98), control: a.body.point(x + 0.7, -a.bodyRy * 0.55),
                              a.body.point(x + 0.2, -a.bodyRy * 0.2), width: 0.7, .dark)
            }
            // 반짝임
            s.detailEllipse(a.body.point(-a.bodyRx * 0.2, -a.bodyRy * 0.55), 0.9, 0.35, rotation: -0.4, .extra)
            s.detailEllipse(a.headPoint(-a.headRx * 0.3, -a.headRy * 0.55), 0.7, 0.3, rotation: -0.4, .extra)
        }
    )

    static let dog = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xE0B07A), belly: NSColor(hex: 0xFFF3E2),
                                  dark: NSColor(hex: 0x8C5A3C), extra: NSColor(hex: 0xE5484D)),
        bodyRx: 6.4, bodyRy: 3.5,
        headRx: 4.2, headRy: 3.7,
        snout: (CGPoint(2.9, 1.0), 2.2, 1.55),
        ears: .floppy, tail: .stub, earRole: .dark,
        overlay: nil,
        decorate: { s, a in
            guard a.pose.activity != .sleep else { return }
            let neck = a.headPoint(-a.headRx * 0.55, a.headRy * 0.75)
            s.detailEllipse(neck, 0.8, 1.9, rotation: -0.5, .extra)
            s.detailEllipse(neck + CGPoint(0.3, 1.4), 0.6, 0.6, .horn)
        }
    )

    static let fox = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xF07B2C), belly: NSColor(hex: 0xFFF6EC),
                                  dark: NSColor(hex: 0x4A2C1F)),
        bodyRx: 6.0, bodyRy: 3.1,
        legLength: 6.6, legWidth: 1.8,
        headRx: 4.0, headRy: 3.5,
        snout: (CGPoint(3.0, 1.1), 2.3, 1.2),
        ears: .pointy(3.6), tail: .bushy, tailLength: 7.2,
        legRole: .dark,
        decorate: { s, a in
            s.detailEllipse(a.headPoint(a.headRx * 0.35, a.headRy * 0.55), 2.2, 1.2, rotation: a.headTilt, .belly)
            if a.pose.activity != .sleep {
                s.detailEllipse(a.body.point(a.bodyRx * 0.62, a.bodyRy * 0.35), 1.7, 1.9, .belly)
            }
        }
    )

    static let panda = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xF7F7F5), belly: NSColor(hex: 0xFFFFFF),
                                  dark: NSColor(hex: 0x2E2B33)),
        bodyRx: 6.6, bodyRy: 3.9,
        legLength: 5.6, legWidth: 2.4,
        headRx: 4.4, headRy: 4.0,
        snout: (CGPoint(2.6, 1.3), 1.8, 1.4),
        ears: .round, tail: .puff, legRole: .dark, earRole: .dark,
        overlay: { s, a in
            guard a.pose.activity != .sleep else { return }
            s.ellipse(a.body.point(a.bodyRx * 0.45, -a.bodyRy * 0.05), 2.3, a.bodyRy * 1.02,
                      rotation: a.body.pitch + 0.15, .dark)
        },
        decorate: { s, a in
            s.detailEllipse(a.headPoint(a.headRx * 0.33, -a.headRy * 0.05), 1.35, 1.65, rotation: 0.5, .dark)
        }
    )

    static let unicorn = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xFDFAFF), belly: NSColor(hex: 0xFFFFFF),
                                  dark: NSColor(hex: 0xC9B5EC), horn: NSColor(hex: 0xFFCF4D),
                                  pink: NSColor(hex: 0xFF8BC6), extra: NSColor(hex: 0xA98BFF)),
        bodyRx: 6.0, bodyRy: 3.3,
        legLength: 6.0, legWidth: 2.0,
        headRx: 3.9, headRy: 3.3,
        headOffset: CGPoint(6.6, -5.4), headTilt: 0.3,
        snout: (CGPoint(2.7, 1.0), 2.0, 1.6),
        ears: .pointy(2.2), tail: .wisp, tailLength: 7.5,
        decorate: { s, a in
            // 뿔
            let base = a.headEdge(-62, -0.4)
            let tipAngle = -1.15 + a.headTilt * 0.6
            let tip = base + CGPoint.polar(tipAngle, 4.4)
            let side = CGPoint.polar(tipAngle + .pi / 2, 0.9)
            s.polygon([base + side, tip, base - side], round: 0.2, .horn)
            for k in 1...2 {
                let p = base + (tip - base) * (CGFloat(k) * 0.3)
                s.detailLine([p + side * 0.7, p - side * 0.5 + (tip - base) * 0.08], width: 0.3, .dark)
            }
            // 갈기
            let u = a.pose.cycle
            let flow: CGFloat = a.pose.activity == .run ? 0.35 : 0.12
            // 갈기: 정수리 뒤에서 목을 따라 뒤로 흘러내린다
            for k in 0..<4 {
                let root = a.headEdge(-120 - CGFloat(k) * 20, -0.5)
                var points = [root]
                var angle: CGFloat = 2.75 + CGFloat(k) * 0.12
                for i in 1...5 {
                    angle += 0.1 + flow * 0.3 * sin(tau * u - CGFloat(i) * 0.7 - CGFloat(k))
                    points.append(points[i - 1] + CGPoint.polar(angle, 1.1))
                }
                s.tapered(points, from: 2.0, to: 0.5, k % 2 == 1 ? .extra : .pink)
            }
        }
    )

    static let hedgehog = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xEED2AE), belly: NSColor(hex: 0xFFF1DE),
                                  dark: NSColor(hex: 0x7A5136)),
        bodyRx: 6.4, bodyRy: 4.3,
        legLength: 3.2, legWidth: 1.8,
        headRx: 3.4, headRy: 3.0,
        headOffset: CGPoint(5.6, -0.6),
        snout: (CGPoint(2.6, 0.7), 2.0, 1.0),
        ears: .round, tail: .none, sitPitch: -0.35,
        overlay: { s, a in
            // 등 가시: 몸통 위쪽을 톱니 모양으로 덮는다
            var points: [CGPoint] = []
            let steps = 15
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let angle = (160 + t * 205) * CGFloat.pi / 180
                let r: CGFloat = i % 2 == 0 ? 1.04 : 1.36
                points.append(a.body.point(cos(angle) * a.bodyRx * r, sin(angle) * a.bodyRy * r))
            }
            points.append(a.body.point(a.bodyRx * 0.2, a.bodyRy * 0.2))
            points.append(a.body.point(-a.bodyRx * 0.75, a.bodyRy * 0.45))
            s.polygon(points, round: 0.25, .dark)
        }
    )

    /// 깡충깡충: 뒷다리를 같이 민다.
    static let rabbit = Quadruped(
        palette: CharacterPalette(body: NSColor(hex: 0xF3EEE9), belly: NSColor(hex: 0xFFFFFF),
                                  dark: NSColor(hex: 0xC8BDB3)),
        bodyRx: 5.6, bodyRy: 3.6,
        legLength: 4.6, legWidth: 2.0,
        headRx: 3.6, headRy: 3.4,
        headOffset: CGPoint(5.2, -3.6),
        snout: (CGPoint(2.4, 1.1), 1.3, 1.1),
        ears: .long, tail: .puff, hop: true, paw: 1.1
    )
}
