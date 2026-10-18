import LoweyCore

extension ObjectKind {
    /// The kind's SF Symbol (the object panel's header, the timeline's rows).
    var symbolName: String {
        switch self {
        case .group: "square.on.square.dashed"
        case .primitive: "cube"
        case .asset: "shippingbox"
        case .prefab: "shippingbox.circle"
        case .drawing: "scribble"
        case .light: "lightbulb"
        case .camera: "video"
        case .text: "textformat"
        case .overlay: "square.on.square.intersection.dashed"
        case .particles: "sparkles"
        case .card: "photo.on.rectangle"
        case .mesh: "cube.transparent"
        case .sketch: "pencil.and.ruler"
        case .dimension: "ruler"
        case .force: "wind"
        case .fluid: "drop"
        }
    }
}
