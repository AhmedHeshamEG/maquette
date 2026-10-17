import Foundation

/// The low-poly pieces parts are made of, built by our own code (the house kit's chunky, softly rounded, toy-scale look,
/// CONTEXT §10.9). Everything is counter-clockwise outward, in metres.
enum PartShapes {
    /// A profile revolved around y: `profile` runs top to bottom as (radius, height). A radius of 0 closes the end.
    static func lathe(_ profile: [(Double, Double)], segments: Int = 12) -> MeshData {
        var mesh = MeshData()
        let ring = segments + 1
        for (index, point) in profile.enumerated() {
            for segment in 0 ... segments {
                let theta = Double(segment) / Double(segments) * 2 * .pi
                let position = SIMD3<Float>(Float(sin(theta) * point.0), Float(point.1), Float(cos(theta) * point.0))
                mesh.addVertex(position, uv: SIMD2<Float>(Float(segment) / Float(segments), Float(index) / Float(max(profile.count - 1, 1))))
            }
        }
        for index in 0 ..< UInt32(profile.count - 1) {
            for segment in 0 ..< UInt32(segments) {
                let a = index * UInt32(ring) + segment
                let b = a + UInt32(ring)
                if profile[Int(index)].0 > 1e-9 { mesh.addTriangle(a, b, a + 1) }
                if profile[Int(index) + 1].0 > 1e-9 { mesh.addTriangle(a + 1, b, b + 1) }
            }
        }
        mesh.computeSmoothNormals()
        return mesh
    }

    /// A round-ended tube hanging down from its top (a limb's piece): `length` between the ends' middles.
    static func capsule(radius: Double, length: Double, bottomRadius: Double? = nil, segments: Int = 10) -> MeshData {
        let bottom = bottomRadius ?? radius
        var profile: [(Double, Double)] = []
        let steps = 4
        for step in 0 ... steps {
            let angle = Double(step) / Double(steps) * .pi / 2
            profile.append((radius * sin(angle), radius * cos(angle)))
        }
        for step in 0 ... steps {
            let angle = Double(step) / Double(steps) * .pi / 2
            profile.append((bottom * cos(angle), -length - bottom * sin(angle)))
        }
        return lathe(profile, segments: segments)
    }

    /// An ellipsoid of this size standing on its lowest point (y from 0 to `size.y`).
    static func ellipsoid(_ size: Vec3, segments: Int = 12, rings: Int = 8) -> MeshData {
        let profile = (0 ... rings).map { ring -> (Double, Double) in
            let phi = Double(ring) / Double(rings) * .pi
            return (0.5 * sin(phi), 0.5 + 0.5 * cos(phi))
        }
        return lathe(profile, segments: segments).transformed(Transform(scale: size))
    }

    /// An ellipsoid centred on its middle.
    static func centredEllipsoid(_ size: Vec3, segments: Int = 12, rings: Int = 8) -> MeshData {
        ellipsoid(size, segments: segments, rings: rings).transformed(Transform(position: Vec3(0, -size.y / 2, 0)))
    }

    /// A cone standing on its base.
    static func cone(radius: Double, height: Double, segments: Int = 10) -> MeshData {
        lathe([(0, height), (radius, 0), (0, 0)], segments: segments)
    }

    /// A box with its corners cut softly, standing on its base.
    static func block(_ size: Vec3, round: Double = 0.18) -> MeshData {
        let r = min(size.x, size.z) * round
        let hx = size.x / 2, hz = size.z / 2
        // An octagon in plan, lofted: the low-poly way to a soft box.
        let plan: [(Double, Double)] = [(hx - r, hz), (-hx + r, hz), (-hx, hz - r), (-hx, -hz + r), (-hx + r, -hz), (hx - r, -hz),
                                        (hx, -hz + r), (hx, hz - r)]
        return prism(plan, height: size.y)
    }

    /// A shape extruded up from an outline in x/z that runs counter-clockwise with x to the right and z up the page.
    static func prism(_ outline: [(Double, Double)], height: Double, bottom: Double = 0) -> MeshData {
        var mesh = MeshData()
        let count = outline.count
        func point(_ i: Int, _ y: Double) -> SIMD3<Float> {
            let p = outline[(i + count) % count]
            return SIMD3<Float>(Float(p.0), Float(y), Float(p.1))
        }
        for i in 0 ..< count {
            PrimitiveMesh.quad(&mesh, point(i + 1, bottom), point(i, bottom), point(i, bottom + height), point(i + 1, bottom + height))
        }
        let top = mesh.addVertex(SIMD3<Float>(0, Float(bottom + height), 0), normal: SIMD3<Float>(0, 1, 0))
        let base = mesh.addVertex(SIMD3<Float>(0, Float(bottom), 0), normal: SIMD3<Float>(0, -1, 0))
        for i in 0 ..< count {
            let a = mesh.addVertex(point(i, bottom + height), normal: SIMD3<Float>(0, 1, 0))
            let b = mesh.addVertex(point(i + 1, bottom + height), normal: SIMD3<Float>(0, 1, 0))
            mesh.addTriangle(top, b, a)
            let c = mesh.addVertex(point(i, bottom), normal: SIMD3<Float>(0, -1, 0))
            let d = mesh.addVertex(point(i + 1, bottom), normal: SIMD3<Float>(0, -1, 0))
            mesh.addTriangle(base, c, d)
        }
        return mesh
    }

    /// A flat slab from an outline in x/y (a wing, a fin, an ear), `thickness` deep, centred on z = 0.
    static func slab(_ outline: [(Double, Double)], thickness: Double) -> MeshData {
        // The outline in x/y becomes a prism in x/z, then turns up to face +z.
        let flipped = outline.map { ($0.0, -$0.1) }
        let ccw = signedArea(flipped) > 0 ? flipped : flipped.reversed()
        let prism = prism(ccw, height: thickness, bottom: -thickness / 2)
        return prism.transformed(Transform(rotation: Quat(angle: .pi / 2, axis: .unitX)))
    }

    static func signedArea(_ points: [(Double, Double)]) -> Double {
        var area = 0.0
        for i in points.indices {
            let a = points[i], b = points[(i + 1) % points.count]
            area += a.0 * b.1 - b.0 * a.1
        }
        // Positive when the outline runs counter-clockwise with x to the right and z up the page (what `prism` takes).
        return area / 2
    }

    /// Pieces joined into one mesh.
    static func joined(_ pieces: [MeshData]) -> MeshData {
        var mesh = MeshData()
        for piece in pieces {
            mesh.append(piece)
        }
        return mesh
    }
}
