import Foundation

/// The bridge reaches everything (M12, CONTEXT §12): every command a person can give from the menu bar (which carries
/// every action the keyboard reaches, `KeyCommands` in Features) has a bridge path: a Scene Script verb (and its op),
/// an app ask (`{"do": "app"}`, for what changes how the person sees the work rather than the work), or a laptop tool.
/// Tests walk it both ways: every command has a path (Features), and every path exists (Core: the verbs, their ops in
/// the schema, the tools in the skill's reference).
public enum BridgeCoverage {
    public enum Path: Hashable, Sendable {
        case verb(String, op: String? = nil)
        case app(AppAsk.Op, value: String? = nil)
        case tool(String)
    }

    /// Menu-bar command id → its bridge path.
    public static let commands: [String: Path] = [editCommands, toolsCommands, shapeCommands, textureCommands, lookCommands, physicsCommands,
                                                  characterCommands, kitCommands, sceneCommands, timelineCommands]
        .reduce(into: [:]) { all, part in all.merge(part) { $1 } }

    private static let editCommands: [String: Path] = [
        "edit.undo": .app(.undo), "edit.redo": .app(.redo), "edit.copy": .verb("duplicate"), "edit.paste": .verb("duplicate"),
        "edit.duplicate": .verb("duplicate"), "edit.delete": .verb("delete"), "edit.selectAll": .app(.select, value: "all"),
        "edit.selectSimilar": .app(.select, value: "similar"), "edit.group": .verb("group"), "edit.ungroup": .verb("command")
    ]

    private static let toolsCommands: [String: Path] = [
        "tools.model": .app(.tool, value: "model"), "tools.draw": .app(.tool, value: "draw"), "tools.rig": .app(.tool, value: "rig"),
        "tools.animate": .app(.tool, value: "animate"), "tools.actions": .app(.panel, value: "actions"),
        "tools.look": .app(.tool, value: "look"), "tools.lasso": .app(.tool, value: "lasso"), "tools.library": .tool("find_assets"),
        "tools.precision": .app(.tool, value: "precision"), "tools.solidShape": .verb("sketch"), "tools.frames": .verb("flipbook"),
        "tools.shadowBrush": .verb("paint", op: "color"), "tools.scatter": .verb("scatter"), "tools.move": .verb("transform"),
        "tools.turn": .verb("transform"), "tools.size": .verb("scaleTo")
    ]

    private static let shapeCommands: [String: Path] = [
        "shape.shapeByTouch": .verb("model", op: "pull"), "shape.brushTheSurface": .verb("model", op: "brush"),
        "shape.cage": .verb("model", op: "cage"), "shape.bend": .verb("model", op: "bend"), "shape.smoothMore": .verb("model", op: "smooth"),
        "shape.smoothLess": .verb("model", op: "smooth"), "shape.loopCut": .verb("model", op: "loopCut"),
        "shape.linkedCopy": .verb("model", op: "linkedCopy"), "shape.clone": .verb("design", op: "clone"),
        "shape.morphInto": .verb("design", op: "morph"), "shape.pivotToTheMiddle": .verb("model", op: "pivot")
    ]

    private static let textureCommands: [String: Path] = [
        "texture.paintFlat": .verb("paint", op: "color"), "texture.addDirt": .verb("paint", op: "wear"),
        "texture.addWornEdges": .verb("paint", op: "wear"), "texture.mirrorPaint": .verb("paint", op: "mirror"),
        "texture.fillFaces": .verb("paint", op: "faces")
    ]

    private static let lookCommands: [String: Path] = [
        "look.nextLook": .verb("look"), "look.previousLook": .verb("look"), "look.impactFrame": .verb("effect"),
        "look.focusLines": .verb("effect"), "look.kirbyDots": .verb("effect")
    ]

    private static let physicsCommands: [String: Path] = [
        "physics.makeReal": .verb("physics", op: "real"), "physics.notReal": .verb("physics", op: "unreal"),
        "physics.settle": .verb("physics", op: "settle"), "physics.doesItStand": .verb("physics", op: "stand"),
        "physics.keepTheRunAsKeys": .verb("physics", op: "keep"), "physics.showSpeedAndForces": .app(.show, value: "forces")
    ]

    private static let characterCommands: [String: Path] = [
        "character.newCharacter": .verb("character", op: "new"), "character.newPerson": .verb("character", op: "new"),
        "character.newFourLegged": .verb("character", op: "new"), "character.newCreatureFromNothing": .verb("character", op: "new"),
        "character.mirrorParts": .verb("character", op: "add"), "character.rigItAgain": .verb("character", op: "rig"),
        "character.exportForGames": .app(.export, value: "glb")
    ]

    private static let kitCommands: [String: Path] = [
        "kit.plansAndElevations": .app(.panel, value: "plans"), "kit.walkThrough": .app(.present, value: "walk"),
        "kit.matchAPhoto": .app(.panel, value: "matchPhoto"), "kit.bestWayUp": .verb("guest", op: "orient"),
        "kit.splitForPrinting": .verb("guest", op: "split"), "kit.hollow": .verb("guest", op: "hollow"),
        "kit.showOverhangs": .app(.show, value: "overhangs"), "kit.explode": .verb("guest", op: "explode"),
        "kit.freezeTransforms": .verb("guest", op: "freeze")
    ]

    private static let sceneCommands: [String: Path] = [
        "scene.frameSelection": .app(.frameSelection), "scene.directorView": .app(.directorView), "scene.flyTheCamera": .app(.fly),
        "scene.hideInterface": .app(.hideInterface), "scene.historyAndSteps": .verb("model", op: "steps"),
        "scene.export": .app(.export, value: "film"), "scene.closeTheLoop": .verb("design", op: "loop"),
        "scene.pasteASceneScript": .tool("build"), "scene.aiLaptopBridge": .tool("status"), "scene.scripts": .tool("build"),
        "scene.referenceWindow": .verb("reference", op: "open"), "scene.newMonitorWindow": .app(.monitor),
        "scene.present": .app(.present, value: "film"), "scene.notes": .verb("note", op: "list"),
        "scene.yourIPhone": .app(.panel, value: "phone"), "scene.viewInAR": .app(.ar), "scene.shareForAR": .app(.export, value: "usdz")
    ]

    private static let timelineCommands: [String: Path] = [
        "timeline.showTimeline": .app(.timeline), "timeline.playPause": .app(.play), "timeline.keyTheSelection": .verb("key"),
        "timeline.recordAPerformance": .verb("keys"), "timeline.addMarker": .verb("marker"), "timeline.audioWords": .tool("add_media"),
        "timeline.transcript": .verb("transcript"), "timeline.recordVoiceover": .tool("add_media"), "timeline.selectAllKeys": .verb("keys"),
        "timeline.keysAfterThePlayhead": .verb("keys"), "timeline.keysAtThePlayhead": .verb("keys"),
        "timeline.drawAPath": .verb("motion", op: "path"), "timeline.lookAt": .verb("motion", op: "lookAt"),
        "timeline.pickUpOrHandOff": .verb("motion", op: "pickUp"), "timeline.evenSpeed": .verb("motion", op: "evenSpeed"),
        "timeline.ghosts": .app(.show, value: "ghosts"), "timeline.dopeSheet": .app(.show, value: "dopeSheet"),
        "timeline.lensAndFrame": .verb("film", op: "lens"), "timeline.focusOnTheSelection": .verb("film", op: "focus"),
        "timeline.pullFocusToTheSelection": .verb("film", op: "focus"), "perform.microphone": .verb("lipSync")
    ]

    /// What the Add page makes (shapes, lights, effects, forces, fluids, the frame's marks, web pieces) → its verb.
    public static let making: [String: Path] = [
        "shape": .verb("add"), "light": .verb("light"), "particles": .verb("particles"), "force": .verb("physics", op: "force"),
        "fluid": .verb("physics", op: "fluid"), "overlay": .verb("overlay"), "text3D": .verb("text"), "media": .tool("add_media"),
        "logo": .verb("design", op: "logo"), "web": .verb("web", op: "add"), "character": .verb("character", op: "new"),
        "camera": .verb("camera"), "note": .verb("note", op: "add")
    ]

    /// Every verb a path names.
    public static var verbs: Set<String> {
        Set((Array(commands.values) + Array(making.values)).compactMap { path in
            if case let .verb(verb, _) = path { return verb }
            return nil
        })
    }

    /// Every laptop tool a path names.
    public static var tools: Set<String> {
        Set((Array(commands.values) + Array(making.values)).compactMap { path in
            if case let .tool(tool) = path { return tool }
            return nil
        })
    }
}
