import ARKit
import HmmDesign
import HmmLink
import LoweyCore
import LoweyEngine
import Observation
import RealityKit
import RoomPlan
import SwiftUI
import UIKit

/// What the iPhone holds of its link to the iPad: how it stands, what the iPad asked for, and what came from it.
@MainActor @Observable
final class CompanionLink {
    private(set) var state: HmmLinkState = .off
    /// The mode on screen (the iPad's ask, or the person's own pick).
    var mode: CompanionMode?
    private(set) var presenting: PresentStatus?
    /// The scene for AR, saved as a file.
    private(set) var model: URL?
    @ObservationIgnored private let companion = HmmLinkCompanion(type: EditorModel.companionService)

    static var abilities: CompanionAbilities {
        CompanionAbilities(faceTracking: ARFaceTrackingConfiguration.isSupported, worldTracking: ARWorldTrackingConfiguration.isSupported,
                           roomScan: RoomCaptureSession.isSupported, objectScan: ObjectCaptureFlow.isSupported)
    }

    func start() {
        companion.onState = { [weak self] state in self?.changed(state) }
        companion.onFrame = { [weak self] data in self?.received(data) }
        companion.start()
    }

    func stop() {
        companion.stop()
    }

    func send(_ message: CompanionMessage) {
        guard let data = try? message.encoded() else { return }
        companion.send(data)
    }

    private func changed(_ state: HmmLinkState) {
        self.state = state
        if state.isConnected { send(.hello(name: UIDevice.current.name, abilities: Self.abilities)) }
    }

    private func received(_ data: Data) {
        guard let message = CompanionMessage.decode(data) else { return }
        switch message {
        case let .ask(mode): self.mode = mode
        case let .presenting(status): presenting = status
        case let .model(name, data): keep(name: name, data: data)
        case .done:
            mode = nil
            presenting = nil
        case .hello, .cameraPose, .remote, .roomScan, .objectScan, .trouble: break
        }
    }

    private func keep(name: String, data: Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AR \(UUID().uuidString)")
        let url = folder.appendingPathComponent(name.isEmpty ? "Scene" : name).appendingPathExtension("usdz")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            model = url
        } catch {
            model = nil
        }
    }
}

/// What the app shows on an iPhone (U8): the companion. It finds the iPad on the same Wi-Fi by itself; the iPad asks
/// for a mode and the phone switches to it, or the person picks one here.
public struct CompanionView: View {
    @State private var link = CompanionLink()
    @Environment(\.hmmTheme) private var theme

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if let mode = link.mode {
                    modeView(mode)
                        .navigationTitle(LocalizedStringKey(mode.title))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Back") { link.mode = nil } }
                        }
                } else {
                    home
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear {
            link.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            link.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var home: some View {
        List {
            SwiftUI.Section {
                HStack(spacing: HmmSpacing.s) {
                    Image(systemName: link.state.isConnected ? "ipad.landscape" : "wifi")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(link.state.isConnected ? theme.accent : theme.text3)
                    Text(verbatim: statusText).font(.hmm(.headline)).accessibilityIdentifier("companion-status")
                }
            } footer: {
                Text("Open \(AppIdentity.displayName) on your iPad, on the same Wi-Fi. The iPad picks what the iPhone does, or pick it here.")
            }
            SwiftUI.Section("Use this iPhone as") {
                ForEach(CompanionMode.allCases.filter { CompanionLink.abilities.can($0) }) { mode in
                    Button { link.mode = mode } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(mode.title)).foregroundStyle(theme.text)
                                Text(LocalizedStringKey(mode.subtitle)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
                            }
                        } icon: {
                            Image(systemName: mode.systemImage)
                        }
                    }
                    .accessibilityIdentifier("companion-\(mode.rawValue)")
                }
            }
        }
        .navigationTitle(AppIdentity.displayName)
    }

    private var statusText: String {
        switch link.state {
        case let .connected(name): String(localized: "With \(name)")
        case let .failed(reason): reason
        default: String(localized: "Looking for your iPad…")
        }
    }

    @ViewBuilder
    private func modeView(_ mode: CompanionMode) -> some View {
        switch mode {
        case .face: FaceCompanion()
        case .camera: PhoneCameraMode(link: link)
        case .remote: RemoteMode(link: link)
        case .augmented: AugmentedMode(link: link)
        case .roomScan:
            RoomScanMode { scan in
                link.send(.roomScan(scan))
                link.mode = nil
            }
        case .objectScan:
            ObjectCaptureFlow { url in
                if let data = try? Data(contentsOf: url) { link.send(.objectScan(name: String(localized: "Scan"), model: data)) }
                link.mode = nil
            } cancel: {
                link.mode = nil
            }
        }
    }
}

/// The iPhone as the scene's camera: its moves since Start go to the iPad (record them there, in Perform).
private struct PhoneCameraMode: View {
    let link: CompanionLink
    @State private var controller = VirtualCameraController()
    @State private var trouble: String?
    @State private var lastSent: CFTimeInterval = 0
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: HmmSpacing.l) {
            Image(systemName: "video").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(theme.accent)
            Text("Move the iPhone: the camera in the scene follows. Record the move on the iPad, in Perform.")
                .font(.hmm(.body)).multilineTextAlignment(.center).foregroundStyle(theme.text2)
            if let trouble { Text(verbatim: trouble).font(.hmm(.footnote)).foregroundStyle(theme.text2) }
            HmmPillButton("Start again from here", systemName: "arrow.counterclockwise") { restart() }
        }
        .padding(HmmSpacing.l)
        .onAppear(perform: restart)
        .onDisappear { controller.stop() }
    }

    private func restart() {
        controller.stop()
        controller.onPose = { pose in
            let now = CACurrentMediaTime()
            guard now - lastSent > 1.0 / 30 else { return }
            lastSent = now
            link.send(.cameraPose(pose))
        }
        controller.onFailure = { message in
            trouble = message
            link.send(.trouble(message))
        }
        controller.start()
    }
}

/// RoomPlan on the iPhone; the finished room goes to the iPad.
private struct RoomScanMode: View {
    let finished: (RoomScan) -> Void
    @State private var capture = RoomCaptureHolder()

    var body: some View {
        RoomCaptureRepresentable(holder: capture)
            .ignoresSafeArea()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if let result = capture.result {
                        Button("Send to the iPad") { finished(result) }
                    } else {
                        Button("Done scanning") { capture.view?.captureSession.stop() }
                    }
                }
            }
    }
}
