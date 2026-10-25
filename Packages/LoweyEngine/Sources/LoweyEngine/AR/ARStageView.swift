import ARKit
import LoweyCore
import MetalKit
import simd
import UIKit

/// The scene in the room (M12): the iPad's camera behind, the scene drawn over it by our own renderer, so its Look,
/// lights, paint and effects are the ones on the stage. A tap on a found floor or table puts it there; one finger moves
/// it along the surface, two turn it, a pinch sizes it (snapping to life size). Nothing is recorded and nothing leaves
/// the iPad.
@MainActor
public final class ARStageView: MTKView {
    /// The frame to draw for a drawable of this size (the stage's request; the camera, sky and ground are replaced).
    public var frameSource: ((CGSize) -> FrameRequest?)?
    /// Where the scene stands; nil until a tap places it.
    public var placement: ARPlacement? {
        didSet { onPlaced?(placement) }
    }

    /// Said when the placement changes (the screen's size buttons follow it).
    public var onPlaced: ((ARPlacement?) -> Void)?
    /// What the camera needs, in words ("Move the iPad slowly…"), or nil when it's tracking well.
    public var onGuidance: ((String?) -> Void)?
    /// The scene's bounds (for the table size).
    public var sceneBounds: Bounds?

    public let session = ARSession()
    private let renderDevice: RenderDevice
    private let renderer: LoweyRenderer
    private let compose: MTLRenderPipelineState
    private var textureCache: CVMetalTextureCache?
    private var sceneTexture: MTLTexture?
    private var coaching: ARCoachingOverlayView?
    private var lastGuidance: String?
    private var pinchStart = 1.0
    private var turnStart = 0.0

    public init(device: RenderDevice, quality: PreviewQuality = .current) throws {
        renderDevice = device
        renderer = try LoweyRenderer(device: device, quality: quality)
        let library = try device.device.makeLibrary(source: ARCompose.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "AR compose"
        descriptor.vertexFunction = library.makeFunction(name: "arVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "arFragment")
        descriptor.colorAttachments[0].pixelFormat = RenderDevice.outputFormat
        compose = try device.device.makeRenderPipelineState(descriptor: descriptor)
        super.init(frame: .zero, device: device.device)
        CVMetalTextureCacheCreate(nil, nil, device.device, nil, &textureCache)
        colorPixelFormat = RenderDevice.outputFormat
        depthStencilPixelFormat = .invalid
        framebufferOnly = false
        preferredFramesPerSecond = 60
        delegate = self
        isMultipleTouchEnabled = true
        session.delegate = self
        addGestures()
        accessibilityLabel = String(localized: "The scene in your room")
        accessibilityHint = String(localized: "Tap a floor or table to put the scene there")
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Whether this iPad can show it (a rear camera with world tracking).
    public static var isSupported: Bool {
        ARWorldTrackingConfiguration.isSupported
    }

    /// Starts the camera and the search for floors and tables.
    public func start() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        configuration.environmentTexturing = .none
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        showCoaching()
        isPaused = false
    }

    /// Stops the camera (the screen closes).
    public func stop() {
        session.pause()
        isPaused = true
        coaching?.removeFromSuperview()
        coaching = nil
        renderer.trimCaches()
    }

    /// Life size, or small enough for a table.
    public func setSize(lifeSize: Bool) {
        guard var placed = placement else { return }
        placed.scale = lifeSize ? 1 : ARPlacement.tableScale(for: sceneBounds)
        placement = placed
    }

    private func showCoaching() {
        let overlay = ARCoachingOverlayView()
        overlay.session = session
        overlay.goal = .horizontalPlane
        overlay.activatesAutomatically = true
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor), overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor), overlay.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        coaching = overlay
    }

    // MARK: Touch

    private func addGestures() {
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        let move = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
        move.maximumNumberOfTouches = 1
        addGestureRecognizer(move)
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinched(_:)))
        let turn = UIRotationGestureRecognizer(target: self, action: #selector(turned(_:)))
        pinch.delegate = self
        turn.delegate = self
        addGestureRecognizer(pinch)
        addGestureRecognizer(turn)
    }

    /// The room point on a found (or estimated) surface under a screen point.
    private func surface(at point: CGPoint) -> SIMD3<Float>? {
        guard let frame = session.currentFrame else { return nil }
        let query = frame.raycastQuery(from: point, allowing: .estimatedPlane, alignment: .horizontal)
        return session.raycast(query).first.map { SIMD3($0.worldTransform.columns.3.x, $0.worldTransform.columns.3.y, $0.worldTransform.columns.3.z) }
    }

    @objc private func tapped(_ gesture: UITapGestureRecognizer) {
        guard let spot = surface(at: gesture.location(in: self)) else { return }
        var placed = placement ?? ARPlacement(scale: ARPlacement.tableScale(for: sceneBounds))
        if placement == nil, let camera = session.currentFrame?.camera.transform {
            // Turned to face the iPad.
            placed.yaw = Double(atan2(camera.columns.3.x - spot.x, camera.columns.3.z - spot.z))
        }
        placed.position = Vec3(Double(spot.x), Double(spot.y), Double(spot.z))
        placement = placed
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @objc private func moved(_ gesture: UIPanGestureRecognizer) {
        guard var placed = placement, let spot = surface(at: gesture.location(in: self)) else { return }
        placed.position = Vec3(Double(spot.x), Double(spot.y), Double(spot.z))
        placement = placed
    }

    @objc private func pinched(_ gesture: UIPinchGestureRecognizer) {
        guard var placed = placement else { return }
        if gesture.state == .began { pinchStart = placed.scale }
        let wasLife = placed.isLifeSize
        placed.scale = ARPlacement(scale: pinchStart).pinched(Double(gesture.scale))
        if placed.isLifeSize, !wasLife { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        placement = placed
    }

    @objc private func turned(_ gesture: UIRotationGestureRecognizer) {
        guard var placed = placement else { return }
        if gesture.state == .began { turnStart = placed.yaw }
        placed.yaw = turnStart - Double(gesture.rotation)
        placement = placed
    }

    // MARK: Drawing

    private var interfaceOrientation: UIInterfaceOrientation {
        window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .landscapeRight
    }

    /// The scene's camera for this frame: the iPad's, carried into the scene's space.
    private func camera(for frame: ARFrame, size: CGSize) -> RenderCamera? {
        guard let placement else { return nil }
        let orientation = interfaceOrientation
        let pose = simd_inverse(frame.camera.viewMatrix(for: orientation))
        let rotation = simd_quatf(simd_float3x3(SIMD3(pose.columns.0.x, pose.columns.0.y, pose.columns.0.z),
                                                SIMD3(pose.columns.1.x, pose.columns.1.y, pose.columns.1.z),
                                                SIMD3(pose.columns.2.x, pose.columns.2.y, pose.columns.2.z)))
        let room = LoweyCore.Transform(position: Vec3(Double(pose.columns.3.x), Double(pose.columns.3.y), Double(pose.columns.3.z)),
                                       rotation: Quat(rotation))
        let local = placement.sceneCamera(room)
        let projection = frame.camera.projectionMatrix(for: orientation, viewportSize: size, zNear: 0.01, zFar: 1000)
        let fieldOfView = 2 * atan(1 / projection.columns.1.y) * 180 / .pi
        let depth = placement.sceneDepth(near: 0.01, far: 1000)
        return RenderCamera(position: local.position.float3, orientation: local.rotation.simd, fieldOfView: fieldOfView,
                            near: Float(depth.near), far: Float(depth.far))
    }

    private func planes(_ frame: ARFrame) -> (MTLTexture, MTLTexture)? {
        guard let cache = textureCache else { return nil }
        let buffer = frame.capturedImage
        func plane(_ index: Int, _ format: MTLPixelFormat) -> MTLTexture? {
            var made: CVMetalTexture?
            let width = CVPixelBufferGetWidthOfPlane(buffer, index), height = CVPixelBufferGetHeightOfPlane(buffer, index)
            CVMetalTextureCacheCreateTextureFromImage(nil, cache, buffer, nil, format, width, height, index, &made)
            return made.flatMap(CVMetalTextureGetTexture)
        }
        guard let luma = plane(0, .r8Unorm), let chroma = plane(1, .rg8Unorm) else { return nil }
        return (luma, chroma)
    }

    private func offscreen(_ size: CGSize) -> MTLTexture? {
        let width = Int(size.width), height = Int(size.height)
        if let sceneTexture, sceneTexture.width == width, sceneTexture.height == height { return sceneTexture }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: RenderDevice.outputFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        sceneTexture = renderDevice.device.makeTexture(descriptor: descriptor)
        return sceneTexture
    }
}

extension ARStageView: MTKViewDelegate {
    public func mtkView(_: MTKView, drawableSizeWillChange _: CGSize) {}

    public func draw(in _: MTKView) {
        guard let frame = session.currentFrame, let drawable = currentDrawable, let (luma, chroma) = planes(frame),
              let commandBuffer = renderDevice.queue.makeCommandBuffer() else { return }
        commandBuffer.label = "AR"
        let size = drawableSize
        var scene: MTLTexture?
        if let camera = camera(for: frame, size: bounds.size), var request = frameSource?(size), let target = offscreen(size) {
            request.camera = camera
            request.lens = nil
            request.transition = nil
            request.transparent = true
            request.overlay = nil
            request.flipbooks = []
            request.editor = nil
            if (try? renderer.encode(request, to: target, commandBuffer: commandBuffer)) != nil { scene = target }
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let display = frame.displayTransform(for: interfaceOrientation, viewportSize: bounds.size).inverted()
        var transform = [SIMD4<Float>(Float(display.a), Float(display.b), Float(display.c), Float(display.d)),
                         SIMD4<Float>(Float(display.tx), Float(display.ty), scene == nil ? 0 : 1, 0)]
        encoder.setRenderPipelineState(compose)
        encoder.setVertexBytes(&transform, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        encoder.setFragmentBytes(&transform, length: MemoryLayout<SIMD4<Float>>.stride * 2, index: 0)
        encoder.setFragmentTexture(luma, index: 0)
        encoder.setFragmentTexture(chroma, index: 1)
        encoder.setFragmentTexture(scene ?? luma, index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension ARStageView: @preconcurrency ARSessionDelegate {
    public func session(_: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let guidance: String? = switch camera.trackingState {
        case .normal: placement == nil ? String(localized: "Tap a floor or a table to put the scene there") : nil
        case .notAvailable: String(localized: "The camera can't see the room")
        case .limited(.excessiveMotion): String(localized: "Move the iPad more slowly")
        case .limited(.insufficientFeatures): String(localized: "Point the camera at something with more detail, in more light")
        case .limited: String(localized: "Move the iPad slowly to look around the room")
        }
        guard guidance != lastGuidance else { return }
        lastGuidance = guidance
        onGuidance?(guidance)
    }
}

extension ARStageView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }
}

/// The camera picture (full-range YCbCr) behind the scene's frame (premultiplied), in one pass.
enum ARCompose {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    struct Out { float4 position [[position]]; float2 view; float2 image; };
    vertex Out arVertex(uint id [[vertex_id]], constant float4 *t [[buffer(0)]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        Out out;
        out.position = float4(p * 2 - 1, 0, 1);
        out.view = float2(p.x, 1 - p.y);
        out.image = float2(t[0].x * out.view.x + t[0].z * out.view.y + t[1].x, t[0].y * out.view.x + t[0].w * out.view.y + t[1].y);
        return out;
    }
    fragment float4 arFragment(Out in [[stage_in]], constant float4 *t [[buffer(0)]], texture2d<float> luma [[texture(0)]],
                               texture2d<float> chroma [[texture(1)]], texture2d<float> scene [[texture(2)]]) {
        constexpr sampler linear(filter::linear, address::clamp_to_edge);
        float y = luma.sample(linear, in.image).r;
        float2 c = chroma.sample(linear, in.image).rg - 0.5;
        float3 camera = float3(y + 1.402 * c.y, y - 0.344136 * c.x - 0.714136 * c.y, y + 1.772 * c.x);
        float4 drawn = t[1].z > 0.5 ? scene.sample(linear, in.view) : float4(0);
        return float4(drawn.rgb + saturate(camera) * (1 - drawn.a), 1);
    }
    """
}
