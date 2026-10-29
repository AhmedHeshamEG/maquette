import Foundation
import LoweyCore
import LoweyEngine

/// What a script asked of the app around the scene (`{"do": "app", …}`, M12), in order, after its command: the bridge
/// reaches what the menu bar reaches. The switch is over every `AppAsk.Op`, so a new op can't go unhandled.
extension EditorModel {
    func applyAppAsks(_ asks: [AppAsk]) {
        for ask in asks {
            apply(ask)
        }
    }

    /// One case per op (the compiler checks they're all handled).
    private func apply(_ ask: AppAsk) {
        let text = ask.value?.stringValue
        let flag = ask.on ?? ask.value?.boolValue
        switch ask.op {
        case .tool: if let text { chooseTool(text) }
        case .panel: if let text { openPanelNamed(text) }
        case .closePanel:
            openPanel = nil
            sheet = nil
        case .play: play()
        case .pause: pause()
        case .playhead: if let seconds = ask.value?.numberValue { setTime(seconds, snap: false) }
        case .undo: undo()
        case .redo: redo()
        case .present: startPresenting(text.flatMap(PresentKind.init(rawValue:)))
        case .stopPresenting: stopPresenting()
        case .notes: setNotesShown(flag ?? true)
        case .timeline: if (flag ?? true) != (timelinePresence != .hidden) { toggleTimeline() }
        case .directorView: setDirectorView(flag ?? true)
        case .hideInterface: chromeHidden = flag ?? true
        case .frameSelection:
            if let text, let id = baseScene.objects.values.first(where: { $0.name == text })?.id { select(id) }
            frameSelection()
        case .fly:
            if flag ?? true {
                startFlying()
            } else {
                stopFlying()
            }
        case .show: if let text { show(text, on: flag) }
        case .select: select(ask.value)
        case .export: if let text { exportFor(text) }
        case .ar:
            if flag ?? true, canShowAR {
                openAR()
            } else {
                closeAR()
            }
        case .monitor: ar.monitorRequested = true
        }
    }

    private func chooseTool(_ name: String) {
        switch name {
        case "model", "rig", "look", "library", "actions":
            openPanel = ClusterPanel(rawValue: name)
        case "draw": if tool != .draw { toggleDraw() }
        case "animate": if !animatesNow { toggleAnimate() }
        case "move", "turn", "size":
            tool = .select
            gizmoMode = name == "move" ? .move : name == "turn" ? .rotate : .scale
        case "precision":
            modelPage = .precision
            openPanel = .model
        case "shapeByTouch": chooseModelVerb(.shape)
        case "brushTheSurface": chooseModelVerb(.brush)
        case "cage": chooseModelVerb(.cage)
        case "bend": chooseModelVerb(.bend)
        default: if let stage = StageTool(rawValue: name) { tool = stage }
        }
    }

    private func openPanelNamed(_ name: String) {
        switch name {
        case "history": openHistory()
        case "board": openBoard()
        case "lensAndFrame": showsLensPanel = true
        default:
            if let panel = ClusterPanel(rawValue: name) {
                openPanel = panel
            } else if let named = EditorSheet(rawValue: name) {
                openPanel = nil
                sheet = named
            }
        }
    }

    private func show(_ what: String, on: Bool?) {
        switch what {
        case "ghosts": animate.ghosts = on ?? !animate.ghosts
        case "forces":
            physicsRun.showsArrows = on ?? !physicsRun.showsArrows
            refreshPhysicsOverlay()
        case "overhangs": guest.overhangs = on ?? !guest.overhangs
        case "dopeSheet": timelineStyle = (on ?? (timelineStyle != .dopeSheet)) ? .dopeSheet : .motion
        default: break
        }
    }

    private func select(_ value: JSONValue?) {
        switch value?.stringValue {
        case "all": selectAll()
        case "similar": selectSimilar()
        case "none": select(nil)
        default:
            let names = value?.arrayValue?.compactMap(\.stringValue) ?? value?.stringValue.map { [$0] } ?? []
            let ids = names.compactMap { name in baseScene.objects.values.first { $0.name == name }?.id }
            for (index, id) in ids.enumerated() {
                select(id, additive: index > 0)
            }
        }
    }

    /// An export into the project's renders, by a short name or an export preset's id.
    private func exportFor(_ name: String) {
        let short: [String: ExportPreset] = ["film": .hd1080, "vertical": .vertical, "still": .stillHD, "gif": .gifLoop, "glb": .gltfApps,
                                             "usdz": .usdzQuickLook, "obj": .objMaterials, "stl": .stlPrint, "3mf": .threeMFPrint,
                                             "blender": .blenderComputer, "fbx": .fbxUnity, "web": .threeFolder, "threejs": .threeFolder]
        guard let preset = short[name] ?? ExportPreset(rawValue: name) else {
            app.show("No export called “\(name)”", kind: .error)
            return
        }
        let settings = preset.settings(range: TimeRange(start: 0, end: timeline.duration), fps: timeline.fps, frame: timeline.frameShape)
        startExport(ExportJob(preset: preset, settings: settings))
    }
}
