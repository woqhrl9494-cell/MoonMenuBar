import Foundation

enum MoonMath {
    static let toRad = Double.pi / 180.0

    static func deg2rad(_ deg: Double) -> Double { deg * toRad }
    static func rad2deg(_ rad: Double) -> Double { rad / toRad }

    static func normalizeDeg(_ v: Double) -> Double {
        var x = v.truncatingRemainder(dividingBy: 360.0)
        if x < 0 { x += 360.0 }
        return x
    }

    static func normalizeRad(_ v: Double) -> Double {
        var x = v.truncatingRemainder(dividingBy: 2.0 * Double.pi)
        if x < 0 { x += 2.0 * Double.pi }
        return x
    }
}

struct MoonPhaseInfo {
    let ageDays: Double
    let phaseAngleRad: Double // 0...2π, 0 == new, π == full
    let illumination: Double // 0...1
    let relativeBrightness: Double // 0...1, full moon == 1
    let waxing: Bool
    let phaseName: String
}

struct MoonPositionInfo {
    let altitudeDeg: Double
    let azimuthDeg: Double
    let compassDirection: String
    let isAboveHorizon: Bool
}

struct MoonPhaseCalculator {
    static let synodicMonth: Double = 29.530588853
    private static let fullMoonMagnitude = -12.74

    struct LocationAwareTimeZone {
        let zone: TimeZone
    }

    static func phase(for date: Date, timeZone: TimeZone = .current) -> MoonPhaseInfo {
        // Lunar phase is an absolute geocentric quantity. Location changes the local
        // clock date and apparent tilt, but not the illuminated fraction itself.
        let jd = julianDateUTC(date)
        let lambdaSun = sunLongitude(jd: jd)
        let moon = moonEclipticCoordinates(jd: jd)

        let phaseDeg = MoonMath.normalizeDeg(moon.longitudeDeg - lambdaSun)
        let phaseRad = MoonMath.deg2rad(phaseDeg)
        let illum = max(0.0, min(1.0, (1.0 - cos(phaseRad)) * 0.5))
        let brightness = relativeBrightness(phaseAngleRad: phaseRad)

        let age = synodicAgeFromPhaseRadians(phaseRad)
        let phaseName = phaseNameFromAge(age)
        let waxing = phaseRad < Double.pi

        return MoonPhaseInfo(
            ageDays: age,
            phaseAngleRad: phaseRad,
            illumination: illum,
            relativeBrightness: brightness,
            waxing: waxing,
            phaseName: phaseName
        )
    }

    static func position(for date: Date, latitudeDeg: Double, longitudeDeg: Double) -> MoonPositionInfo {
        let jd = julianDateUTC(date)
        let T = (jd - 2451545.0) / 36525.0
        let moon = moonEclipticCoordinates(jd: jd)
        let lambda = MoonMath.deg2rad(moon.longitudeDeg)
        let beta = MoonMath.deg2rad(moon.latitudeDeg)
        let epsilon = MoonMath.deg2rad(23.439291 - 0.0130042 * T)

        let ra = atan2(
            sin(lambda) * cos(epsilon) - tan(beta) * sin(epsilon),
            cos(lambda)
        )
        let dec = asin(
            sin(beta) * cos(epsilon) + cos(beta) * sin(epsilon) * sin(lambda)
        )

        let gmst = MoonMath.normalizeDeg(
            280.46061837
            + 360.98564736629 * (jd - 2451545.0)
            + 0.000387933 * T * T
            - T * T * T / 38710000.0
        )
        let lst = MoonMath.normalizeDeg(gmst + longitudeDeg)
        let hourAngle = MoonMath.deg2rad(MoonMath.normalizeDeg(lst - MoonMath.rad2deg(ra)))
        let lat = MoonMath.deg2rad(latitudeDeg)

        let altitude = asin(
            sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(hourAngle)
        )
        let azimuth = atan2(
            -sin(hourAngle),
            tan(dec) * cos(lat) - sin(lat) * cos(hourAngle)
        )
        let azimuthDeg = MoonMath.normalizeDeg(MoonMath.rad2deg(azimuth))
        let altitudeDeg = MoonMath.rad2deg(altitude)

        return MoonPositionInfo(
            altitudeDeg: altitudeDeg,
            azimuthDeg: azimuthDeg,
            compassDirection: compassDirection(azimuthDeg),
            isAboveHorizon: altitudeDeg > 0.0
        )
    }

    private static func synodicAgeFromPhaseRadians(_ rad: Double) -> Double {
        (rad / (2.0 * Double.pi)) * synodicMonth
    }

    private static func relativeBrightness(phaseAngleRad: Double) -> Double {
        // Phase angle alpha is 0 at full moon and 180 at new moon.
        let alphaDeg = abs(180.0 - MoonMath.rad2deg(phaseAngleRad))
        let magnitude = fullMoonMagnitude + 0.026 * alphaDeg + 4.0e-9 * pow(alphaDeg, 4.0)
        return max(0.0, min(1.0, pow(10.0, -0.4 * (magnitude - fullMoonMagnitude))))
    }

    private static func sunLongitude(jd: Double) -> Double {
        let T = (jd - 2451545.0) / 36525.0
        let L0 = MoonMath.normalizeDeg(280.46646 + 36000.76983 * T + 0.0003032 * T * T)
        let M = MoonMath.normalizeDeg(357.52911 + 35999.05029 * T - 0.0001537 * T * T - 0.000000000244 * T * T * T)
        let C = (1.914602 - 0.004817 * T - 0.000014 * T * T) * sin(MoonMath.deg2rad(M))
                + (0.019993 - 0.000101 * T) * sin(2.0 * MoonMath.deg2rad(M))
                + 0.000289 * sin(3.0 * MoonMath.deg2rad(M))
        let omega = MoonMath.normalizeDeg(125.04 - 1934.136 * T)
        return MoonMath.normalizeDeg(L0 + C - 0.00569 - 0.00478 * sin(MoonMath.deg2rad(omega)))
    }

    private static func moonEclipticCoordinates(jd: Double) -> (longitudeDeg: Double, latitudeDeg: Double) {
        let T = (jd - 2451545.0) / 36525.0
        let L1 = MoonMath.normalizeDeg(218.3164477 + 481267.88123421 * T - 0.0015786 * T * T + 0.000001297 * T * T * T)
        let D = MoonMath.normalizeDeg(297.8501921 + 445267.1114034 * T - 0.0018819 * T * T + 0.00000191 * T * T * T)
        let M = MoonMath.normalizeDeg(357.52911 + 35999.05029 * T - 0.0001537 * T * T - 0.000000000244 * T * T * T)
        let M1 = MoonMath.normalizeDeg(134.9633964 + 477198.8675055 * T + 0.0087414 * T * T + 0.000014 * T * T * T)
        let F = MoonMath.normalizeDeg(93.2720950 + 483202.0175233 * T - 0.0036539 * T * T - 0.000001 * T * T * T)

        let dR = MoonMath.deg2rad(D)
        let mR = MoonMath.deg2rad(M)
        let m1R = MoonMath.deg2rad(M1)
        let fR = MoonMath.deg2rad(F)

        var longitude = L1
        longitude += 6.289 * sin(m1R)
        longitude += 1.274 * sin(2.0 * dR - m1R)
        longitude += 0.658 * sin(2.0 * dR)
        longitude += 0.214 * sin(2.0 * m1R)
        longitude -= 0.186 * sin(mR)
        longitude -= 0.114 * sin(2.0 * fR)
        longitude += 0.059 * sin(2.0 * dR - 2.0 * m1R)
        longitude += 0.057 * sin(2.0 * dR - mR - m1R)
        longitude += 0.053 * sin(2.0 * dR + m1R)

        var latitude = 0.0
        latitude += 5.128 * sin(fR)
        latitude += 0.280 * sin(m1R + fR)
        latitude += 0.277 * sin(m1R - fR)
        latitude += 0.173 * sin(2.0 * dR - fR)
        latitude += 0.055 * sin(2.0 * dR - m1R + fR)
        latitude += 0.046 * sin(2.0 * dR - m1R - fR)
        latitude += 0.033 * sin(2.0 * dR + fR)
        latitude += 0.017 * sin(2.0 * m1R + fR)

        return (MoonMath.normalizeDeg(longitude), latitude)
    }

    private static func compassDirection(_ azimuthDeg: Double) -> String {
        let directions = [
            "N", "NNE", "NE", "ENE",
            "E", "ESE", "SE", "SSE",
            "S", "SSW", "SW", "WSW",
            "W", "WNW", "NW", "NNW"
        ]
        let index = Int(floor((azimuthDeg + 11.25) / 22.5)).modulo(directions.count)
        return directions[index]
    }

    private static func phaseNameFromAge(_ ageDays: Double) -> String {
        switch ageDays {
        case 0..<1.84566:
            return "New Moon"
        case 1.84566..<5.53699:
            return "Waxing Crescent"
        case 5.53699..<9.22831:
            return "First Quarter"
        case 9.22831..<12.91963:
            return "Waxing Gibbous"
        case 12.91963..<16.61096:
            return "Full Moon"
        case 16.61096..<20.30228:
            return "Waning Gibbous"
        case 20.30228..<23.99361:
            return "Last Quarter"
        case 23.99361..<27.68493:
            return "Waning Crescent"
        default:
            return "New Moon"
        }
    }

    private static func julianDateUTC(_ date: Date) -> Double {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let comp = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        guard
            let year = comp.year,
            let month = comp.month,
            let day = comp.day,
            let hour = comp.hour,
            let minute = comp.minute,
            let second = comp.second
        else {
            return 0.0
        }

        let dayFraction = Double(hour) / 24.0 + Double(minute) / 1440.0 + Double(second) / 86400.0
        let d = Double(day) + dayFraction

        var y = year
        var m = month
        let dd = d

        if m <= 2 {
            y -= 1
            m += 12
        }

        let A = floor(Double(y) / 100.0)
        let B = 2.0 - A + floor(A / 4.0)
        let jd = floor(365.25 * Double(y + 4716)) + floor(30.6001 * Double(m + 1)) + dd + B - 1524.5
        return jd
    }
}

private extension Int {
    func modulo(_ n: Int) -> Int {
        let r = self % n
        return r >= 0 ? r : r + n
    }
}
