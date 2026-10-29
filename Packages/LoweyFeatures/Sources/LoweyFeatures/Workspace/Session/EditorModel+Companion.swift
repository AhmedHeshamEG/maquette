import Foundation
import HmmDesign
import HmmLink
import LoweyCore
import LoweyEngine
import UIKit

/// The iPhone companion (U8), from the iPad's side: the iPad listens on the local network while the person wants the
/// phone for something (Actions ▸ Your iPhone, Present, the camera, a scan), and asks the phone for a mode; the phone
/// switches to it by itself. Face capture keeps its own link (`FaceLinkReceiver`).
extension EditorModel {
    static let companionService = "_maquette._tcp"

    /// Starts listening for the iPhone (the first time asks for the local network).
    func startCompanionLink() {
        guard Held.isOn(.companion), together.host == nil else { return }
        let host = HmmLinkHost(type: Self.companionService, name: UIDevice.current.name)
        host.onState = { [weak self] state in self?.phoneLinkChanged(state) }
        host.onFrame = { [weak self] data in self?.companionFrame(data) }
        together.host = host
        host.start()
    }

    func stopCompanionLink() {
        together.host?.stop()
        together.host = nil
        together.phone = nil
        together.asked = nil
        together.phoneLink = .off
        endPhoneCamera()
    }

    /// Wants the iPhone in `mode`: it switches as soon as it's there.
    func ask(_ mode: CompanionMode) {
        startCompanionLink()
        together.asked = mode
        sendToPhone(.ask(mode))
        if mode == .augmented { sendSceneToPhone() }
    }

    func sendToPhone(_ message: CompanionMessage) {
        guard let host = together.host, together.phoneLink.isConnected, let data = try? message.encoded() else { return }
        host.send(data)
    }

    private func phoneLinkChanged(_ state: HmmLinkState) {
        together.phoneLink = state
        if !state.isConnected {
            together.phone = nil
            endPhoneCamera()
        }
    }

    private func companionFrame(_ data: Data) {
        guard let message = CompanionMessage.decode(data) else { return }
        switch message {
        case let .hello(name, abilities):
            together.phone = CompanionPhone(name: name, abilities: abilities)
            if let asked = together.asked { ask(asked) }
            sendPresentStatus()
        case let .cameraPose(delta):
            phoneCameraMoved(delta)
        case let .remote(command):
            presentRemote(command)
        case let .roomScan(scan):
            addScannedRoom(scan)
            phoneJobDone("The room from your iPhone is in the scene")
        case let .objectScan(name, model):
            landPhoneModel(name: name, data: model)
        case let .trouble(text):
            app.show(String.LocalizationValue(text), kind: .error)
        case .ask, .presenting, .model, .done:
            break
        }
    }

    private func phoneJobDone(_ message: String.LocalizationValue) {
        together.asked = nil
        sendToPhone(.done)
        app.show(message)
    }

    private func landPhoneModel(name: String, data: Data) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("iPhone \(UUID().uuidString)")
        let url = folder.appendingPathComponent(ProjectStore.sanitize(name.isEmpty ? "Scan" : name)).appendingPathExtension("usdz")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            app.landModels([url])
            phoneJobDone("The object from your iPhone is in the Library and on the stage")
        } catch {
            app.show("Couldn't keep the scan: \(error.localizedDescription)", kind: .error)
        }
    }

    // MARK: The iPhone as the camera

    /// The scene's camera follows the iPhone (record in Perform, as with the iPad's own camera).
    func usePhoneAsCamera() {
        if editedCamera == nil { addCamera() }
        guard let camera = editedCamera else { return }
        stopVirtualCamera()
        setSelection([camera])
        together.phoneCameraStart = (camera, displayed.scene.worldTransform(of: camera))
        virtualCameraActive = true
        directorView = true
        updateStageClock()
        ask(.camera)
    }

    private func phoneCameraMoved(_ delta: CoreTransform) {
        guard let start = together.phoneCameraStart else { return }
        var pose = start.pose
        pose.position = start.pose.position + start.pose.rotation.act(delta.position * virtualCameraScale)
        pose.rotation = (start.pose.rotation * delta.rotation).normalized
        beginCameraTake(start.camera)
        performOverride[start.camera] = pose
        if !isPlaying { refreshDisplay() }
    }

    /// The iPhone stops being the camera (its Stop, the camera panel's, or the link dropping).
    func endPhoneCamera() {
        guard together.phoneCameraStart != nil else { return }
        together.phoneCameraStart = nil
        if together.asked == .camera {
            together.asked = nil
            sendToPhone(.done)
        }
        virtualCameraActive = false
        if performPhase == .idle {
            performOverride = [:]
            refreshDisplay()
        }
        updateStageClock()
    }

    // MARK: AR on the iPhone

    /// The scene as a USDZ model, to the iPhone's AR view.
    func sendSceneToPhone() {
        guard let file = modelFiles(.usdz, preset: .apps, selectionOnly: false, colors: .texture).first else { return }
        sendToPhone(.model(name: baseScene.name, data: file.data))
    }
}
