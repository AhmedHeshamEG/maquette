import HmmDesign
import LoweyCore
import SwiftUI

/// The Reference window (CONTEXT §10.10) and the pictures pinned from the Board (§10.7), floating over the stage beside
/// the model. Drag a card to move it, its corner to size it, its fold button to fold it to a chip; with Pick in the
/// hand a tap takes its colour; touch and hold for its menu (trace it on the sheet, stand it in the scene). Drop a
/// picture on one for another. With the Board off only the Reference window's pictures stay.
struct ReferenceCards: View {
    @Bindable var editor: EditorModel
    let boardEnabled: Bool

    var body: some View {
        GeometryReader { geometry in
            ForEach(editor.references.filter { boardEnabled || $0.isWindow }) { card in
                if card.isFolded {
                    FoldedReference(editor: editor, card: card, stage: geometry.size)
                } else {
                    ReferenceCardView(editor: editor, card: card, stage: geometry.size)
                }
            }
        }
    }
}

/// A folded reference: a small chip with its picture; tap it to open it again.
private struct FoldedReference: View {
    let editor: EditorModel
    let card: ReferenceCard
    let stage: CGSize
    @State private var picture: UIImage?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button {
            editor.foldReference(card.id, folded: false)
        } label: {
            Group {
                if let picture { Image(uiImage: picture).resizable().scaledToFill() } else { theme.surface2 }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: HmmRadius.control, style: .continuous).strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .position(x: card.x * stage.width, y: card.y * stage.height)
        .accessibilityLabel(Text("Open the reference"))
        .accessibilityIdentifier("reference-folded")
        .task(id: card.image) { picture = UIImage(contentsOfFile: editor.referenceURL(card).path) }
    }
}

private struct ReferenceCardView: View {
    let editor: EditorModel
    let card: ReferenceCard
    let stage: CGSize
    @State private var picture: UIImage?
    @State private var moved = CGSize.zero
    @State private var widthWhileSizing: Double?
    @Environment(\.hmmTheme) private var theme

    private var width: Double { widthWhileSizing ?? card.width }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous) }

    var body: some View {
        content
            .frame(width: width, height: width * card.aspect)
            .clipShape(shape)
            .overlay(shape.strokeBorder(theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            .overlay(alignment: .bottomTrailing) { grip }
            .overlay(alignment: .topLeading) { fold }
            .contentShape(shape)
            .onTapGesture(coordinateSpace: .local) { location in pick(at: location) }
            .hmmHoldMenu(menu)
            .gesture(move)
            .dropDestination(for: Data.self) { items, _ in
                for item in items where UIImage(data: item) != nil {
                    editor.addReference(imageData: item)
                }
                return items.contains { UIImage(data: $0) != nil }
            }
            .position(x: card.x * stage.width + moved.width, y: card.y * stage.height + moved.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.title.isEmpty ? Text("Reference") : Text(verbatim: card.title))
            .accessibilityAddTraits(.isImage)
            .accessibilityIdentifier("reference-card")
            .task(id: card.image) {
                picture = UIImage(contentsOfFile: editor.referenceURL(card).path)
            }
    }

    @ViewBuilder private var content: some View {
        if let picture {
            Image(uiImage: picture)
                .resizable()
                .interpolation(.high)
        } else {
            theme.surface2
        }
    }

    /// Folds the card to a chip.
    private var fold: some View {
        Image(systemName: "chevron.down.right.and.arrow.up.left")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(width: 28, height: 28)
            .background(theme.surface.opacity(0.85), in: Circle())
            .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            .contentShape(Rectangle())
            .onTapGesture { editor.foldReference(card.id, folded: true) }
            .accessibilityElement()
            .accessibilityLabel(Text("Fold"))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("reference-fold")
    }

    /// With Pick (the sidebar's eyedropper) in the hand, a tap takes the picture's colour there.
    private func pick(at location: CGPoint) {
        guard editor.pickActive, let picture, width > 0 else { return }
        editor.pickColour(from: picture, at: CGPoint(x: location.x / width, y: location.y / max(width * card.aspect, 1)))
    }

    /// The corner that sizes the card.
    private var grip: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.text)
            .frame(width: 28, height: 28)
            .background(theme.surface.opacity(0.85), in: Circle())
            .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            .contentShape(Rectangle())
            .gesture(size)
            .accessibilityLabel("Resize")
            .accessibilityIdentifier("reference-card-resize")
    }

    private var move: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                moved = value.translation
            }
            .onEnded { value in
                var next = card
                next.x = card.x + value.translation.width / max(stage.width, 1)
                next.y = card.y + value.translation.height / max(stage.height, 1)
                moved = .zero
                editor.updateReference(next)
            }
    }

    private var size: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                widthWhileSizing = Self.sized(card.width, by: value.translation.width)
            }
            .onEnded { value in
                var next = card
                next.width = Self.sized(card.width, by: value.translation.width)
                widthWhileSizing = nil
                editor.updateReference(next)
            }
    }

    private static func sized(_ width: Double, by drag: Double) -> Double {
        min(max(width + drag, ReferenceCard.widthRange.lowerBound), ReferenceCard.widthRange.upperBound)
    }

    /// The hold menu, in the one grammar: a pinned picture can't be duplicated, renamed, copied or pasted over, so
    /// those rows are dimmed; its own two actions; Delete takes it off the stage.
    private var menu: HmmHoldMenu {
        var extras = [
            HmmHoldMenu.Item("Trace it on the sheet", id: "reference-trace", systemName: "square.on.square.dashed") { editor.traceReference(card) },
            HmmHoldMenu.Item("Stand it in the scene", id: "reference-stand", systemName: "photo.on.rectangle") { editor.standReferenceInScene(card) }
        ]
        if !card.isWindow {
            extras.append(HmmHoldMenu.Item("Open the board", id: "reference-open-board", systemName: "scribble.variable") { editor.openBoard() })
        }
        return HmmHoldMenu(extras: extras, delete: { editor.removeReference(card.id) })
    }
}
