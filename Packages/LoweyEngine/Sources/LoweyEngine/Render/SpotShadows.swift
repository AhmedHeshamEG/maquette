import simd

/// Spot lights' shadows (U9, the Real Look; any Look when a spot asks): the nearest spots that ask get a slice of the
/// spot shadow map each, drawn from the lamp's own point of view.
extension SceneCompiler {
    /// How many spots can cast a shadow in one frame.
    static let spotShadowSlots = 2

    /// Gives the first spots that ask (the lights are nearest first) a slice and the matrix that draws it.
    static func assignShadows(_ lights: [LightData]) -> [LightData] {
        var slot: Float = 0
        return lights.map { light in
            var light = light
            guard light.shadow.z > 0.5, light.color.w > 0.5, light.color.w < 1.5, slot < Float(spotShadowSlots) else {
                light.shadow.x = -1
                return light
            }
            light.shadow.x = slot
            light.shadowMatrix = spotMatrix(light)
            slot += 1
            return light
        }
    }

    /// The lamp's view: from its place along its direction, wide enough for its cone, out to its reach. Depth 0 (near) … 1.
    static func spotMatrix(_ light: LightData) -> simd_float4x4 {
        let eye = SIMD3<Float>(light.position.x, light.position.y, light.position.z)
        let forward = simd_normalize(SIMD3<Float>(light.direction.x, light.direction.y, light.direction.z))
        let up: SIMD3<Float> = abs(forward.y) > 0.99 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let view = ShadowCascades.lookAt(eye: eye, target: eye + forward, up: up)
        let halfAngle = acos(min(max(light.direction.w, -1), 1))
        let fieldOfView = min(halfAngle * 2 + 0.1, 2.9)
        let near: Float = 0.05
        let far = max(light.position.w, near + 0.1)
        let f = 1 / tan(fieldOfView / 2)
        let projection = simd_float4x4(columns: (
            SIMD4<Float>(f, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, near * far / (near - far), 0)
        ))
        return projection * view
    }
}
