import AppKit

/// drawingHandler 기반 NSImage를 비트맵으로 1회 래스터라이즈.
/// 프레임은 Core Animation 레이어에 넘겨 재생하므로 그리기는 상태가 바뀔 때 한 번만 일어난다 (§4 성능 예산).
/// labelColor 등 동적 색상은 래스터라이즈 시점의 appearance로 고정되므로,
/// 테마 변경 시 SpriteAnimator가 캐시를 비우고 다시 만든다.
enum SpriteRasterizer {

    /// 메뉴바 칸 픽셀 크기 그대로 그린 CGImage. `halo`를 주면 그림 바깥에 한 겹 테두리를 두른다.
    static func cgImage(_ image: NSImage, canvas: MenuBarCanvas, appearance: NSAppearance?,
                        halo: NSColor? = nil) -> CGImage? {
        let width = canvas.pixelWidth, height = canvas.pixelHeight
        guard width > 0, height > 0,
              let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        cg.scaleBy(x: canvas.pixelsPerPoint, y: canvas.pixelsPerPoint)
        cg.interpolationQuality = .high
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
        let draw = { image.draw(in: canvas.designRect) }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        NSGraphicsContext.restoreGraphicsState()
        if let halo, let pixels = cg.data?.bindMemory(to: UInt8.self, capacity: width * height * 4) {
            addHalo(pixels, width: width, height: height, color: halo, radius: canvas.haloRadius)
        }
        return cg.makeImage()
    }

    /// 그림 바깥으로 `radius` 픽셀 안에 있는 투명한 자리에 `color`를 깐다 (프리멀티플라이드 RGBA).
    /// 검은 머리처럼 메뉴바와 색이 비슷한 부분의 윤곽을 살린다.
    static func addHalo(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int, color: NSColor, radius: Int) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let a = rgb.alphaComponent
        let halo = [rgb.redComponent * a, rgb.greenComponent * a, rgb.blueComponent * a, a].map { $0 * 255 }
        let solid: UInt8 = 128
        let mask = (0..<width * height).map { pixels[$0 * 4 + 3] >= solid }
        // 그림이 있는 범위에서 테두리 두께만큼 넓힌 곳만 본다
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where mask[y * width + x] {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return }
        for y in max(minY - radius, 0)...min(maxY + radius, height - 1) {
            for x in max(minX - radius, 0)...min(maxX + radius, width - 1) where !mask[y * width + x] {
                var near = false
                search: for dy in -radius...radius {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -radius...radius where dx * dx + dy * dy <= radius * radius + 1 {
                        let nx = x + dx
                        if nx >= 0, nx < width, mask[ny * width + nx] { near = true; break search }
                    }
                }
                guard near else { continue }
                // 이미 칠해진 반투명 픽셀(가장자리 안티앨리어싱) 아래에 깐다
                let i = (y * width + x) * 4
                let keep = 1 - CGFloat(pixels[i + 3]) / 255
                for c in 0..<4 {
                    pixels[i + c] = UInt8(min(255, CGFloat(pixels[i + c]) + halo[c] * keep))
                }
            }
        }
    }
}
