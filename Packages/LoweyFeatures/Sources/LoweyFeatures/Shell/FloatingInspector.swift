import HmmDesign
import LoweyCore
import SwiftUI

/// The object panel, floating beside the selection without covering it (HmmFloatingPlacement): it keeps its side while
/// it fits, flips at the screen's edge, and glides over once the view settles. It stays inside the room the chrome
/// leaves: below the corner clusters, clear of the sidebar, an open panel and the bottom row.
///
/// Moved by hand (its header is a grip), it stays where it was left, on this device, until its header is double-tapped;
/// but it never opens on top of the thing it describes: a remembered spot that would cover the selection gives way to
/// the place beside it. While something bigger is open it is a chip. With Settings ▸ Stage ▸ Dock the inspector it
/// stays at the side instead.
struct FloatingInspector: View {
    let editor: EditorModel
    /// An open panel on the leading side, in screen space (the stage's space too: it fills the window from its corner).
    let avoiding: CGRect?
    let sidebarOnRight: Bool
    @State private var size: HmmPanelSize?
    @State private var side: HmmFloatingSide = .right
    @State private var dragStart: CGPoint?
    @State private var dragOrigin: CGPoint?
    @AppStorage(AppSettings.inspectorDocked) private var docked = false
    /// Where it was left, as fractions of the room (so it survives a rotation); negative: never moved.
    @AppStorage("inspector.pinnedX") private var pinnedX = -1.0
    @AppStorage("inspector.pinnedY") private var pinnedY = -1.0
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let chipSize = CGSize(width: 300, height: 52)

    var body: some View {
        // The stage view ignores the top and side safe areas, so the selection's rect is in that space: so is this.
        GeometryReader { geometry in
            let room = Self.room(in: geometry.size, insets: geometry.safeAreaInsets, sidebarOnRight: sidebarOnRight, avoiding: avoiding)
            let chip = editor.inspectorAsChip
            let placed = placement(in: room, size: chip ? Self.chipSize : panelSize)
            Group {
                if chip {
                    InspectorChip(editor: editor)
                        .fixedSize()
                        .frame(width: placed.frame.width, height: placed.frame.height, alignment: placed.side == .right ? .leading : .trailing)
                } else {
                    InspectorPanel(editor: editor, size: $size, move: move(in: room, frame: placed.frame))
                        .frame(width: placed.frame.width, height: placed.frame.height)
                }
            }
            .environment(\.layoutDirection, layoutDirection)
            .position(x: placed.frame.midX, y: placed.frame.midY)
            .animation(dragStart == nil ? HmmMotion.standard.animation(reduceMotion: reduceMotion) : nil, value: placed.frame)
            .onChange(of: placed.side) { _, newSide in side = newSide }
        }
        .environment(\.layoutDirection, .leftToRight)
        .ignoresSafeArea(edges: [.top, .horizontal])
        .animation(HmmMotion.standard.animation(reduceMotion: reduceMotion), value: editor.inspectorAsChip)
    }

    private var panelSize: CGSize {
        CGSize(width: size?.width ?? InspectorPanel.defaultSize.width, height: size?.height ?? InspectorPanel.defaultSize.height)
    }

    private func placement(in room: CGRect, size: CGSize) -> (frame: CGRect, side: HmmFloatingSide) {
        if let origin = dragOrigin {
            return (CGRect(origin: origin, size: CGSize(width: min(size.width, room.width), height: min(size.height, room.height))), side)
        }
        guard !docked, let target = editor.selectionScreenRect else {
            return (HmmFloatingPlacement.docked(size, in: room, side: docked ? .right : side), docked ? .right : side)
        }
        if let pinned = pinnedFrame(size: size, in: room), !pinned.intersects(target) {
            return (pinned, side)
        }
        let placed = HmmFloatingPlacement.place(size, beside: target, in: room, current: side)
        return (placed.frame, placed.side)
    }

    /// The spot it was left at, kept inside the room.
    private func pinnedFrame(size: CGSize, in room: CGRect) -> CGRect? {
        guard pinnedX >= 0, pinnedY >= 0 else { return nil }
        let width = min(size.width, room.width)
        let height = min(size.height, room.height)
        let x = room.minX + CGFloat(pinnedX) * max(room.width - width, 0)
        let y = room.minY + CGFloat(pinnedY) * max(room.height - height, 0)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// The header's drag: the panel follows the finger inside the room, and is remembered where it lands.
    private func move(in room: CGRect, frame: CGRect) -> InspectorMove? {
        guard !docked else { return nil }
        return InspectorMove(changed: { translation in
            let start = dragStart ?? frame.origin
            if dragStart == nil { dragStart = start }
            let x = min(max(start.x + translation.width, room.minX), max(room.maxX - frame.width, room.minX))
            let y = min(max(start.y + translation.height, room.minY), max(room.maxY - frame.height, room.minY))
            dragOrigin = CGPoint(x: x, y: y)
        }, ended: {
            if let origin = dragOrigin {
                pinnedX = room.width > frame.width ? Double((origin.x - room.minX) / (room.width - frame.width)) : 0
                pinnedY = room.height > frame.height ? Double((origin.y - room.minY) / (room.height - frame.height)) : 0
            }
            dragStart = nil
            dragOrigin = nil
        }, reset: {
            pinnedX = -1
            pinnedY = -1
        })
    }

    /// The part of the stage the inspector may use, clear of the chrome and of an open panel on either side.
    static func room(in size: CGSize, insets: EdgeInsets, sidebarOnRight: Bool, avoiding: CGRect?) -> CGRect {
        let margin = CGFloat(HmmSpacing.m)
        let sidebar: CGFloat = 64
        // A cluster's height and a gap above; the bottom row's height and a gap below.
        let band = CGFloat(HmmTarget.minimum + HmmSpacing.l)
        let top = insets.top + margin + band
        let bottom = size.height - margin - band
        var minX = insets.leading + margin + (sidebarOnRight ? 0 : sidebar)
        var maxX = size.width - insets.trailing - margin - (sidebarOnRight ? sidebar : 0)
        if let avoiding {
            // Leading is the left in left-to-right languages and the right in right-to-left ones.
            if avoiding.midX < size.width / 2 {
                minX = max(minX, avoiding.maxX + CGFloat(HmmSpacing.s))
            } else {
                maxX = min(maxX, avoiding.minX - CGFloat(HmmSpacing.s))
            }
        }
        return CGRect(x: minX, y: top, width: max(maxX - minX, 0), height: max(bottom - top, 0))
    }
}
