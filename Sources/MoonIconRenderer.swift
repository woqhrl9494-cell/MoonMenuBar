import Cocoa

enum MoonIconColor: String, CaseIterable {
    case white
    case silver
    case ivory
    case yellow

    var menuTitle: String {
        switch self {
        case .white:
            return "White"
        case .silver:
            return "Silver"
        case .ivory:
            return "Ivory"
        case .yellow:
            return "Yellow"
        }
    }

    var baseColor: NSColor {
        switch self {
        case .white:
            return NSColor(calibratedRed: 1.00, green: 1.00, blue: 1.00, alpha: 1.0)
        case .silver:
            return NSColor(calibratedRed: 0.78, green: 0.82, blue: 0.88, alpha: 1.0)
        case .ivory:
            return NSColor(calibratedRed: 1.00, green: 0.93, blue: 0.74, alpha: 1.0)
        case .yellow:
            return NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.22, alpha: 1.0)
        }
    }
}

enum MoonSurfaceStyle: String, CaseIterable {
    case none
    case craters

    var menuTitle: String {
        switch self {
        case .none:
            return "None"
        case .craters:
            return "Show craters"
        }
    }
}

enum MoonIconRenderer {
    static func image(
        pointSize: CGFloat,
        illumination: Double,
        relativeBrightness: Double,
        waxing: Bool
    ) -> NSImage {
        image(
            pointSize: pointSize,
            illumination: illumination,
            relativeBrightness: relativeBrightness,
            waxing: waxing,
            color: .white,
            surfaceStyle: .none
        )
    }

    static func image(
        pointSize: CGFloat,
        illumination: Double,
        relativeBrightness: Double,
        waxing: Bool,
        color: MoonIconColor,
        surfaceStyle: MoonSurfaceStyle
    ) -> NSImage {
        let size = max(16.0, pointSize)
        let image = NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = false
        let illum = max(0.0, min(1.0, illumination))
        let brightness = max(0.0, min(1.0, relativeBrightness))
        let rgb = color.baseColor.deviceRGBComponents

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
        let craters: [(x: Double, y: Double, radius: Double, strength: Double)] = [
            (-0.43, -0.22, 0.33, 0.70),
            (0.20, -0.40, 0.28, 0.62),
            (-0.14, 0.44, 0.24, 0.56),
            (0.45, 0.12, 0.18, 0.44)
        ]

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
                let sphereShade = 0.88 + 0.12 * z

                var red = rgb.red * sphereShade
                var green = rgb.green * sphereShade
                var blue = rgb.blue * sphereShade
                var alpha = isLit ? litAlpha : darkAlpha

                if surfaceStyle == .craters, isLit {
                    let craterShade = craterStrength(atX: x, y: y, craters: craters)
                    if craterShade > 0.0 {
                        let shade = craterShade * 0.58
                        red *= 1.0 - shade
                        green *= 1.0 - shade
                        blue *= 1.0 - shade
                        alpha = min(1.0, alpha + craterShade * 0.12)
                    }
                }

                rep.setColor(
                    NSColor(
                        calibratedRed: CGFloat(red),
                        green: CGFloat(green),
                        blue: CGFloat(blue),
                        alpha: CGFloat(alpha)
                    ),
                    atX: px,
                    y: py
                )

                if isLimb {
                    rep.setColor(
                        NSColor(
                            calibratedRed: CGFloat(rgb.red),
                            green: CGFloat(rgb.green),
                            blue: CGFloat(rgb.blue),
                            alpha: CGFloat(edgeAlpha)
                        ),
                        atX: px,
                        y: py
                    )
                }
            }
        }

        image.addRepresentation(rep)
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

private func craterStrength(
    atX x: Double,
    y: Double,
    craters: [(x: Double, y: Double, radius: Double, strength: Double)]
) -> Double {
    var strength = 0.0
    for crater in craters {
        let dx = x - crater.x
        let dy = y - crater.y
        let distance = sqrt(dx * dx + dy * dy)
        guard distance < crater.radius else { continue }

        let normalized = distance / crater.radius
        let bowl = pow(1.0 - normalized, 0.75) * crater.strength
        let innerShadow = exp(-pow(normalized / 0.55, 2.0)) * crater.strength * 0.24
        strength += bowl + innerShadow
    }
    return min(0.58, strength)
}

private extension NSColor {
    var deviceRGBComponents: (red: Double, green: Double, blue: Double) {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return (1.0, 1.0, 1.0)
        }
        return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
    }
}
