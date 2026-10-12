import HmmDesign
import SwiftUI

/// Every gesture, the same in every hmm. app, plus Maquette's own.
struct GestureGuide: View {
    struct Item: Identifiable {
        let symbol: String
        let gesture: String
        let result: String
        var id: String { gesture }
    }

    static let sections: [(String, [Item])] = [
        ("Everywhere", HmmUniversalGesture.allCases.map { Item(symbol: "hand.tap", gesture: $0.gesture, result: $0.meaning) }),
        ("Stage", [
            Item(symbol: "hand.point.up.left", gesture: "Tap", result: "Select; tap empty space to deselect"),
            Item(symbol: "hand.draw", gesture: "Drag", result: "Orbit; drag the selection to move it"),
            Item(symbol: "arrow.up.and.down.and.arrow.left.and.right", gesture: "Two-finger drag", result: "Pan"),
            Item(symbol: "arrow.trianglehead.2.clockwise.rotate.90", gesture: "Two fingers on the selection", result: "Twist turns it, pinch sizes it"),
            Item(symbol: "scope", gesture: "Double-tap", result: "Frame a thing; again, look straight at the face you touched"),
            Item(symbol: "hand.tap", gesture: "Tap with a drawing tool", result: "The sheet goes there: onto a surface, or into the air facing you"),
            Item(symbol: "doc.on.clipboard", gesture: "Three-finger swipe down", result: "Cut, copy and paste"),
            Item(symbol: "hand.tap", gesture: "Touch and hold an object", result: "Its menu: duplicate, rename, hide, lock and more"),
            Item(symbol: "video", gesture: "Looking through a camera", result: "Fingers fly it: drag aims, two fingers move, pinch dollies, twist rolls")
        ]),
        ("Apple Pencil", [
            Item(symbol: "pencil.tip", gesture: "A drawing or painting tool", result: "The Pencil makes, fingers move the view. No Pencil: a finger makes"),
            Item(symbol: "scribble", gesture: "Draw, then hold", result: "Snaps to a clean line, circle or rectangle"),
            Item(symbol: "magnet", gesture: "A finger held down while the Pencil works", result: "Snapping flips for that one move"),
            Item(symbol: "pencil.and.outline", gesture: "Squeeze (Pencil Pro)", result: "The quick menu at the tip"),
            Item(symbol: "hand.tap", gesture: "Double-tap the Pencil", result: "What the iPad's Pencil setting says (the eraser, the last tool, the colours)"),
            Item(symbol: "arrow.clockwise", gesture: "Barrel roll (Pencil Pro)", result: "Turns what you perform")
        ]),
        ("Timeline", [
            Item(symbol: "hand.point.up.left", gesture: "Tap or drag the ruler", result: "Move the playhead (snaps to words)"),
            Item(symbol: "arrow.left.and.right", gesture: "Pinch", result: "Zoom time"),
            Item(symbol: "rectangle.dashed", gesture: "Touch and hold, then drag", result: "Box-select keys; on a clip's edge, retime it"),
            Item(symbol: "lasso", gesture: "Draw around with the Pencil", result: "Pick keys and clips"),
            Item(symbol: "hand.draw", gesture: "Two-finger drag", result: "Pan through time and rows"),
            Item(symbol: "pencil.tip", gesture: "Pencil hover", result: "Scrub"),
            Item(symbol: "flag", gesture: "Touch and hold a marker", result: "Rename or delete it")
        ]),
        ("Keyboard", [
            Item(symbol: "space", gesture: "Space · J K L", result: "Play / pause · shuttle"),
            Item(symbol: "option", gesture: "⌥← ⌥→", result: "Back / forward 10 seconds"),
            Item(symbol: "command", gesture: "⌘1 – ⌘5", result: "Model, Draw, Paint, Rig, Animate"),
            Item(symbol: "command", gesture: "⌘6 – ⌘8 · ⌘L", result: "Actions, Look, Select · the Library"),
            Item(symbol: "command", gesture: "⌘Z ⇧⌘Z ⌘D ⌘G ⌘K", result: "Undo, redo, duplicate, group, key"),
            Item(symbol: "questionmark", gesture: "?", result: "This page")
        ])
    ]

    var body: some View {
        List {
            ForEach(Self.sections, id: \.0) { section in
                Section(section.0) {
                    ForEach(section.1) { item in
                        HStack(spacing: HmmSpacing.s) {
                            Image(systemName: item.symbol).foregroundStyle(Color.accentColor).frame(width: 28)
                            Text(item.gesture).font(.hmm(.body, weight: .semibold)).frame(width: 220, alignment: .leading)
                            Text(item.result).font(.hmm(.body)).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Gestures")
    }
}
