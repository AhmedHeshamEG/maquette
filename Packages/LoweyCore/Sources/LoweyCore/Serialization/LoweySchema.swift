import Foundation
import HmmDocuments

/// The JSON files inside a `.lowey` package, the library and the brush library.
public enum FileKind: String, Sendable {
    case project, scene, library, brushes, materials
}

public extension Migration {
    init(kind: FileKind, from: Int, transform: @escaping @Sendable (JSONValue) throws -> JSONValue) {
        self.init(kind: kind.rawValue, from: from, transform: transform)
    }
}

public extension SchemaCoder {
    /// Maquette's coder: current schema, every migration since v0.
    static let shared = SchemaCoder(appName: "Maquette", currentVersion: LoweySchema.currentVersion, migrations: LoweySchema.migrations)

    func encode(_ payload: some Codable & Sendable, kind: FileKind) throws -> Data {
        try encode(payload, kind: kind.rawValue)
    }

    func decode<T: Codable & Sendable>(_ type: T.Type, kind: FileKind, from data: Data) throws -> T {
        try decode(type, kind: kind.rawValue, from: data)
    }

    func migrate(_ raw: JSONValue, kind: FileKind) throws -> JSONValue {
        try migrate(raw, kind: kind.rawValue)
    }
}

/// Schema versions of Maquette's JSON files.
///
/// - v1: objects keyed by id, transforms as properties.
/// - v2 (1.0 phase 2): timelines gain markers, loop, cuts, behaviours, clip tracks. Additive.
/// - v3 (1.0 phase 3): audio, transcripts, effects, transitions, captions; looks gain post. Additive.
/// - v4 (2.0): looks gain a render style (`presetID`); projects gain their own Looks. Files from 1.x keep their
///   appearance: they open in Clay (the v1 look on the new renderer), or Low-poly when they were faceted.
public enum LoweySchema {
    /// 5: Maquette 0.3's `mesh` and `sketch` objects (older apps refuse these files instead of misreading them).
    /// 6: Maquette 0.4's `dimension` objects and the `symmetry` property.
    /// 7: Maquette 0.5's brushes: strokes name a brush, projects keep the brushes they use, the `setBrushes` command.
    /// 8: Maquette 0.6's paint: objects' `paint` (surface and layers), the `setPaint` and `paintTiles` commands.
    /// 9: Maquette 0.7's rigs: objects' `rig` (a drawn skeleton and its weights), `bone.<joint>` properties, `setRig`.
    /// 10: Maquette 0.8's looping motions: the `bounce` and `swing` behaviours.
    /// 11: Maquette 0.10's live performance: timelines' `takes` and the `setTakes` command; `dangle.<joint>`, `breathe`,
    ///     `attachBone`, `liveHead` and `triggers` properties.
    /// 12: Maquette 0.12's `darkStudio` mood (a blank project's world).
    /// 13: Maquette 0.13's sheets: scenes' `sheets`, the `setSheets` command, flipbooks drawn on a sheet.
    /// 14: Maquette 0.14's rigs: a rig's `marks` (pins and dots) and `person` dots, the `bendDetail` property, tracks'
    ///     `cycle` (a motion played again), the library's `motions` and an asset's `original` and `detail`.
    /// 15: Maquette 0.16's shaping: objects' `shaping` (a cage, surface brush strokes), the `setShaping` command, the
    ///     `subdivision`, `smoothAngle`, `deform`, `deformAmount`, `deformAxis` and `linked` properties, sketches'
    ///     `constraints`.
    /// 16: Maquette 0.17's editable history: objects' `modelHistory` (the shape the steps start from, the steps, the
    ///     tags of the faces), the `setModelHistory` command.
    /// 17: Maquette 0.18's texture: layers' `maps` (roughness, metal, glow, bumps, fur, mask) and `fill`, paint's
    ///     `mirror`, `normalMap` and the surface's `seams`, tile changes' `map`, the `fur…` properties, the
    ///     `materials` library file.
    /// 18: Maquette 0.19's physics: objects' `physics` (a material and how it moves), scenes' `physics` (gravity, wind,
    ///     ground, joints), the `force` and `fluid` objects, the `setPhysics` and `setScenePhysics` commands, the Look's
    ///     `realSun`.
    /// 19: Maquette 0.20's characters: objects' `part` (a made character's part: its job, side, style, pieces and face
    ///     states), the `setPart` command, the `characterStart`, `mouthShape` and `browState` properties.
    /// 20: Maquette 0.21's animation: timelines' `holds` (pick-up, hand-off, put-down), the `setHolds` command, the
    ///     `lookAt` property.
    /// 21: Maquette 0.22's film: the `area` light (a soft panel) and its `lightWidth` / `lightHeight`, cameras' `sensor`,
    ///     `rig…` and `focusOn` properties, timelines' `frame`, the Look's `atmosphere` and the sky's `environment…`.
    /// 22: Maquette 0.23's motion design: objects' `motionDesign` (clones, a morph, animated letters), timelines'
    ///     `links`, audio clips' `levels`, 3D text's `font`, the `morph` and `effectStrength` properties, the
    ///     `setMotionDesign` and `setLinks` commands.
    /// 23: Maquette 0.24's Looks and library: Looks' `paint` and `pixel`, shading's `shadowTint` and `reflection`, the
    ///     Finish's `misregistration`, `boil`, `benDay` and three print textures, screen effects' `impact`, `focusLines` and
    ///     `kirbyDots` with a `center` or `target`, the ground's `surface`, the library's `styles`, `effects`, `parts` and
    ///     `origins`.
    /// 24: Maquette 0.26's review notes: scenes' `notes` (a pin on a spot, its thread, resolved or not) and the
    ///     `setNotes` command.
    /// 25: Maquette 0.28's web layer: cards' and overlays' `web` (a page, a three.js scene or a Lottie file on the
    ///     timeline's clock).
    /// 26: Maquette 0.29's clones as a file placed them: the `placed` clone layout.
    public static let currentVersion = 26

    public static let migrations: [Migration] = [
        Migration(kind: .scene, from: 0, transform: liftSceneV0),
        Migration(kind: .project, from: 0) { $0 },
        Migration(kind: .library, from: 0) { $0 },
        Migration(kind: .scene, from: 1) { $0 },
        Migration(kind: .project, from: 1) { $0 },
        Migration(kind: .library, from: 1) { $0 },
        Migration(kind: .scene, from: 2) { $0 },
        Migration(kind: .project, from: 2) { $0 },
        Migration(kind: .library, from: 2) { $0 },
        Migration(kind: .scene, from: 3) { keepV1Appearance($0) },
        Migration(kind: .project, from: 3) { keepV1Appearance($0) },
        Migration(kind: .library, from: 3) { keepV1Appearance($0) },
        // 4 → 5 adds object kinds; nothing older changes shape.
        Migration(kind: .scene, from: 4) { $0 },
        Migration(kind: .project, from: 4) { $0 },
        Migration(kind: .library, from: 4) { $0 },
        // 5 → 6 adds an object kind; nothing older changes shape.
        Migration(kind: .scene, from: 5) { $0 },
        Migration(kind: .project, from: 5) { $0 },
        Migration(kind: .library, from: 5) { $0 },
        // 6 → 7 adds optional brush fields; nothing older changes shape.
        Migration(kind: .scene, from: 6) { $0 },
        Migration(kind: .project, from: 6) { $0 },
        Migration(kind: .library, from: 6) { $0 },
        // 7 → 8 adds an optional paint field; nothing older changes shape.
        Migration(kind: .scene, from: 7) { $0 },
        Migration(kind: .project, from: 7) { $0 },
        Migration(kind: .library, from: 7) { $0 },
        // 8 → 9 adds an optional rig field; nothing older changes shape.
        Migration(kind: .scene, from: 8) { $0 },
        Migration(kind: .project, from: 8) { $0 },
        Migration(kind: .library, from: 8) { $0 },
        // 9 → 10 adds two behaviour kinds; nothing older changes shape.
        Migration(kind: .scene, from: 9) { $0 },
        Migration(kind: .project, from: 9) { $0 },
        Migration(kind: .library, from: 9) { $0 },
        // 10 → 11 adds optional takes and properties; nothing older changes shape.
        Migration(kind: .scene, from: 10) { $0 },
        Migration(kind: .project, from: 10) { $0 },
        Migration(kind: .library, from: 10) { $0 },
        // 11 → 12 adds a mood; nothing older changes shape.
        Migration(kind: .scene, from: 11) { $0 },
        Migration(kind: .project, from: 11) { $0 },
        Migration(kind: .library, from: 11) { $0 },
        // 12 → 13 adds optional sheets and a flipbook anchor; nothing older changes shape.
        Migration(kind: .scene, from: 12) { $0 },
        Migration(kind: .project, from: 12) { $0 },
        Migration(kind: .library, from: 12) { $0 },
        // 13 → 14 adds optional rig marks, track cycles, a property and library motions; nothing older changes shape.
        Migration(kind: .scene, from: 13) { $0 },
        Migration(kind: .project, from: 13) { $0 },
        Migration(kind: .library, from: 13) { $0 },
        // 14 → 15 adds optional fields and properties; nothing older changes shape.
        Migration(kind: .scene, from: 14) { $0 },
        Migration(kind: .project, from: 14) { $0 },
        Migration(kind: .library, from: 14) { $0 },
        // 15 → 16 adds the optional model history; nothing older changes shape.
        Migration(kind: .scene, from: 15) { $0 },
        Migration(kind: .project, from: 15) { $0 },
        Migration(kind: .library, from: 15) { $0 },
        // 16 → 17 adds optional paint maps, fills, mirror, normals, seams and fur; nothing older changes shape.
        Migration(kind: .scene, from: 16) { $0 },
        Migration(kind: .project, from: 16) { $0 },
        Migration(kind: .library, from: 16) { $0 },
        // 17 → 18 adds optional physics, two object kinds and the real sun; nothing older changes shape.
        Migration(kind: .scene, from: 17) { $0 },
        Migration(kind: .project, from: 17) { $0 },
        Migration(kind: .library, from: 17) { $0 },
        // 18 → 19 adds optional character parts; nothing older changes shape.
        Migration(kind: .scene, from: 18) { $0 },
        Migration(kind: .project, from: 18) { $0 },
        Migration(kind: .library, from: 18) { $0 },
        // 19 → 20 adds optional holds and a property; nothing older changes shape.
        Migration(kind: .scene, from: 19) { $0 },
        Migration(kind: .project, from: 19) { $0 },
        Migration(kind: .library, from: 19) { $0 },
        // 20 → 21 adds a light type, optional fields and properties; nothing older changes shape.
        Migration(kind: .scene, from: 20) { $0 },
        Migration(kind: .project, from: 20) { $0 },
        Migration(kind: .library, from: 20) { $0 },
        // 21 → 22 adds optional motion design, links, levels and a font; nothing older changes shape.
        Migration(kind: .scene, from: 21) { $0 },
        Migration(kind: .project, from: 21) { $0 },
        Migration(kind: .library, from: 21) { $0 },
        // 22 → 23 adds Look and Finish fields, effect kinds, a ground surface and library lists; nothing older changes shape.
        Migration(kind: .scene, from: 22) { $0 },
        Migration(kind: .project, from: 22) { $0 },
        Migration(kind: .library, from: 22) { $0 },
        // 23 → 24 adds optional review notes; nothing older changes shape.
        Migration(kind: .scene, from: 23) { $0 },
        Migration(kind: .project, from: 23) { $0 },
        Migration(kind: .library, from: 23) { $0 },
        // 24 → 25 adds optional web pieces on cards and overlays; nothing older changes shape.
        Migration(kind: .scene, from: 24) { $0 },
        Migration(kind: .project, from: 24) { $0 },
        Migration(kind: .library, from: 24) { $0 },
        // 25 → 26 adds a clone layout; nothing older changes shape.
        Migration(kind: .scene, from: 25) { $0 },
        Migration(kind: .project, from: 25) { $0 },
        Migration(kind: .library, from: 25) { $0 }
    ] + unchangedSince(.brushes) + unchangedSince(.materials)

    /// A file kind whose payload hasn't changed shape at any version: every step keeps it as it is (D-339; the
    /// brush library was missing these, so each schema bump failed to read the device's brushes).
    static func unchangedSince(_ kind: FileKind) -> [Migration] {
        (0 ..< currentVersion).map { Migration(kind: kind, from: $0) { $0 } }
    }

    /// The render style a 1.x look maps to.
    static func v1PresetID(for look: JSONValue) -> String {
        look["shading"]?.stringValue == "flat" ? LookPreset.lowPoly.id : LookPreset.clay.id
    }

    /// Every look in the file (project look, scene look, saved library looks) gets the style that keeps its v1
    /// appearance. A look is any object with a palette, lighting and sky.
    static func keepV1Appearance(_ value: JSONValue) -> JSONValue {
        switch value {
        case var .object(dictionary):
            for (key, child) in dictionary {
                dictionary[key] = keepV1Appearance(child)
            }
            if dictionary["palette"] != nil, dictionary["lighting"] != nil, dictionary["sky"] != nil, dictionary["presetID"] == nil {
                dictionary["presetID"] = .string(v1PresetID(for: .object(dictionary)))
            }
            return .object(dictionary)
        case let .array(items):
            return .array(items.map(keepV1Appearance))
        default:
            return value
        }
    }

    /// v0 → v1: objects were an array with nested transforms; v1 keys them by id with transform properties.
    static func liftSceneV0(_ payload: JSONValue) -> JSONValue {
        var scene = payload
        if let array = payload["objects"]?.arrayValue {
            var keyed: [String: JSONValue] = [:]
            for object in array {
                guard let id = object["id"]?.stringValue else { continue }
                keyed[id] = liftTransform(object)
            }
            scene["objects"] = .object(keyed)
        } else if let dictionary = payload["objects"]?.objectValue {
            scene["objects"] = .object(dictionary.mapValues(liftTransform))
        }
        if scene["roots"] == nil, let objects = scene["objects"]?.objectValue {
            let roots = objects.values
                .filter { $0["parent"] == nil || $0["parent"] == .null }
                .compactMap { $0["id"]?.stringValue }
                .sorted()
            scene["roots"] = .array(roots.map(JSONValue.string))
        }
        return scene
    }

    private static func liftTransform(_ object: JSONValue) -> JSONValue {
        guard case var .object(dictionary) = object else { return object }
        if dictionary["children"] == nil { dictionary["children"] = .array([]) }
        var properties = dictionary["properties"]?.objectValue ?? [:]
        if let transform = dictionary["transform"]?.objectValue {
            if let position = transform["position"] { properties["position"] = .object(["vec3": position]) }
            if let rotation = transform["rotation"] { properties["rotation"] = .object(["quat": rotation]) }
            if let scale = transform["scale"] { properties["scale"] = .object(["vec3": scale]) }
            dictionary.removeValue(forKey: "transform")
        }
        dictionary["properties"] = .object(properties)
        return .object(dictionary)
    }
}
