import HmmDesign

/// Every command the keyboard reaches (the menu bar), with the keys it comes with. Settings ▸ Keyboard gives any of them
/// other keys (U8); the ids are stored, so they never change. A Perform trigger's letter is the deck's, not here.
enum KeyCommands {
    static let editUndo = HmmKeyCommand("edit.undo", "Undo", menu: "Edit", HmmKeyCombo("z"))
    static let editRedo = HmmKeyCommand("edit.redo", "Redo", menu: "Edit", HmmKeyCombo("z", shift: true))
    static let editCopy = HmmKeyCommand("edit.copy", "Copy", menu: "Edit", HmmKeyCombo("c"))
    static let editPaste = HmmKeyCommand("edit.paste", "Paste", menu: "Edit", HmmKeyCombo("v"))
    static let editDuplicate = HmmKeyCommand("edit.duplicate", "Duplicate", menu: "Edit", HmmKeyCombo("d"))
    static let editDelete = HmmKeyCommand("edit.delete", "Delete", menu: "Edit", HmmKeyCombo("delete"))
    static let editSelectAll = HmmKeyCommand("edit.selectAll", "Select All", menu: "Edit", HmmKeyCombo("a"))
    static let editSelectSimilar = HmmKeyCommand("edit.selectSimilar", "Select Similar", menu: "Edit", HmmKeyCombo("a", shift: true))
    static let editGroup = HmmKeyCommand("edit.group", "Group", menu: "Edit", HmmKeyCombo("g"))
    static let editUngroup = HmmKeyCommand("edit.ungroup", "Ungroup", menu: "Edit", HmmKeyCombo("g", shift: true))
    static let toolsModel = HmmKeyCommand("tools.model", "Model", menu: "Tools", HmmKeyCombo("1"))
    static let toolsDraw = HmmKeyCommand("tools.draw", "Draw", menu: "Tools", HmmKeyCombo("2"))
    static let toolsRig = HmmKeyCommand("tools.rig", "Rig", menu: "Tools", HmmKeyCombo("3"))
    static let toolsAnimate = HmmKeyCommand("tools.animate", "Animate", menu: "Tools", HmmKeyCombo("4"))
    static let toolsActions = HmmKeyCommand("tools.actions", "Actions", menu: "Tools", HmmKeyCombo("6"))
    static let toolsLook = HmmKeyCommand("tools.look", "Look", menu: "Tools", HmmKeyCombo("7"))
    static let toolsLasso = HmmKeyCommand("tools.lasso", "Lasso", menu: "Tools", HmmKeyCombo("8"))
    static let toolsLibrary = HmmKeyCommand("tools.library", "Library", menu: "Tools", HmmKeyCombo("l"))
    static let toolsPrecision = HmmKeyCommand("tools.precision", "Precision", menu: "Tools", nil)
    static let toolsSolidShape = HmmKeyCommand("tools.solidShape", "Solid Shape", menu: "Tools", nil)
    static let toolsFrames = HmmKeyCommand("tools.frames", "Frames", menu: "Tools", nil)
    static let toolsShadowBrush = HmmKeyCommand("tools.shadowBrush", "Shadow Brush", menu: "Tools", nil)
    static let toolsScatter = HmmKeyCommand("tools.scatter", "Scatter", menu: "Tools", nil)
    static let toolsMove = HmmKeyCommand("tools.move", "Move", menu: "Tools", HmmKeyCombo("1", option: true))
    static let toolsTurn = HmmKeyCommand("tools.turn", "Turn", menu: "Tools", HmmKeyCombo("2", option: true))
    static let toolsSize = HmmKeyCommand("tools.size", "Size", menu: "Tools", HmmKeyCombo("3", option: true))
    static let shapeShapeByTouch = HmmKeyCommand("shape.shapeByTouch", "Shape by Touch", menu: "Shape", HmmKeyCombo("1", shift: true))
    static let shapeBrushTheSurface = HmmKeyCommand("shape.brushTheSurface", "Brush the Surface", menu: "Shape", HmmKeyCombo("2", shift: true))
    static let shapeCage = HmmKeyCommand("shape.cage", "Cage", menu: "Shape", HmmKeyCombo("3", shift: true))
    static let shapeBend = HmmKeyCommand("shape.bend", "Bend", menu: "Shape", HmmKeyCombo("4", shift: true))
    static let shapeSmoothMore = HmmKeyCommand("shape.smoothMore", "Smooth More", menu: "Shape", HmmKeyCombo("]"))
    static let shapeSmoothLess = HmmKeyCommand("shape.smoothLess", "Smooth Less", menu: "Shape", HmmKeyCombo("["))
    static let shapeLoopCut = HmmKeyCommand("shape.loopCut", "Loop Cut", menu: "Shape", HmmKeyCombo("r", control: true))
    static let shapeLinkedCopy = HmmKeyCommand("shape.linkedCopy", "Linked Copy", menu: "Shape", HmmKeyCombo("d", shift: true))
    static let shapeClone = HmmKeyCommand("shape.clone", "Clone", menu: "Shape", HmmKeyCombo("c", control: true))
    static let shapeMorphInto = HmmKeyCommand("shape.morphInto", "Morph Into…", menu: "Shape", HmmKeyCombo("o", control: true))
    static let shapePivotToTheMiddle = HmmKeyCommand("shape.pivotToTheMiddle", "Pivot to the Middle", menu: "Shape", nil)
    static let texturePaintFlat = HmmKeyCommand("texture.paintFlat", "Paint Flat", menu: "Texture", HmmKeyCombo("f", shift: true))
    static let textureAddDirt = HmmKeyCommand("texture.addDirt", "Add Dirt", menu: "Texture", HmmKeyCombo("w", option: true))
    static let textureAddWornEdges = HmmKeyCommand("texture.addWornEdges", "Add Worn Edges", menu: "Texture", HmmKeyCombo("e", option: true))
    static let textureMirrorPaint = HmmKeyCommand("texture.mirrorPaint", "Mirror Paint", menu: "Texture", HmmKeyCombo("m", control: true))
    static let textureFillFaces = HmmKeyCommand("texture.fillFaces", "Fill Faces", menu: "Texture", HmmKeyCombo("f", shift: true, option: true))
    static let lookNextLook = HmmKeyCommand("look.nextLook", "Next Look", menu: "Look", HmmKeyCombo("k", option: true))
    static let lookPreviousLook = HmmKeyCommand("look.previousLook", "Previous Look", menu: "Look", HmmKeyCombo("k", shift: true, option: true))
    static let lookImpactFrame = HmmKeyCommand("look.impactFrame", "Impact Frame", menu: "Look", HmmKeyCombo("i", control: true))
    static let lookFocusLines = HmmKeyCommand("look.focusLines", "Focus Lines", menu: "Look", HmmKeyCombo("u", control: true))
    static let lookKirbyDots = HmmKeyCommand("look.kirbyDots", "Kirby Dots", menu: "Look", HmmKeyCombo("k", control: true))
    static let physicsMakeReal = HmmKeyCommand("physics.makeReal", "Make Real", menu: "Physics", HmmKeyCombo("j", shift: true))
    static let physicsNotReal = HmmKeyCommand("physics.notReal", "Not Real", menu: "Physics", HmmKeyCombo("j", option: true))
    static let physicsSettle = HmmKeyCommand("physics.settle", "Settle", menu: "Physics", HmmKeyCombo("j"))
    static let physicsDoesItStand = HmmKeyCommand("physics.doesItStand", "Does It Stand?", menu: "Physics", HmmKeyCombo("u", option: true))
    static let physicsKeepTheRunAsKeys = HmmKeyCommand("physics.keepTheRunAsKeys", "Keep the Run as Keys",
                                                       menu: "Physics", HmmKeyCombo("k", shift: true))
    static let physicsShowSpeedAndForces = HmmKeyCommand("physics.showSpeedAndForces", "Show Speed and Forces", menu: "Physics", nil)
    static let characterNewCharacter = HmmKeyCommand("character.newCharacter", "New Character…", menu: "Character", HmmKeyCombo("c", shift: true))
    static let characterNewPerson = HmmKeyCommand("character.newPerson", "New Person", menu: "Character", HmmKeyCombo("p", option: true))
    static let characterNewFourLegged = HmmKeyCommand("character.newFourLegged", "New Four-Legged", menu: "Character", nil)
    static let characterNewCreatureFromNothing = HmmKeyCommand("character.newCreatureFromNothing", "New Creature from Nothing",
                                                               menu: "Character", nil)
    static let characterMirrorParts = HmmKeyCommand("character.mirrorParts", "Mirror Parts", menu: "Character", nil)
    static let characterRigItAgain = HmmKeyCommand("character.rigItAgain", "Rig It Again", menu: "Character", nil)
    static let characterExportForGames = HmmKeyCommand("character.exportForGames", "Export for Games…",
                                                       menu: "Character", HmmKeyCombo("e", shift: true))
    static let kitPlansAndElevations = HmmKeyCommand("kit.plansAndElevations", "Plans and Elevations", menu: "Kit", HmmKeyCombo("a", control: true))
    static let kitWalkThrough = HmmKeyCommand("kit.walkThrough", "Walk Through", menu: "Kit", HmmKeyCombo("w", control: true))
    static let kitMatchAPhoto = HmmKeyCommand("kit.matchAPhoto", "Match a Photo…", menu: "Kit", nil)
    static let kitBestWayUp = HmmKeyCommand("kit.bestWayUp", "Best Way Up", menu: "Kit", HmmKeyCombo("b", control: true))
    static let kitSplitForPrinting = HmmKeyCommand("kit.splitForPrinting", "Split for Printing", menu: "Kit", HmmKeyCombo("s", control: true))
    static let kitHollow = HmmKeyCommand("kit.hollow", "Hollow", menu: "Kit", HmmKeyCombo("h", control: true))
    static let kitShowOverhangs = HmmKeyCommand("kit.showOverhangs", "Show Overhangs", menu: "Kit", HmmKeyCombo("v", control: true))
    static let kitExplode = HmmKeyCommand("kit.explode", "Explode", menu: "Kit", HmmKeyCombo("x", control: true))
    static let kitFreezeTransforms = HmmKeyCommand("kit.freezeTransforms", "Freeze Transforms", menu: "Kit", HmmKeyCombo("t", control: true))
    static let sceneFrameSelection = HmmKeyCommand("scene.frameSelection", "Frame Selection", menu: "Scene", HmmKeyCombo("f"))
    static let sceneDirectorView = HmmKeyCommand("scene.directorView", "Director View", menu: "Scene", HmmKeyCombo("d", option: true))
    static let sceneFlyTheCamera = HmmKeyCommand("scene.flyTheCamera", "Fly the Camera", menu: "Scene", HmmKeyCombo("y", option: true))
    static let sceneHideInterface = HmmKeyCommand("scene.hideInterface", "Hide Interface", menu: "Scene", HmmKeyCombo("f", control: true))
    static let sceneHistoryAndSteps = HmmKeyCommand("scene.historyAndSteps", "History and Steps", menu: "Scene", HmmKeyCombo("y"))
    static let sceneExport = HmmKeyCommand("scene.export", "Export…", menu: "Scene", HmmKeyCombo("e"))
    static let sceneCloseTheLoop = HmmKeyCommand("scene.closeTheLoop", "Close the Loop", menu: "Scene", HmmKeyCombo("e", control: true))
    static let scenePasteASceneScript = HmmKeyCommand("scene.pasteASceneScript", "Paste a Scene Script",
                                                      menu: "Scene", HmmKeyCombo("v", option: true))
    static let sceneAiLaptopBridge = HmmKeyCommand("scene.aiLaptopBridge", "AI & Laptop Bridge…", menu: "Scene", HmmKeyCombo("b", shift: true))
    static let sceneScripts = HmmKeyCommand("scene.scripts", "Scripts…", menu: "Scene", nil)
    static let sceneNewMonitorWindow = HmmKeyCommand("scene.newMonitorWindow", "New Monitor Window", menu: "Scene", HmmKeyCombo("n", option: true))
    static let timelineShowTimeline = HmmKeyCommand("timeline.showTimeline", "Show or Hide the Timeline", menu: "Timeline", HmmKeyCombo("t"))
    static let timelinePlayPause = HmmKeyCommand("timeline.playPause", "Play / Pause", menu: "Timeline", nil)
    static let timelineKeyTheSelection = HmmKeyCommand("timeline.keyTheSelection", "Key the Selection", menu: "Timeline", HmmKeyCombo("k"))
    static let timelineRecordAPerformance = HmmKeyCommand("timeline.recordAPerformance", "Record a Performance",
                                                          menu: "Timeline", HmmKeyCombo("r", shift: true))
    static let timelineAddMarker = HmmKeyCommand("timeline.addMarker", "Add Marker", menu: "Timeline", HmmKeyCombo("m"))
    static let timelineAudioWords = HmmKeyCommand("timeline.audioWords", "Audio & Words…", menu: "Timeline", HmmKeyCombo("u", shift: true))
    static let timelineTranscript = HmmKeyCommand("timeline.transcript", "Transcript", menu: "Timeline", HmmKeyCombo("t", shift: true))
    static let timelineRecordVoiceover = HmmKeyCommand("timeline.recordVoiceover", "Record Voiceover",
                                                       menu: "Timeline", HmmKeyCombo("r", option: true))
    static let timelineSelectAllKeys = HmmKeyCommand("timeline.selectAllKeys", "Select All Keys", menu: "Timeline", HmmKeyCombo("a", option: true))
    static let timelineKeysAfterThePlayhead = HmmKeyCommand("timeline.keysAfterThePlayhead", "Keys After the Playhead",
                                                            menu: "Timeline", HmmKeyCombo("right", shift: true))
    static let timelineKeysAtThePlayhead = HmmKeyCommand("timeline.keysAtThePlayhead", "Keys at the Playhead", menu: "Timeline", nil)
    static let timelineDrawAPath = HmmKeyCommand("timeline.drawAPath", "Draw a Path", menu: "Timeline", HmmKeyCombo("4", option: true))
    static let timelineLookAt = HmmKeyCommand("timeline.lookAt", "Look At…", menu: "Timeline", HmmKeyCombo("l", control: true))
    static let timelinePickUpOrHandOff = HmmKeyCommand("timeline.pickUpOrHandOff", "Pick Up or Hand Off…",
                                                       menu: "Timeline", HmmKeyCombo("p", control: true))
    static let timelineEvenSpeed = HmmKeyCommand("timeline.evenSpeed", "Even Speed", menu: "Timeline", nil)
    static let timelineGhosts = HmmKeyCommand("timeline.ghosts", "Ghosts While Scrubbing", menu: "Timeline", HmmKeyCombo("g", control: true))
    static let timelineDopeSheet = HmmKeyCommand("timeline.dopeSheet", "The Dope Sheet or Motion",
                                                 menu: "Timeline", HmmKeyCombo("d", control: true))
    static let timelineLensAndFrame = HmmKeyCommand("timeline.lensAndFrame", "Lens and Frame…", menu: "Timeline", HmmKeyCombo("l", option: true))
    static let timelineFocusOnTheSelection = HmmKeyCommand("timeline.focusOnTheSelection", "Focus on the Selection",
                                                           menu: "Timeline", HmmKeyCombo("f", option: true))
    static let timelinePullFocusToTheSelection = HmmKeyCommand("timeline.pullFocusToTheSelection", "Pull Focus to the Selection",
                                                               menu: "Timeline", HmmKeyCombo("f", option: true, control: true))
    static let performMicrophone = HmmKeyCommand("perform.microphone", "Mouth from the Microphone", menu: "Perform", HmmKeyCombo("m", option: true))
    // U8: presenting, notes and reviews.
    static let scenePresent = HmmKeyCommand("scene.present", "Present", menu: "Scene", HmmKeyCombo("p", shift: true))
    static let sceneNotes = HmmKeyCommand("scene.notes", "Notes", menu: "Scene", HmmKeyCombo("n", shift: true))
    static let sceneYourIPhone = HmmKeyCommand("scene.yourIPhone", "Your iPhone…", menu: "Scene", nil)

    static let all: [HmmKeyCommand] = [
        editUndo,
        editRedo,
        editCopy,
        editPaste,
        editDuplicate,
        editDelete,
        editSelectAll,
        editSelectSimilar,
        editGroup,
        editUngroup,
        toolsModel,
        toolsDraw,
        toolsRig,
        toolsAnimate,
        toolsActions,
        toolsLook,
        toolsLasso,
        toolsLibrary,
        toolsPrecision,
        toolsSolidShape,
        toolsFrames,
        toolsShadowBrush,
        toolsScatter,
        toolsMove,
        toolsTurn,
        toolsSize,
        shapeShapeByTouch,
        shapeBrushTheSurface,
        shapeCage,
        shapeBend,
        shapeSmoothMore,
        shapeSmoothLess,
        shapeLoopCut,
        shapeLinkedCopy,
        shapeClone,
        shapeMorphInto,
        shapePivotToTheMiddle,
        texturePaintFlat,
        textureAddDirt,
        textureAddWornEdges,
        textureMirrorPaint,
        textureFillFaces,
        lookNextLook,
        lookPreviousLook,
        lookImpactFrame,
        lookFocusLines,
        lookKirbyDots,
        physicsMakeReal,
        physicsNotReal,
        physicsSettle,
        physicsDoesItStand,
        physicsKeepTheRunAsKeys,
        physicsShowSpeedAndForces,
        characterNewCharacter,
        characterNewPerson,
        characterNewFourLegged,
        characterNewCreatureFromNothing,
        characterMirrorParts,
        characterRigItAgain,
        characterExportForGames,
        kitPlansAndElevations,
        kitWalkThrough,
        kitMatchAPhoto,
        kitBestWayUp,
        kitSplitForPrinting,
        kitHollow,
        kitShowOverhangs,
        kitExplode,
        kitFreezeTransforms,
        sceneFrameSelection,
        sceneDirectorView,
        sceneFlyTheCamera,
        sceneHideInterface,
        sceneHistoryAndSteps,
        sceneExport,
        sceneCloseTheLoop,
        scenePasteASceneScript,
        sceneAiLaptopBridge,
        sceneScripts,
        sceneNewMonitorWindow,
        timelineShowTimeline,
        timelinePlayPause,
        timelineKeyTheSelection,
        timelineRecordAPerformance,
        timelineAddMarker,
        timelineAudioWords,
        timelineTranscript,
        timelineRecordVoiceover,
        timelineSelectAllKeys,
        timelineKeysAfterThePlayhead,
        timelineKeysAtThePlayhead,
        timelineDrawAPath,
        timelineLookAt,
        timelinePickUpOrHandOff,
        timelineEvenSpeed,
        timelineGhosts,
        timelineDopeSheet,
        timelineLensAndFrame,
        timelineFocusOnTheSelection,
        timelinePullFocusToTheSelection,
        performMicrophone,
        scenePresent,
        sceneNotes,
        sceneYourIPhone
    ]
}
