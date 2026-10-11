import Foundation

/// The sheet (CONTEXT §10.10): in 3D there is always one see-through sheet under the Pencil, so a stroke knows its
/// depth. Hands place it (a finger-tap on a surface lays it there, in empty space it stands facing you there, its grip
/// pushes it nearer or farther); it takes four shapes; sheets that were drawn on are kept with the scene, named, and
/// flipbooks are drawn on them frame by frame.
///
/// Its frame: `origin` is the point it was placed at, local +z faces the person who placed it (its normal), +y is its
/// up. A sheet laid on an object lives in that object's space and rides along with it.
public struct DrawingSheet: Codable, Hashable, Sendable, Identifiable {
    /// The four shapes, chosen from the control on the sheet's edge (they were the nine "Draws on" buttons).
    public enum Shape: String, Codable, CaseIterable, Identifiable, Sendable {
        /// A flat sheet.
        case flat
        /// Wrapped around: a standing cylinder whose front passes through the origin.
        case around
        /// A dome: a sphere whose front passes through the origin.
        case dome
        /// Lying on an object's surface: strokes land on the surface itself.
        case onObject

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .flat: "Flat"
            case .around: "Around"
            case .dome: "Dome"
            case .onObject: "On the object"
            }
        }

        public var systemImage: String {
            switch self {
            case .flat: "square"
            case .around: "cylinder"
            case .dome: "circle.circle"
            case .onObject: "cube.transparent"
            }
        }
    }

    public var id: String
    public var name: String
    public var shape: Shape
    public var origin: Vec3
    public var rotation: Quat
    /// The object it lies on (its space; `onObject` draws on its surface). Nil: the world.
    public var object: ObjectID?
    /// Flat: the size shown (strokes still land past its edge). Around: `height` is the cylinder's.
    public var width: Double
    public var height: Double
    /// Around and dome: how tightly it curves.
    public var radius: Double

    public init(id: String, name: String, shape: Shape = .flat, origin: Vec3, rotation: Quat = .identity, object: ObjectID? = nil,
                width: Double = 2, height: Double = 1.5, radius: Double = 1) {
        self.id = id
        self.name = name
        self.shape = shape == .onObject && object == nil ? .flat : shape
        self.origin = origin
        self.rotation = rotation.normalized
        self.object = object
        self.width = max(width, 0.01)
        self.height = max(height, 0.01)
        self.radius = max(radius, 0.01)
    }

    // MARK: Where it is

    /// The sheet's frame in the world: its object's place (scale included for the point, not for the turn) composed
    /// with its own. Nil when its object is gone.
    public func worldFrame(in scene: Scene) -> (origin: Vec3, rotation: Quat)? {
        guard let object else { return (origin, rotation) }
        guard scene.objects[object] != nil else { return nil }
        let carrier = scene.worldTransform(of: object)
        return (carrier.apply(to: origin), (carrier.rotation * rotation).normalized)
    }

    /// The world axes: right, up, normal (towards the person who placed it).
    public func axes(in scene: Scene) -> (right: Vec3, up: Vec3, normal: Vec3)? {
        guard let frame = worldFrame(in: scene) else { return nil }
        return (frame.rotation.act(.unitX), frame.rotation.act(.unitY), frame.rotation.act(.unitZ))
    }

    // MARK: Landing a stroke

    /// Where a ray (from the eye through the Pencil's tip) lands on the sheet, facing the eye. `onObject` sheets land
    /// on the object's surface, which the caller raycasts (nil here).
    public func land(_ ray: Ray, in scene: Scene) -> SurfaceHit? {
        guard let frame = worldFrame(in: scene) else { return nil }
        let normal = frame.rotation.act(.unitZ)
        switch shape {
        case .flat, .onObject:
            guard shape == .flat else { return nil }
            return GuideSurface.intersectPlane(ray, origin: frame.origin, normal: normal)
        case .around:
            let up = frame.rotation.act(.unitY)
            return Self.intersectCylinder(ray, axisPoint: frame.origin - normal * radius, axis: up, radius: radius)
        case .dome:
            return GuideSurface.intersectSphere(ray, center: frame.origin - normal * radius, radius: radius)
        }
    }

    /// An infinite cylinder (any axis); the nearest crossing in front of the ray, its normal facing the ray.
    static func intersectCylinder(_ ray: Ray, axisPoint: Vec3, axis: Vec3, radius: Double) -> SurfaceHit? {
        let axis = axis.normalized
        let offset = ray.origin - axisPoint
        let direction = ray.direction - axis * ray.direction.dot(axis)
        let start = offset - axis * offset.dot(axis)
        let a = direction.lengthSquared
        guard a > 1e-12 else { return nil }
        let b = start.dot(direction)
        let c = start.lengthSquared - radius * radius
        let discriminant = b * b - a * c
        guard discriminant >= 0 else { return nil }
        let root = discriminant.squareRoot()
        for t in [(-b - root) / a, (-b + root) / a] where t > 1e-9 {
            let point = ray.point(at: t)
            let fromAxis = point - axisPoint
            var normal = (fromAxis - axis * fromAxis.dot(axis)).normalized
            if normal.dot(ray.direction) > 0 { normal = -normal }
            return SurfaceHit(point: point, normal: normal, distance: t)
        }
        return nil
    }

    // MARK: Coordinates on the sheet

    /// A point on (or near) the sheet in the sheet's own coordinates, in metres along its surface: flat (and on an
    /// object, its tangent plane) are across and up; around is the arc from the front and the height; a dome is the
    /// arcs across and up from the front. Flipbooks drawn on a sheet keep their strokes in these.
    public func surfaceCoordinates(of world: Vec3, in scene: Scene) -> Vec2? {
        guard let frame = worldFrame(in: scene) else { return nil }
        let local = frame.rotation.inverse.act(world - frame.origin)
        switch shape {
        case .flat, .onObject:
            return Vec2(local.x, local.y)
        case .around:
            return Vec2(atan2(local.x, local.z + radius) * radius, local.y)
        case .dome:
            let fromCenter = Vec3(local.x, local.y, local.z + radius)
            let length = max(fromCenter.length, 1e-12)
            let across = atan2(fromCenter.x, fromCenter.z)
            let up = asin(min(max(fromCenter.y / length, -1), 1))
            return Vec2(across * radius, up * radius)
        }
    }

    /// The world point at sheet coordinates (the inverse of `surfaceCoordinates`).
    public func worldPoint(at coordinates: Vec2, in scene: Scene) -> Vec3? {
        guard let frame = worldFrame(in: scene) else { return nil }
        return frame.origin + frame.rotation.act(localPoint(at: coordinates))
    }

    /// The point at sheet coordinates in the sheet's own frame.
    public func localPoint(at coordinates: Vec2) -> Vec3 {
        switch shape {
        case .flat, .onObject:
            return Vec3(coordinates.x, coordinates.y, 0)
        case .around:
            let angle = coordinates.x / radius
            return Vec3(radius * sin(angle), coordinates.y, radius * cos(angle) - radius)
        case .dome:
            let across = coordinates.x / radius, up = coordinates.y / radius
            return Vec3(radius * cos(up) * sin(across), radius * sin(up), radius * cos(up) * cos(across) - radius)
        }
    }

    // MARK: Placing it by hand

    /// A flat sheet lying on a surface where a finger tapped it (in `object`'s space when there is one), its up as
    /// close to the world's up as the surface allows (on a floor: away from the eye).
    public static func lying(on hit: SurfaceHit, object: ObjectID?, eye: Vec3, in scene: Scene, id: String, name: String,
                             size: Double) -> DrawingSheet {
        let normal = hit.normal.normalized
        let worldRotation = frame(normal: normal, up: preferredUp(normal: normal, eye: eye, point: hit.point))
        var sheet = DrawingSheet(id: id, name: name, origin: hit.point, rotation: worldRotation, width: size, height: size * 0.75,
                                 radius: size / 2)
        if let object, scene.objects[object] != nil {
            let carrier = scene.worldTransform(of: object)
            sheet.object = object
            sheet.origin = carrier.inverseApply(to: hit.point)
            sheet.rotation = (carrier.rotation.inverse * worldRotation).normalized
        }
        return sheet
    }

    /// A flat sheet standing in empty space at `point`, facing the eye like an easel (upright); seen from steeply above
    /// or below it lies level instead.
    public static func facing(eye: Vec3, at point: Vec3, id: String, name: String, size: Double) -> DrawingSheet {
        let toEye = eye - point
        let level = Vec3(toEye.x, 0, toEye.z)
        let normal: Vec3 = if toEye.length < 1e-9 {
            .unitZ
        } else if level.length < toEye.length * 0.5 {
            toEye.y >= 0 ? .unitY : -Vec3.unitY
        } else {
            level.normalized
        }
        let rotation = frame(normal: normal, up: preferredUp(normal: normal, eye: eye, point: point))
        return DrawingSheet(id: id, name: name, origin: point, rotation: rotation, width: size, height: size * 0.75, radius: size / 2)
    }

    /// Pushed along its normal (towards the person who placed it for a positive distance).
    public func pushed(by distance: Double) -> DrawingSheet {
        var sheet = self
        sheet.origin += rotation.act(.unitZ) * distance
        return sheet
    }

    /// The same sheet in another shape (it keeps touching the same point; `onObject` only on an object).
    public func with(shape: Shape) -> DrawingSheet {
        var sheet = self
        sheet.shape = shape == .onObject && object == nil ? .flat : shape
        return sheet
    }

    /// Up for a sheet with this normal: the world's up laid onto it; on a floor or a ceiling, away from the eye.
    static func preferredUp(normal: Vec3, eye: Vec3, point: Vec3) -> Vec3 {
        let worldUp = Vec3.unitY - normal * normal.y
        if worldUp.length > 0.3 { return worldUp.normalized }
        let away = point - eye
        let along = away - normal * away.dot(normal)
        return along.length > 1e-6 ? along.normalized : (Vec3.unitZ - normal * normal.z).normalized
    }

    /// The turn whose +z is `normal` and whose +y is `up` (made square to the normal).
    public static func frame(normal: Vec3, up: Vec3) -> Quat {
        let z = normal.normalized
        let toNormal = Quat.rotation(from: .unitZ, to: z)
        var wanted = up - z * up.dot(z)
        if wanted.length < 1e-9 { wanted = toNormal.act(.unitY) }
        wanted = wanted.normalized
        let current = toNormal.act(.unitY)
        let angle = atan2(current.cross(wanted).dot(z), current.dot(wanted))
        return (Quat(angle: angle, axis: z) * toNormal).normalized
    }
}

/// Inserts, replaces or removes one kept sheet (`sheet == nil` removes).
public struct SheetEdit: Codable, Hashable, Sendable {
    public var id: String
    public var sheet: DrawingSheet?
    public var index: Int?

    public init(id: String, sheet: DrawingSheet?, index: Int? = nil) {
        self.id = id
        self.sheet = sheet
        self.index = index
    }

    public init(_ sheet: DrawingSheet) {
        self.init(id: sheet.id, sheet: sheet)
    }
}

public extension Scene {
    func sheet(_ id: String) -> DrawingSheet? { sheets.first { $0.id == id } }

    /// "Sheet 3": the next free number.
    func nextSheetName() -> String {
        let taken = Set(sheets.map(\.name))
        var number = sheets.count + 1
        while taken.contains("Sheet \(number)") {
            number += 1
        }
        return "Sheet \(number)"
    }
}
