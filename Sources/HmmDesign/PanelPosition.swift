#if canImport(CoreGraphics)
    import CoreGraphics
#endif
import Foundation

/// Where a person left a panel they moved by hand, remembered per panel on this device (`UserDefaults`, key
/// `hmm.panel.<id>.offset`). The offset is from the place the panel would open at; nil means it was never moved.
public struct HmmPanelPosition: Sendable {
    public var id: String
    /// How much of the panel must stay on screen when it is pushed against an edge.
    public var keepVisible: CGFloat

    public init(id: String, keepVisible: CGFloat = 72) {
        self.id = id
        self.keepVisible = keepVisible
    }

    public var key: String { "hmm.panel.\(id).offset" }

    public func load(from defaults: UserDefaults = .standard) -> CGSize? {
        guard let pair = defaults.array(forKey: key) as? [Double], pair.count == 2 else { return nil }
        return CGSize(width: pair[0], height: pair[1])
    }

    public func save(_ offset: CGSize, to defaults: UserDefaults = .standard) {
        defaults.set([Double(offset.width), Double(offset.height)], forKey: key)
    }

    public func reset(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    /// The offset kept inside `bounds`: the panel (its frame before the offset, `frame`) keeps `keepVisible` points
    /// on screen sideways, and its title row (the top `keepVisible` points) stays on screen vertically, so it can
    /// always be grabbed again.
    public func clamped(_ offset: CGSize, frame: CGRect, in bounds: CGRect) -> CGSize {
        let keep = min(keepVisible, frame.width, frame.height)
        let minX = bounds.minX - frame.maxX + keep
        let maxX = bounds.maxX - frame.minX - keep
        let minY = bounds.minY - frame.minY
        let maxY = bounds.maxY - frame.minY - keep
        return CGSize(width: Self.clamp(offset.width, minX, maxX), height: Self.clamp(offset.height, minY, maxY))
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        max(low, min(value, max(low, high)))
    }
}
