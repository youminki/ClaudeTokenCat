import AppKit

/// drawingHandler 기반 NSImage를 비트맵으로 1회 래스터라이즈.
/// 프레임은 Core Animation 레이어에 넘겨 재생하므로 그리기는 상태가 바뀔 때 한 번만 일어난다 (§4 성능 예산).
/// labelColor 등 동적 색상은 래스터라이즈 시점의 appearance로 고정되므로,
/// 테마 변경 시 SpriteAnimator가 캐시를 비우고 다시 만든다.
enum SpriteRasterizer {

    /// `zoom`이 1보다 크면 칸을 그만큼 옆으로 넓히고, 바닥 조금 위를 기준으로 키워 위아래 여백만 줄인다.
    /// 출력 크기는 (size.width × zoom) × size.height다.
    static func rasterize(_ image: NSImage, size: NSSize,
                          appearance: NSAppearance?, scale: CGFloat = 2, zoom: CGFloat = 1) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((size.width * zoom * scale).rounded()), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: rep)
        else { return image }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)   // 포인트 좌표로 그리면 2x 픽셀로 기록 (레티나)
        // 선 자세는 바닥 아래 1pt, 머리 위 2.5pt가 비어 있다. 바닥에서 4pt 위를 고정점으로 두면
        // 1.12배에서 머리와 발이 모두 칸 안에 남는다 (점프·춤의 머리 위는 조금 잘린다)
        let pivot: CGFloat = 4
        let rect = NSRect(x: 0, y: pivot * (1 - zoom), width: size.width * zoom, height: size.height * zoom)
        let draw = { image.draw(in: rect) }
        if let appearance {
            appearance.performAsCurrentDrawingAppearance(draw)
        } else {
            draw()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let outputSize = NSSize(width: size.width * zoom, height: size.height)
        rep.size = outputSize
        let output = NSImage(size: outputSize)
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
