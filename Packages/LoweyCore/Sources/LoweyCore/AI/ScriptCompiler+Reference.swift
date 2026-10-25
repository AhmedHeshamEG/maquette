import Foundation

// MARK: - The Reference window (Q1)

/// What a script asks of the Reference window. It's how the person sees their work, not the project, so it isn't an
/// edit: the editor applies these after the script's command, in order.
public enum ReferenceAsk: Hashable, Sendable {
    case open(ReferenceWindow.Mode?)
    case mode(ReferenceWindow.Mode)
    /// A picture already in the project (`/v2/media?as=reference` puts one there and names it).
    case image(String)
    /// Canvas frames the whole scene again, from where the stage looks now.
    case frame
    case close
}

extension ScriptState {
    /// `{"do": "reference", "op": "open" | "mode" | "image" | "frame" | "close", "mode": "canvas" | "image" | "face",
    /// "image": "references/….png"}`.
    mutating func reference(_ action: JSONValue) throws {
        let mode = try string(action, "mode").map { name in
            guard let mode = ReferenceWindow.Mode(rawValue: name) else {
                throw fail("reference has no mode “\(name)” (\(ReferenceWindow.Mode.allCases.map(\.rawValue).joined(separator: ", ")))")
            }
            return mode
        }
        let ask: ReferenceAsk
        switch string(action, "op") ?? (mode == nil ? "open" : "mode") {
        case "open": ask = .open(mode)
        case "mode":
            guard let mode else { throw fail("reference mode needs “mode”") }
            ask = .mode(mode)
        case "image":
            guard let file = string(action, "image"), file.hasPrefix("\(ProjectLayout.referencesFolder)/"), !file.contains("..") else {
                throw fail("reference image needs “image”: the name /v2/media?as=reference gave (references/….png)")
            }
            ask = .image(file)
        case "frame": ask = .frame
        case "close": ask = .close
        case let other: throw fail("reference has no op “\(other)” (open, mode, image, frame, close)")
        }
        reference.append(ask)
        report.append(Self.describe(ask))
    }

    static func describe(_ ask: ReferenceAsk) -> String {
        switch ask {
        case let .open(mode): "Reference window open" + (mode.map { ": \($0.title)" } ?? "")
        case let .mode(mode): "Reference window: \(mode.title)"
        case .image: "Reference window: the picture"
        case .frame: "Reference window: the whole scene again"
        case .close: "Reference window closed"
        }
    }
}
