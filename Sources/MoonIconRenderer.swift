import Cocoa

enum MoonIconRenderer {
    static func image(
        pointSize: CGFloat,
        illumination: Double,
        relativeBrightness: Double,
        waxing: Bool
    ) -> NSImage {
        let size = max(16.0, pointSize)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = false
        let illum = max(0.0, min(1.0, illumination))
        let brightness = max(0.0, min(1.0, relativeBrightness))

        let pixels = max(48, Int(ceil(size * 3.0)))
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixels,
            pixelsHigh: pixels,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return image
        }

        rep.size = image.size

        // Sphere illumination model. phase illumination fixes the sun-observer
        // angle; waxing selects whether the bright limb is on the right or left.
        let sunObserverAngle = acos(max(-1.0, min(1.0, 2.0 * illum - 1.0)))
        let side = waxing ? 1.0 : -1.0
        let sunX = side * sin(sunObserverAngle)
        let sunZ = cos(sunObserverAngle)

        let center = (Double(pixels) - 1.0) * 0.5
        let radius = Double(pixels) * 0.46
        let perceptualLevel = 0.55 + 0.45 * pow(brightness, 0.45)
        let litAlpha = 0.72 + 0.28 * perceptualLevel
        let darkAlpha = 0.10
        let edgeAlpha = 0.78

        for py in 0..<pixels {
            for px in 0..<pixels {
                let x = (Double(px) - center) / radius
                let y = (Double(py) - center) / radius
                let r2 = x * x + y * y
                if r2 > 1.0 {
                    continue
                }

                let z = sqrt(max(0.0, 1.0 - r2))
                let isLit = (x * sunX + z * sunZ) >= 0.0
                let limbDistance = abs(sqrt(r2) - 1.0)
                let isLimb = limbDistance < 0.055

                if isLit {
                    rep.setColor(
                        NSColor.black.withAlphaComponent(CGFloat(litAlpha)),
                        atX: px,
                        y: py
                    )
                } else {
                    rep.setColor(
                        NSColor.black.withAlphaComponent(CGFloat(darkAlpha)),
                        atX: px,
                        y: py
                    )
                }

                if isLimb {
                    rep.setColor(
                        NSColor.black.withAlphaComponent(CGFloat(edgeAlpha)),
                        atX: px,
                        y: py
                    )
                }
            }
        }

        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    static func glyph(illumination: Double, waxing: Bool) -> String {
        let illum = max(0.0, min(1.0, illumination))

        if illum < 0.06 { return "○" }
        if illum > 0.94 { return "●" }
        if waxing {
            if illum < 0.40 { return "◔" }
            if illum < 0.62 { return "◐" }
            return "◕"
        }

        if illum < 0.40 { return "◕" }
        if illum < 0.62 { return "◑" }
        return "◔"
    }

}
