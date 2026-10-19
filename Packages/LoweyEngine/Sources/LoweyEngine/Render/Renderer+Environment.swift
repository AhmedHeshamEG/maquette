import LoweyCore
import Metal

extension LoweyRenderer {
    /// The HDRI's picture as a half-float texture (F1): read from the project's files the first time it's drawn, as wide
    /// as the device's tier keeps light (4096 on M-chips, 2048 elsewhere; a background, not a mirror). Nil without one.
    func environmentTexture(_ input: RenderInput) -> MTLTexture? {
        guard let key = input.document.effectiveLook.sky.environment else { return nil }
        let width = quality.tier == .a ? 4096 : 2048
        let cacheKey = "\(key)@\(width)"
        if let cached = environmentCache, cached.key == cacheKey { return cached.texture }
        guard let data = input.paintFile(key), let map = try? RadianceHDR.read(data, maxWidth: width),
              let texture = Self.halfTexture(map, device: device.device) else { return nil }
        environmentCache = (cacheKey, texture)
        return texture
    }

    static func halfTexture(_ map: RadianceHDR, device: MTLDevice) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: map.width, height: map.height,
                                                                  mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        var pixels = [Float16](repeating: 1, count: map.width * map.height * 4)
        for index in 0 ..< map.width * map.height {
            // Half floats top out at 65504: a sun's core is brighter still.
            pixels[index * 4] = Float16(min(map.pixels[index * 3], 65000))
            pixels[index * 4 + 1] = Float16(min(map.pixels[index * 3 + 1], 65000))
            pixels[index * 4 + 2] = Float16(min(map.pixels[index * 3 + 2], 65000))
        }
        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(region: MTLRegionMake2D(0, 0, map.width, map.height), mipmapLevel: 0, withBytes: base, bytesPerRow: map.width * 8)
        }
        return texture
    }

    /// The HDRI's switch, turn and exposure for the frame (off when its picture didn't load).
    static func environmentUniform(_ look: Look, loaded: Bool) -> SIMD4<Float> {
        guard loaded, look.sky.environment != nil else { return .zero }
        let turn = Float((look.sky.environmentTurn ?? 0) * .pi / 180)
        let exposure = Float(pow(2, (look.sky.environmentExposure ?? 0) + look.lighting.exposure))
        return SIMD4<Float>(1, turn, exposure, 0)
    }
}
