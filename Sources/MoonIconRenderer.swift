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
            return NSColor(calibratedRed: 0.95, green: 0.83, blue: 0.29, alpha: 1.0)
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
            return "Show crater"
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
        let realMaria = [
            RealMoonMare(x: -0.42, y: -0.40, radiusX: 0.31, radiusY: 0.20, angle: -0.28, strength: 0.30),
            RealMoonMare(x: -0.10, y: -0.42, radiusX: 0.22, radiusY: 0.29, angle: -0.08, strength: 0.23),
            RealMoonMare(x: 0.50, y: -0.42, radiusX: 0.18, radiusY: 0.14, angle: 0.18, strength: 0.25),
            RealMoonMare(x: 0.04, y: -0.06, radiusX: 0.22, radiusY: 0.20, angle: 0.20, strength: 0.22),
            RealMoonMare(x: -0.30, y: 0.42, radiusX: 0.25, radiusY: 0.34, angle: -0.22, strength: 0.27),
            RealMoonMare(x: 0.14, y: 0.36, radiusX: 0.20, radiusY: 0.15, angle: 0.15, strength: 0.17),
            RealMoonMare(x: -0.70, y: 0.18, radiusX: 0.09, radiusY: 0.30, angle: -0.36, strength: 0.18)
        ]
        let realImpacts = [
            RealMoonImpact(x: 0.50, y: -0.42, radiusX: 0.20, radiusY: 0.15, angle: 0.16, strength: 0.18),
            RealMoonImpact(x: -0.67, y: 0.52, radiusX: 0.08, radiusY: 0.12, angle: -0.42, strength: 0.14),
            RealMoonImpact(x: -0.36, y: -0.08, radiusX: 0.12, radiusY: 0.10, angle: 0.28, strength: 0.10),
            RealMoonImpact(x: 0.28, y: 0.08, radiusX: 0.10, radiusY: 0.08, angle: -0.30, strength: 0.09)
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

                if isLit {
                    switch surfaceStyle {
                    case .none:
                        break
                    case .craters:
                        let rawTone = realCraterTone(atX: x, y: y, maria: realMaria, impacts: realImpacts)
                        let tone = adjustedCraterTone(rawTone, for: color)
                        if tone.shade > 0.0 || tone.highlight > 0.0 {
                            red = min(1.0, red * (1.0 - tone.shade) + rgb.red * tone.highlight)
                            green = min(1.0, green * (1.0 - tone.shade) + rgb.green * tone.highlight)
                            blue = min(1.0, blue * (1.0 - tone.shade) + rgb.blue * tone.highlight)
                            alpha = min(1.0, alpha + tone.alpha)
                        }
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

private struct RealMoonMare {
    let x: Double
    let y: Double
    let radiusX: Double
    let radiusY: Double
    let angle: Double
    let strength: Double
}

private struct RealMoonImpact {
    let x: Double
    let y: Double
    let radiusX: Double
    let radiusY: Double
    let angle: Double
    let strength: Double
}

private func realCraterTone(
    atX x: Double,
    y: Double,
    maria: [RealMoonMare],
    impacts: [RealMoonImpact]
) -> (shade: Double, highlight: Double, alpha: Double) {
    var shade = 0.0
    var highlight = 0.0
    var alpha = 0.0
    let surfaceGrain = 0.5 + 0.5 * sin((x * 39.0 + y * 21.0) * Double.pi)
        * sin((x * 13.0 - y * 31.0) * Double.pi)
    shade += max(0.0, surfaceGrain - 0.62) * 0.045
    highlight += max(0.0, 0.30 - surfaceGrain) * 0.050

    for mare in maria {
        let distance = ellipticalDistance(atX: x, y: y, featureX: mare.x, featureY: mare.y, radiusX: mare.radiusX, radiusY: mare.radiusY, angle: mare.angle)
        guard distance < 1.55 else { continue }

        let interior = exp(-pow(distance / 0.84, 2.2))
        let feather = exp(-pow((distance - 0.96) / 0.30, 2.0)) * 0.35
        let mottling = 0.88 + 0.12 * sin((x * 23.0 - y * 19.0 + mare.angle * 7.0) * Double.pi)
        shade += mare.strength * (interior + feather) * mottling
    }

    let lightX = -0.62
    let lightY = -0.78
    for impact in impacts {
        let dx = x - impact.x
        let dy = y - impact.y
        let cosAngle = cos(impact.angle)
        let sinAngle = sin(impact.angle)
        let rx = dx * cosAngle + dy * sinAngle
        let ry = -dx * sinAngle + dy * cosAngle
        let ux = rx / impact.radiusX
        let uy = ry / impact.radiusY
        let distance = sqrt(ux * ux + uy * uy)
        guard distance < 1.28 else { continue }

        let localLight = ux * lightX + uy * lightY
        let rim = exp(-pow((distance - 0.92) / 0.13, 2.0)) * impact.strength
        let bowl = exp(-pow(distance / 0.62, 2.0)) * impact.strength * 0.45
        shade += bowl + max(0.0, -localLight) * rim * 0.28
        highlight += max(0.0, localLight) * rim * 0.24
        alpha += min(0.020, (rim + bowl) * 0.04)
    }

    return (
        shade: min(0.46, shade),
        highlight: min(0.14, highlight),
        alpha: min(0.10, alpha)
    )
}

private func adjustedCraterTone(
    _ tone: (shade: Double, highlight: Double, alpha: Double),
    for color: MoonIconColor
) -> (shade: Double, highlight: Double, alpha: Double) {
    guard color == .yellow else {
        return tone
    }

    return (
        shade: min(0.34, tone.shade * 0.68),
        highlight: min(0.20, tone.highlight + tone.shade * 0.08),
        alpha: tone.alpha
    )
}

private func ellipticalDistance(
    atX x: Double,
    y: Double,
    featureX: Double,
    featureY: Double,
    radiusX: Double,
    radiusY: Double,
    angle: Double
) -> Double {
    let dx = x - featureX
    let dy = y - featureY
    let cosAngle = cos(angle)
    let sinAngle = sin(angle)
    let rx = dx * cosAngle + dy * sinAngle
    let ry = -dx * sinAngle + dy * cosAngle
    let ux = rx / radiusX
    let uy = ry / radiusY
    return sqrt(ux * ux + uy * uy)
}

private extension NSColor {
    var deviceRGBComponents: (red: Double, green: Double, blue: Double) {
        guard let rgb = usingColorSpace(.deviceRGB) else {
            return (1.0, 1.0, 1.0)
        }
        return (Double(rgb.redComponent), Double(rgb.greenComponent), Double(rgb.blueComponent))
    }
}
