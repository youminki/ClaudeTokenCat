import AppKit

/// drawingHandler 기반 NSImage를 비트맵으로 1회 래스터라이즈.
/// 프레임은 Core Animation 레이어에 넘겨 재생하므로 그리기는 상태가 바뀔 때 한 번만 일어난다 (§4 성능 예산).
/// labelColor 등 동적 색상은 래스터라이즈 시점의 appearance로 고정되므로,
/// 테마 변경 시 SpriteAnimator가 캐시를 비우고 다시 만든다.
enum SpriteRasterizer {

    /// `zoom`이 1보다 크면 위쪽 가운데를 기준으로 확대해 그리고, 칸 밖으로 나간 아래쪽은 잘린다.
    static func rasterize(_ image: NSImage, size: NSSize,
                          appearance: NSAppearance?, scale: CGFloat = 2, zoom: CGFloat = 1) -> NSImage {
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
        let rect = NSRect(x: size.width * (1 - zoom) / 2, y: size.height * (1 - zoom),
                          width: size.width * zoom, height: size.height * zoom)
        let draw = { image.draw(in: rect) }
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

    /// 레이어에 넘길 CGImage.
    static func cgImage(_ image: NSImage, size: NSSize, appearance: NSAppearance?, scale: CGFloat = 2,
                        zoom: CGFloat = 1) -> CGImage? {
        let raster = rasterize(image, size: size, appearance: appearance, scale: scale, zoom: zoom)
        return (raster.representations.first as? NSBitmapImageRep)?.cgImage
    }
}
