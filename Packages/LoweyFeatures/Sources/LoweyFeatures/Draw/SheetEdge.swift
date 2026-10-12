import HmmDesign
import LoweyCore
import SwiftUI

/// The control on the sheet's edge (CONTEXT §10.10), under the middle of its bottom edge: the grip that pushes the
/// sheet nearer or farther, its four shapes, and the sheets kept in the scene (choose one to draw on it again, a new
/// one, rename, delete).
struct SheetEdgeControl: View {
    let editor: EditorModel
    @State private var gesture: String?
    @State private var travelled: CGFloat = 0
    @State private var renaming = false
    @State private var name = ""

    var body: some View {
        GeometryReader { geometry in
            if let point = editor.sheetEdgePoint, let sheet = editor.currentSheet {
                bar(sheet)
                    .fixedSize()
                    .position(Self.clamped(CGPoint(x: point.x, y: point.y + 30), in: geometry.size))
            }
        }
        .alert("Rename the sheet", isPresented: $renaming) {
            TextField("Name", text: $name)
            Button("Rename") { if let id = editor.currentSheet?.id { editor.renameSheet(id, to: name) } }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func bar(_ sheet: DrawingSheet) -> some View {
        HStack(spacing: HmmSpacing.xxs) {
            grip
            ForEach(Self.shapes(for: sheet)) { shape in
                HmmButton(shape.systemImage, label: shape.title, isOn: sheet.shape == shape, size: 36) { editor.setSheetShape(shape) }
                    .accessibilityIdentifier("sheet-\(shape.rawValue)")
            }
            menu(sheet)
        }
        .padding(HmmSpacing.xxs)
        .environment(\.hmmInsideGlass, true)
        .hmmGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sheet-edge")
    }

    /// Drag down to bring the sheet nearer, up to push it away.
    private var grip: some View {
        Image(systemName: "arrow.up.and.down")
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 44, height: 36)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let key = gesture ?? UUID().uuidString
                        if gesture == nil {
                            gesture = key
                            travelled = 0
                        }
                        editor.pushSheet(byPoints: Double(value.translation.height - travelled), gesture: key)
                        travelled = value.translation.height
                    }
                    .onEnded { _ in
                        gesture = nil
                        editor.endGesture()
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Push the sheet nearer or farther"))
            .accessibilityAdjustableAction { direction in
                let key = UUID().uuidString
                editor.pushSheet(byPoints: direction == .increment ? 40 : -40, gesture: key)
                editor.endGesture()
            }
            .accessibilityIdentifier("sheet-grip")
    }

    private func menu(_ sheet: DrawingSheet) -> some View {
        Menu {
            Section("Sheets") {
                ForEach(editor.baseScene.sheets) { kept in
                    Button {
                        editor.chooseSheet(kept.id)
                    } label: {
                        if kept.id == sheet.id {
                            Label(kept.name, systemImage: "checkmark")
                        } else {
                            Text(verbatim: kept.name)
                        }
                    }
                }
                Button("New sheet", systemImage: "plus") { editor.newSheet() }
            }
            if sheet.shape == .around || sheet.shape == .dome {
                Button("Curve more", systemImage: "arrow.down.right.and.arrow.up.left") {
                    editor.setSheetRadius(sheet.radius * 0.75, gesture: UUID().uuidString)
                }
                Button("Curve less", systemImage: "arrow.up.left.and.arrow.down.right") {
                    editor.setSheetRadius(sheet.radius / 0.75, gesture: UUID().uuidString)
                }
            }
            Button("Rename", systemImage: "pencil") {
                name = sheet.name
                renaming = true
            }
            if editor.sheetIsKept {
                Button("Delete the sheet and its drawings", systemImage: "trash", role: .destructive) { editor.deleteSheet(sheet.id) }
            }
        } label: {
            HStack(spacing: 4) {
                Text(verbatim: sheet.name).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .font(.hmm(.caption, weight: .semibold))
            .padding(.horizontal, HmmSpacing.xs)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text("Sheet: \(sheet.name)"))
        .accessibilityIdentifier("sheet-menu")
    }

    /// Flat, around and dome everywhere; "on the object" when it lies on one.
    static func shapes(for sheet: DrawingSheet) -> [DrawingSheet.Shape] {
        DrawingSheet.Shape.allCases.filter { $0 != .onObject || sheet.object != nil }
    }

    /// Kept whole on screen.
    static func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: min(max(point.x, 150), max(size.width - 150, 150)), y: min(max(point.y, 120), max(size.height - 110, 120)))
    }
}
