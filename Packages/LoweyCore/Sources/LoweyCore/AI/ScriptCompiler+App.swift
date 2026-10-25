import Foundation

// MARK: - The app around the scene (M12)

/// What a script asks of the app rather than of the scene (M12, "the bridge reaches everything"): the hand's tool, a
/// panel, playing, presenting, an export, the AR view. None of it is an edit, so none of it is undone: the editor applies
/// these after the script's command, in order, as it does the Reference window's asks.
public struct AppAsk: Hashable, Sendable {
    public enum Op: String, CaseIterable, Hashable, Sendable {
        /// The hand's tool (`value`: model, draw, rig, animate, look, lasso, move, turn, size, precision, solidShape,
        /// frames, shadowBrush, scatter, shapeByTouch, brushTheSurface, cage, bend).
        case tool
        /// A panel or sheet (`value`: actions, library, export, history, board, learn, settings, phone, audio, transcript,
        /// scripts, bridge, plans, matchPhoto, characterBuilder, gameExport, timelineSettings, lensAndFrame, lookAt, pickUp).
        case panel
        /// Close what's open.
        case closePanel
        case play, pause
        /// The playhead (`value`: seconds).
        case playhead
        case undo, redo
        /// Present (`value`: film, walk, model) and stop.
        case present, stopPresenting
        /// Review notes on the stage (`value`: true, false).
        case notes
        /// The timeline (`value`: true shows it, false hides it).
        case timeline
        /// Through the shot's camera (`value`: true, false).
        case directorView
        /// The chrome away (`value`: true, false).
        case hideInterface
        /// The view frames the selection (`value`: a thing's name, or the selection).
        case frameSelection
        /// Fly the camera (`value`: true, false).
        case fly
        /// Ghosts while scrubbing, speed and forces, overhangs (`value`: ghosts, forces, overhangs, dopeSheet; with `on`).
        case show
        /// Select (`value`: a name, a list of names, "all", "similar", "none").
        case select
        /// An export into the project's renders (`value`: film, still, gif, glb, usdz, obj, stl, 3mf, blender, fbx); the
        /// laptop fetches it from /v1/renders.
        case export
        /// The AR view on the iPad (`value`: true opens, false closes).
        case ar
        /// A Monitor window.
        case monitor
    }

    public var op: Op
    public var value: JSONValue?
    public var on: Bool?

    public init(_ op: Op, value: JSONValue? = nil, on: Bool? = nil) {
        self.op = op
        self.value = value
        self.on = on
    }

    /// What the report says.
    public var description: String {
        let detail = value.map { value -> String in
            if let text = value.stringValue { return text }
            if let number = value.numberValue { return String(format: "%g", number) }
            if let flag = value.boolValue { return flag ? "on" : "off" }
            return (try? String(decoding: LoweyJSON.encode(value), as: UTF8.self)) ?? ""
        }
        return "App: \(op.rawValue)" + (detail.map { " \($0)" } ?? "") + (on.map { $0 ? " on" : " off" } ?? "")
    }
}

extension ScriptState {
    /// `{"do": "app", "op": "present", "value": "film"}`: the app around the scene (`AppAsk.Op`).
    mutating func app(_ action: JSONValue) throws {
        guard let name = string(action, "op") else { throw fail("app needs “op” (\(AppAsk.Op.allCases.map(\.rawValue).joined(separator: ", ")))") }
        guard let op = AppAsk.Op(rawValue: name) else {
            throw fail("app has no op “\(name)” (\(AppAsk.Op.allCases.map(\.rawValue).joined(separator: ", ")))")
        }
        let value = action["value"]
        let needsValue: Set<AppAsk.Op> = [.tool, .panel, .playhead, .export, .show, .select]
        if needsValue.contains(op), value == nil { throw fail("app \(name) needs “value”") }
        if op == .playhead, value?.numberValue == nil { throw fail("app playhead needs “value”: seconds") }
        let ask = AppAsk(op, value: value, on: bool(action, "on"))
        app.append(ask)
        report.append(ask.description)
    }
}
