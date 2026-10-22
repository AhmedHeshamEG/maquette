import HmmDesign
import LoweyCore
import RealityKit
import RoomPlan
import simd
import SwiftUI
import UIKit

// Room and object capture (G1), shared by the iPad's scan sheets and the iPhone companion (U8).

/// Holds the capture view (so the sheet's button can stop it) and the finished room.
@MainActor @Observable
final class RoomCaptureHolder {
    @ObservationIgnored var view: RoomCaptureView?
    var result: RoomScan?
}

struct RoomCaptureRepresentable: UIViewRepresentable {
    let holder: RoomCaptureHolder

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        holder.view = view
        view.captureSession.run(configuration: RoomCaptureSession.Configuration())
        return view
    }

    func updateUIView(_: RoomCaptureView, context _: Context) {}

    static func dismantleUIView(_ view: RoomCaptureView, coordinator _: RoomScanCoordinator) {
        view.captureSession.stop()
    }

    func makeCoordinator() -> RoomScanCoordinator { RoomScanCoordinator(holder: holder) }
}

/// RoomPlan's delegate: the finished room read into plain sizes and places, handed back on the main actor.
final class RoomScanCoordinator: NSObject, RoomCaptureViewDelegate {
    let holder: RoomCaptureHolder

    init(holder: RoomCaptureHolder) {
        self.holder = holder
        super.init()
    }

    required init?(coder _: NSCoder) { nil }

    func encode(with _: NSCoder) {}

    nonisolated func captureView(shouldPresent _: CapturedRoomData, error _: (any Error)?) -> Bool { true }

    nonisolated func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
        guard error == nil else { return }
        let scan = Self.scan(processedResult)
        let holder = holder
        Task { @MainActor in holder.result = scan }
    }

    nonisolated static func scan(_ room: CapturedRoom) -> RoomScan {
        func place(_ transform: simd_float4x4) -> (Vec3, Quat) {
            let q = simd_quatf(transform)
            return (Vec3(Double(transform.columns.3.x), Double(transform.columns.3.y), Double(transform.columns.3.z)),
                    Quat(x: Double(q.imag.x), y: Double(q.imag.y), z: Double(q.imag.z), w: Double(q.real)))
        }
        func surfaces(_ list: [CapturedRoom.Surface], _ kind: RoomScan.SurfaceKind) -> [RoomScan.Surface] {
            list.map { surface in
                let (position, rotation) = place(surface.transform)
                return RoomScan.Surface(kind: kind, position: position, rotation: rotation, width: Double(surface.dimensions.x),
                                        height: Double(surface.dimensions.y),
                                        corners: kind == .floor ? surface.polygonCorners.map { surface.transform.apply($0) } : nil)
            }
        }
        let items = room.objects.map { object in
            let (position, rotation) = place(object.transform)
            return RoomScan.Item(category: String(describing: object.category), position: position, rotation: rotation,
                                 size: Vec3(Double(object.dimensions.x), Double(object.dimensions.y), Double(object.dimensions.z)))
        }
        return RoomScan(surfaces: surfaces(room.walls, .wall) + surfaces(room.doors, .door) + surfaces(room.windows, .window)
            + surfaces(room.openings, .opening) + surfaces(room.floors, .floor), items: items)
    }
}

extension simd_float4x4 {
    /// A point of the surface's own space in the world.
    func apply(_ point: simd_float3) -> Vec3 {
        let world = self * simd_float4(point.x, point.y, point.z, 1)
        return Vec3(Double(world.x), Double(world.y), Double(world.z))
    }
}

/// Object Capture, start to finish (G1; the iPad's scan sheet and the iPhone companion, U8): walk round a thing on the
/// table, then the photos become a USDZ model at reduced detail, handed to `finished`.
struct ObjectCaptureFlow: View {
    let finished: (URL) -> Void
    let cancel: () -> Void
    @Environment(\.hmmTheme) private var theme
    @State private var session: ObjectCaptureSession?
    @State private var state = "Point at the object, then Start"
    @State private var making = false
    @State private var progress = 0.0
    @State private var folder = FileManager.default.temporaryDirectory.appendingPathComponent("Object scan \(UUID().uuidString)")

    static var isSupported: Bool { ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported }

    var body: some View {
        VStack(spacing: HmmSpacing.m) {
            if making {
                ProgressView(value: progress) { Text("Making the model") }.padding(HmmSpacing.l)
            } else if let session {
                ObjectCaptureView(session: session).ignoresSafeArea()
            }
            Text(LocalizedStringKey(state)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            HStack(spacing: HmmSpacing.s) {
                HmmPillButton("Start", systemName: "viewfinder") { start() }.accessibilityIdentifier("object-scan-start")
                HmmPillButton("Finish", systemName: "checkmark") { session?.finish() }.accessibilityIdentifier("object-scan-finish")
            }
            .disabled(making)
        }
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { session?.cancel(); cancel() } } }
        .task { await begin() }
    }

    private func begin() async {
        try? FileManager.default.createDirectory(at: folder.appendingPathComponent("Images"), withIntermediateDirectories: true)
        let session = ObjectCaptureSession()
        self.session = session
        session.start(imagesDirectory: folder.appendingPathComponent("Images"), configuration: ObjectCaptureSession.Configuration())
        for await update in session.stateUpdates {
            switch update {
            case .ready: state = "Point at the object, then Start"
            case .detecting: state = "Fit the box round it, then Start again"
            case .capturing: state = "Walk slowly round it; Finish when you've been all the way"
            case .completed:
                await makeModel()
                return
            case let .failed(error): state = error.localizedDescription
            default: break
            }
        }
    }

    private func start() {
        guard let session else { return }
        if case .ready = session.state {
            _ = session.startDetecting()
        } else if case .detecting = session.state {
            session.startCapturing()
        }
    }

    /// The photos made into a model on the iPad (reduced detail, what an iPad keeps smooth), then imported.
    private func makeModel() async {
        making = true
        let output = folder.appendingPathComponent("Scan.usdz")
        do {
            let maker = try PhotogrammetrySession(input: folder.appendingPathComponent("Images"))
            try maker.process(requests: [.modelFile(url: output, detail: .reduced)])
            for try await message in maker.outputs {
                switch message {
                case .requestProgress(_, fractionComplete: let fraction): progress = fraction
                case .processingComplete:
                    finished(output)
                    return
                case let .requestError(_, error): state = error.localizedDescription
                default: break
                }
            }
        } catch {
            state = error.localizedDescription
        }
        making = false
    }
}
