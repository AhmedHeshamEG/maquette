import Foundation

/// The Keeper's Tower (CONTEXT §10.9, L2): a huge leaning tower of stone on a dark outcrop, one warm amber lamp at its
/// top, a tiny keeper with a lantern at its foot, at night in Ink. Home's Samples stack shows it turning; it's the
/// first App Store picture and the flagship lesson later (M16). Built with Scene Script, like every sample.
public enum KeepersTowerSample {
    public static let projectName = "The Keeper's Tower"

    public static func build(ids: IDFactory = .sequential("tower")) throws -> (ProjectInfo, [Scene]) {
        var look = MoodPresets.look(for: .night)
        look.presetID = LookPreset.ink.id
        look.sky.stars = 0.9
        look.fog = Fog(enabled: true, color: RGBA.hex("#141A33"), distance: 48)
        look.ground = look.ground.made(of: .rock)
        look.ground.color = RGBA.hex("#34323A")
        look.atmosphere = Atmosphere(haze: 0.012, color: RGBA.hex("#1B2240"))
        look.palette = Palette(swatches: [
            .init(name: "Stone", color: RGBA.hex("#6E6A73")), .init(name: "Mortar", color: RGBA.hex("#4B4852")),
            .init(name: "Roof", color: RGBA.hex("#3A2F35")), .init(name: "Lamp", color: RGBA.hex("#FFB347")),
            .init(name: "Coat", color: RGBA.hex("#2F3E5C")), .init(name: "Night", color: RGBA.hex("#141A33"))
        ])
        let info = ProjectInfo(id: ids.isSequential ? "tower-project" : .make(), name: projectName, look: look)
        var scene = Scene(id: ids.isSequential ? "tower-scene" : .make(), name: "The tower at night")
        scene.look = look
        scene.timeline = Timeline(fps: 24, duration: 12)
        let parsed = try LoweyJSON.decode(SceneScript.self, from: Data(script.utf8))
        let result = try ScriptCompiler.compile(parsed, document: Document(project: info, scene: scene), context: ScriptContext(ids: ids))
        scene = result.document.scene
        scene.viewpoint = Viewpoint(target: Vec3(0.6, 4.5, 0), yaw: 32, pitch: 8, distance: 17)
        return (info, [scene])
    }

    /// The tower leans by its group's turn; the lamp sits where the lantern room ends up (0.98, 9.95, 0).
    static let script = """
    {"version": 2, "title": "The Keeper's Tower", "actions": [
      {"do": "add", "shape": "cone", "name": "Outcrop", "at": [0, 0, 0], "size": [10, 0.7, 9], "color": "#3C3A40"},
      {"do": "add", "shape": "sphere", "name": "Boulder", "at": [-3.6, 0, 2.2], "size": [1.1, 0.8, 1], "color": "#45434B", "onGround": false},
      {"do": "add", "shape": "sphere", "name": "Small boulder", "at": [3.9, 0, -1.6], "size": [0.7, 0.5, 0.6], "color": "#45434B", "onGround": false},
      {"do": "add", "shape": "group", "name": "Tower", "at": [0, 0.6, 0], "rotation": [0, 0, -6], "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Course 1", "parent": "Tower", "at": [0, 0, 0], "size": [3, 1.6, 3], "color": "#6E6A73", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Band 1", "parent": "Tower", "at": [0, 1.6, 0], "size": [3.15, 0.15, 3.15], "color": "#4B4852", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Course 2", "parent": "Tower", "at": [0.05, 1.75, 0], "size": [2.85, 1.6, 2.85], "color": "#716D76", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Band 2", "parent": "Tower", "at": [0.05, 3.35, 0], "size": [3, 0.15, 3], "color": "#4B4852", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Course 3", "parent": "Tower", "at": [0, 3.5, 0], "size": [2.7, 1.6, 2.7], "color": "#6A6670", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Band 3", "parent": "Tower", "at": [0, 5.1, 0], "size": [2.85, 0.15, 2.85], "color": "#4B4852", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Course 4", "parent": "Tower", "at": [-0.04, 5.25, 0], "size": [2.55, 1.6, 2.55], "color": "#726E78", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Band 4", "parent": "Tower", "at": [-0.04, 6.85, 0], "size": [2.7, 0.15, 2.7], "color": "#4B4852", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Course 5", "parent": "Tower", "at": [0, 7, 0], "size": [2.4, 1.6, 2.4], "color": "#6E6A73", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Gallery", "parent": "Tower", "at": [0, 8.6, 0], "size": [3.2, 0.18, 3.2], "color": "#2E2B33", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Lantern frame", "parent": "Tower", "at": [0, 8.78, 0], "size": [1.7, 1.3, 1.7], "color": "#2E2B33", "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Lamp glass", "parent": "Tower", "at": [0, 8.88, 0], "size": [1.78, 1.1, 1.78], "color": "#FFB347", "glow": 4, "onGround": false},
      {"do": "add", "shape": "cone", "name": "Roof", "parent": "Tower", "at": [0, 10.08, 0], "size": [2.1, 1.2, 2.1], "color": "#3A2F35", "onGround": false},
      {"do": "add", "shape": "sphere", "name": "Finial", "parent": "Tower", "at": [0, 11.22, 0], "size": [0.25, 0.25, 0.25], "color": "#3A2F35", "onGround": false},
      {"do": "add", "shape": "cube", "name": "Door", "parent": "Tower", "at": [0, 0, 1.47], "size": [0.7, 1.1, 0.12], "color": "#3B2A20", "onGround": false},
      {"do": "add", "shape": "cube", "name": "Window", "parent": "Tower", "at": [0.05, 2.35, 1.4], "size": [0.32, 0.55, 0.1], "color": "#1B1A22", "onGround": false},
      {"do": "add", "shape": "cube", "name": "Lit window", "parent": "Tower", "at": [-0.04, 5.8, 1.25], "size": [0.3, 0.5, 0.1], "color": "#FFB347", "glow": 1.5, "onGround": false},
      {"do": "light", "type": "point", "name": "The lamp", "at": [0.98, 9.95, 0], "color": "#FFB347", "intensity": 3, "range": 20},
      {"do": "add", "shape": "group", "name": "Keeper", "at": [2.3, 0.62, 3.1], "rotation": [0, -25, 0], "onGround": false},
      {"do": "add", "shape": "cylinder", "name": "Coat", "parent": "Keeper", "at": [0, 0, 0], "size": [0.3, 0.5, 0.3], "color": "#2F3E5C", "onGround": false},
      {"do": "add", "shape": "sphere", "name": "Head", "parent": "Keeper", "at": [0, 0.5, 0], "size": [0.22, 0.22, 0.22], "color": "#F2C9A0", "onGround": false},
      {"do": "add", "shape": "cone", "name": "Hat", "parent": "Keeper", "at": [0, 0.66, 0], "size": [0.28, 0.2, 0.28], "color": "#1E1A1C", "onGround": false},
      {"do": "add", "shape": "cube", "name": "Lantern", "parent": "Keeper", "at": [0.21, 0.2, 0.05], "size": [0.09, 0.12, 0.09], "color": "#FFB347", "glow": 4, "onGround": false},
      {"do": "light", "type": "point", "name": "Keeper's lantern", "at": [2.5, 0.95, 3.2], "color": "#FFB347", "intensity": 1.2, "range": 3},
      {"do": "camera", "name": "Tower camera", "from": [9, 1.6, 13], "lookAt": [0.6, 5.2, 0], "focalLength": 28, "active": true},
      {"do": "cameraMove", "camera": "Tower camera", "move": "orbit", "subject": [0.6, 4.5, 0], "at": 0, "duration": 12},
      {"do": "cut", "camera": "Tower camera", "at": 0}
    ]}
    """
}
