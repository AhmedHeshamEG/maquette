import Foundation

/// Where the sun is in the sky for a place and a moment: NOAA's solar position calculation (Jean Meeus, Astronomical
/// Algorithms), with atmospheric refraction. Good to a few hundredths of a degree between 1800 and 2100.
public enum SolarPosition {
    public struct Result: Hashable, Sendable {
        /// Degrees above the horizon (refraction included; negative at night).
        public var elevation: Double
        /// Compass degrees from north, clockwise (90 = east).
        public var azimuth: Double
    }

    /// `hour` is local clock time (e.g. 13.5); `utcOffset` the hours the clock is ahead of UTC (Rome in summer: 2).
    public static func at(latitude: Double, longitude: Double, year: Int, month: Int, day: Int, hour: Double, utcOffset: Double) -> Result {
        let julianDay = julian(year: year, month: month, day: day) + (hour - utcOffset) / 24
        let t = (julianDay - 2_451_545) / 36525
        let geomLong = normalized(280.46646 + t * (36000.76983 + t * 0.0003032))
        let anomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let centre = sin(rad(anomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t)) + sin(rad(2 * anomaly)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * anomaly)) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let apparent = geomLong + centre - 0.00569 - 0.00478 * sin(rad(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(rad(omega))
        let declination = deg(asin(sin(rad(obliquity)) * sin(rad(apparent))))
        let y = pow(tan(rad(obliquity / 2)), 2)
        let equationOfTime = 4 * deg(y * sin(2 * rad(geomLong)) - 2 * eccentricity * sin(rad(anomaly))
            + 4 * eccentricity * y * sin(rad(anomaly)) * cos(2 * rad(geomLong)) - 0.5 * y * y * sin(4 * rad(geomLong))
            - 1.25 * eccentricity * eccentricity * sin(2 * rad(anomaly)))
        let trueSolarMinutes = (hour * 60 + equationOfTime + 4 * longitude - 60 * utcOffset).truncatingRemainder(dividingBy: 1440)
        var hourAngle = trueSolarMinutes / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }
        let cosZenith = min(max(sin(rad(latitude)) * sin(rad(declination)) + cos(rad(latitude)) * cos(rad(declination)) * cos(rad(hourAngle)), -1), 1)
        let zenith = deg(acos(cosZenith))
        let azimuth = compassAzimuth(latitude: latitude, declination: declination, zenith: zenith, hourAngle: hourAngle)
        let elevation = 90 - zenith
        return Result(elevation: elevation + refraction(elevation), azimuth: azimuth)
    }

    static func compassAzimuth(latitude: Double, declination: Double, zenith: Double, hourAngle: Double) -> Double {
        let denominator = cos(rad(latitude)) * sin(rad(zenith))
        guard abs(denominator) > 1e-9 else { return latitude > 0 ? 180 : 0 }
        let cosine = min(max((sin(rad(latitude)) * cos(rad(zenith)) - sin(rad(declination))) / denominator, -1), 1)
        let angle = deg(acos(cosine))
        return hourAngle > 0 ? normalized(angle + 180) : normalized(540 - angle)
    }

    /// NOAA's approximation of how much the air lifts the sun's image near the horizon (degrees).
    static func refraction(_ elevation: Double) -> Double {
        guard elevation <= 85 else { return 0 }
        let tangent = tan(rad(elevation))
        let seconds: Double = if elevation > 5 {
            58.1 / tangent - 0.07 / pow(tangent, 3) + 0.000086 / pow(tangent, 5)
        } else if elevation > -0.575 {
            1735 + elevation * (-518.2 + elevation * (103.4 + elevation * (-12.79 + elevation * 0.711)))
        } else {
            -20.772 / tangent
        }
        return seconds / 3600
    }

    /// The Julian day at 0:00 UTC of a Gregorian date.
    static func julian(year: Int, month: Int, day: Int) -> Double {
        var y = year
        var m = month
        if m <= 2 {
            y -= 1
            m += 12
        }
        let a = y / 100
        let b = 2 - a + a / 4
        return Double(Int(365.25 * Double(y + 4716))) + Double(Int(30.6001 * Double(m + 1))) + Double(day) + Double(b) - 1524.5
    }

    static func rad(_ degrees: Double) -> Double { degrees * .pi / 180 }
    static func deg(_ radians: Double) -> Double { radians * 180 / .pi }
    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }
}

/// The real sun of a place on a date (Look ▸ World ▸ Sun ▸ Real sun). With a study, the time of day runs from `study`'s
/// start to its end across the timeline: a shadow study.
public struct RealSun: Codable, Hashable, Sendable {
    public var place: String
    public var latitude: Double
    public var longitude: Double
    /// Hours the clock is ahead of UTC.
    public var utcOffset: Double
    public var year: Int
    public var month: Int
    public var day: Int
    /// Local clock time, in hours (13.5 = half past one).
    public var hour: Double
    /// Which way north is on the stage, degrees around Y (0 = north is -Z, 90 = north is -X).
    public var north: Double
    /// A shadow study: the hours the timeline runs through (nil: one moment, `hour`).
    public var study: ClosedRange<Double>?

    public init(place: String, latitude: Double, longitude: Double, utcOffset: Double, year: Int, month: Int, day: Int, hour: Double,
                north: Double = 0, study: ClosedRange<Double>? = nil) {
        self.place = place
        self.latitude = latitude
        self.longitude = longitude
        self.utcOffset = utcOffset
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.north = north
        self.study = study
    }

    /// The clock time at a moment of a timeline `duration` seconds long.
    public func hour(at time: Double, duration: Double) -> Double {
        guard let study else { return hour }
        let progress = duration > 0 ? min(max(time / duration, 0), 1) : 0
        return study.lowerBound + (study.upperBound - study.lowerBound) * progress
    }

    public func position(at time: Double, duration: Double) -> SolarPosition.Result {
        SolarPosition.at(latitude: latitude, longitude: longitude, year: year, month: month, day: day,
                         hour: hour(at: time, duration: duration), utcOffset: utcOffset)
    }

    /// The Look's sun placed as the real one: its elevation, its azimuth on the stage (the Look measures from +Z toward
    /// +X; north is `north` degrees from -Z), and a sun that fades out below the horizon.
    public func apply(to lighting: inout Lighting, at time: Double, duration: Double) {
        let sun = position(at: time, duration: duration)
        lighting.sunElevation = max(sun.elevation, 0.5)
        lighting.sunAzimuth = SolarPosition.normalized(180 - sun.azimuth - north)
        let dusk = min(max((sun.elevation + 4) / 8, 0), 1)
        lighting.sunIntensity *= dusk * dusk * (3 - 2 * dusk)
    }

    /// A few places to start from (anyone can type coordinates).
    public static let places: [RealSun] = [
        RealSun(place: "Rome", latitude: 41.9028, longitude: 12.4964, utcOffset: 2, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "Cairo", latitude: 30.0444, longitude: 31.2357, utcOffset: 3, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "London", latitude: 51.5072, longitude: -0.1276, utcOffset: 1, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "New York", latitude: 40.7128, longitude: -74.006, utcOffset: -4, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "Los Angeles", latitude: 34.0522, longitude: -118.2437, utcOffset: -7, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "Tokyo", latitude: 35.6762, longitude: 139.6503, utcOffset: 9, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "Sydney", latitude: -33.8688, longitude: 151.2093, utcOffset: 10, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "Dubai", latitude: 25.2048, longitude: 55.2708, utcOffset: 4, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "São Paulo", latitude: -23.5558, longitude: -46.6396, utcOffset: -3, year: 2026, month: 6, day: 21, hour: 12),
        RealSun(place: "Mumbai", latitude: 19.076, longitude: 72.8777, utcOffset: 5.5, year: 2026, month: 6, day: 21, hour: 12)
    ]
}

/// The real sun placed on the shown scene's Look at a moment (a shadow study moves it across the timeline).
enum RealSunPlayback {
    static func apply(to scene: inout Scene, project: ProjectInfo, time: Double) {
        var look = scene.look ?? project.look
        guard let sun = look.lighting.realSun else { return }
        sun.apply(to: &look.lighting, at: time, duration: scene.timeline.duration)
        scene.look = look
    }
}
