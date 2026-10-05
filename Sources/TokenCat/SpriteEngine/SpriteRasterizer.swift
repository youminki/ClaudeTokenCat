import AppKit

/// drawingHandler 기반 NSImage를 비트맵으로 1회 래스터라이즈.
/// 상태바가 40ms 프레임마다 핸들러를 재실행하지 않게 해 애니메이션 CPU를 낮춘다 (§4 성능 예산).
/// labelColor 등 동적 색상은 래스터라이즈 시점의 appearance로 고정되므로,
/// 테마 변경 시 SpriteAnimator가 캐시를 비우고 다시 만든다.
enum SpriteRasterizer {

    static func rasterize(_ image: NSImage, size: NSSize,
                          appearance: NSAppearance?, scale: CGFloat = 2) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)   // 포인트 좌표로 그리면 2x 픽셀로 기록 (레티나)
        let draw = { image.draw(in: NSRect(origin: .zero, size: size)) }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        rep.size = size
        let output = NSImage(size: size)
        output.addRepresentation(rep)
        return output
    }
}
