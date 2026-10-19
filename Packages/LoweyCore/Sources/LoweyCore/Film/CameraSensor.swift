import Foundation

public extension PropertyKey {
    /// The camera body the lens is on (F1): the focal length reads in its millimetres. The field of view stays the truth,
    /// so changing the body keeps the picture and changes the number.
    static let sensor: PropertyKey = "sensor"
}

/// Real camera bodies by their sensor's size against a full-frame one (the crop factor, by the diagonal). Maquette's
/// lens maths is full frame (`CameraLens.focalLength`); a body only changes what the millimetres say.
public enum CameraSensor: String, Codable, Sendable, CaseIterable, Identifiable {
    case fullFrame, super35, apsC, microFourThirds, super16, phone, largeFormat, imax

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fullFrame: "Full frame"
        case .super35: "Super 35 (cinema)"
        case .apsC: "APS-C"
        case .microFourThirds: "Micro Four Thirds"
        case .super16: "Super 16 (film)"
        case .phone: "Phone (main camera)"
        case .largeFormat: "Large format (65)"
        case .imax: "IMAX 70 mm"
        }
    }

    /// Full frame's diagonal (43.3 mm) over this sensor's.
    public var cropFactor: Double {
        switch self {
        case .fullFrame: 1
        case .super35: 43.27 / 31.11 // 24.89 × 18.66 mm
        case .apsC: 1.53 // 23.5 × 15.6 mm
        case .microFourThirds: 2
        case .super16: 43.27 / 14.54 // 12.52 × 7.41 mm
        case .phone: 24.0 / 6.86 // a 6.86 mm lens that shoots like a 24 mm
        case .largeFormat: 43.27 / 59.86 // 54.12 × 25.58 mm
        case .imax: 43.27 / 87.91 // 70.41 × 52.63 mm
        }
    }

    public static func of(_ camera: SceneObject) -> CameraSensor {
        camera[.sensor]?.stringValue.flatMap(CameraSensor.init(rawValue:)) ?? .fullFrame
    }
}

public extension CameraLens {
    /// The focal length on a body: the same picture, the body's own millimetres.
    func focalLength(on sensor: CameraSensor) -> Double { focalLength / sensor.cropFactor }

    static func fieldOfView(focalLength: Double, on sensor: CameraSensor) -> Double {
        fieldOfView(focalLength: focalLength * sensor.cropFactor)
    }
}

public extension PropertyKey {
    /// A soft panel's size in metres (F1).
    static let lightWidth: PropertyKey = "lightWidth"
    static let lightHeight: PropertyKey = "lightHeight"
}
