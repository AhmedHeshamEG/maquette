import HmmDesign
import LoweyCore
import RealityKit
import RoomPlan
import simd
import SwiftUI
import UIKit

/// Room ▸ Scan a room (G1): Apple's RoomPlan with the LiDAR scanner walks the room, then its walls, doors, windows and
/// furniture land as the building. Offered only on iPads that can; the others scan with the iPhone companion (U8).
struct RoomScanSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var capture = RoomCaptureHolder()

    static var isSupported: Bool { RoomCaptureSession.isSupported }

    var body: some View {
        NavigationStack {
            RoomCaptureRepresentable(holder: capture)
                .ignoresSafeArea()
                .navigationTitle("Scan a room")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        if let result = capture.result {
                            Button("Add to the scene") {
                                editor.addScannedRoom(result)
                                dismiss()
                            }
                            .accessibilityIdentifier("scan-add")
                        } else {
                            Button("Done scanning") { capture.view?.captureSession.stop() }
                        }
                    }
                }
        }
    }
}

/// Model ▸ Edit ▸ 3D print ▸ Scan an object (G1): Apple's Object Capture walks round a thing on the table, the iPad
/// turns the photos into a model, and it lands in the Library and on the stage. Offered only where it can run.
struct ObjectScanSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss

    static var isSupported: Bool { ObjectCaptureFlow.isSupported }

    var body: some View {
        NavigationStack {
            ObjectCaptureFlow { url in
                editor.app.landModels([url])
                dismiss()
            } cancel: {
                dismiss()
            }
            .navigationTitle("Scan an object")
        }
    }
}
