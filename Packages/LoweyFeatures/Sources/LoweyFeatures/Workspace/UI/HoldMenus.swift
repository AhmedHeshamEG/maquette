import HmmDesign
import LoweyCore
import SwiftUI

/// A hold-menu row's action when the thing can do it; nil, a dimmed row, when it can't. (A closure and `nil` in a
/// ternary is more than the type checker will work out for a main-actor action.)
@MainActor
func holdAction(if possible: Bool, _ action: @escaping @MainActor () -> Void) -> (@MainActor () -> Void)? {
    possible ? action : nil
}

/// The hold menus of the things in a scene, in the one grammar (CONTEXT §4.1; the kit's `HmmHoldMenu`): Duplicate,
/// Rename, Copy and Paste first, then what fits the thing, Delete last. An object has the same menu on the stage, in
/// the outliner and on its timeline row.
extension EditorModel {
    /// The menu of some objects. Acting on it makes them the selection first.
    func holdMenu(for ids: [ObjectID], extras custom: [HmmHoldMenu.Item]? = nil) -> HmmHoldMenu {
        let objects = ids.compactMap { scene.objects[$0] }
        return HmmHoldMenu(duplicate: on(ids) { $0.duplicateSelection() },
                           rename: holdAction(if: objects.count == 1) { [weak self] in self?.renamingObject = ids.first },
                           copy: on(ids) { $0.copySelection() },
                           paste: holdAction(if: canPaste) { [weak self] in self?.paste() },
                           extras: custom ?? objectExtras(ids, objects),
                           delete: on(ids) { $0.deleteSelection() })
    }

    /// A finger held still on the stage with the Select tool: the menu of the object under it (nil: nothing there, or
    /// a tool that holds for something else). The held object becomes the selection unless it's already part of it;
    /// when other things were selected, the first extra adds it to them instead.
    func stageHoldMenu(at point: CGPoint) -> HmmHoldMenu? {
        if drawsOnSheet, !pickActive, let stage, stage.pickObject(at: point) == nil { return sheetHoldMenu() }
        guard tool == .select, !pickActive, performPhase == .idle, !flying, historyScrub == nil, let stage else { return nil }
        guard let id = overlayHit(at: point) ?? stage.pickObject(at: point)?.0 else { return emptyStageMenu() }
        HmmHaptics.play(.selection)
        if selection.contains(id) { return holdMenu(for: selection) }
        let before = selection
        select(id)
        var menu = holdMenu(for: [id])
        if !before.isEmpty {
            let add = HmmHoldMenu.Item("Add to the selection", systemName: "plus.circle") { [weak self] in self?.setSelection(before + [id]) }
            menu.extras = [add] + menu.extras.prefix(HmmHoldMenu.maximumExtras - 1)
        }
        return menu
    }

    /// The empty stage (U5: where the Select button's lasso and Select all went): paste, the lasso, everything.
    func emptyStageMenu() -> HmmHoldMenu {
        HmmHoldMenu(paste: holdAction(if: canPaste) { [weak self] in self?.paste() }, extras: [
            HmmHoldMenu.Item("Lasso", systemName: "lasso") { [weak self] in self?.startLasso() },
            HmmHoldMenu.Item("Select all", systemName: "checkmark.circle") { [weak self] in self?.selectAll() }
        ])
    }

    /// The sheet's own menu (U5: its place, shape and guide live here; the floating bar went): nearer, farther, facing
    /// you; its shape; its guide. Rename and delete when it's kept.
    func sheetHoldMenu() -> HmmHoldMenu? {
        guard let sheet = currentSheet else { return nil }
        HmmHaptics.play(.selection)
        let place = HmmHoldMenu.Item("Place", systemName: "arrow.up.and.down", children: [
            HmmHoldMenu.Item("Nearer", systemName: "arrow.down") { [weak self] in self?.nudgeSheet(nearer: true) },
            HmmHoldMenu.Item("Farther", systemName: "arrow.up") { [weak self] in self?.nudgeSheet(nearer: false) },
            HmmHoldMenu.Item("Face me", systemName: "person.crop.square") { [weak self] in self?.faceSheet() }
        ])
        let shapes = DrawingSheet.Shape.allCases.filter { $0 != .onObject || sheet.object != nil }.map { shape in
            HmmHoldMenu.Item(shape.title, systemName: shape.systemImage) { [weak self] in self?.setSheetShape(shape) }
        }
        var guides = [HmmHoldMenu.Item("No guide", systemName: "square") { [weak self] in self?.setPlaneGuide(nil) }]
        if sheet.shape == .flat {
            guides += [DrawingGuide.Kind.grid, .isometric, .symmetry].map { kind in
                HmmHoldMenu.Item(kind.title, systemName: kind.systemImage) { [weak self] in self?.setPlaneGuide(DrawingGuide(kind: kind)) }
            }
        }
        return HmmHoldMenu(rename: holdAction(if: sheetIsKept) { [weak self] in self?.renamingSheet = sheet.id },
                           extras: [place, HmmHoldMenu.Item("Shape", systemName: sheet.shape.systemImage, children: shapes),
                                    HmmHoldMenu.Item("Guide", systemName: "grid", children: guides)],
                           delete: holdAction(if: sheetIsKept) { [weak self] in self?.deleteSheet(sheet.id) })
    }

    /// A key on the timeline (with the other picked keys, when it is one of them).
    func holdMenu(forKey key: KeyRef) -> HmmHoldMenu {
        if !selectedKeys.contains(key) { selectedKeys = [key] }
        // Moves ease by default; four named feels, and the curve itself one step deeper (CONTEXT §10.10).
        let feels = KeyFeel.allCases.map { feel in
            HmmHoldMenu.Item(feel.title, systemName: feel.systemImage) { [weak self] in self?.setEasing(feel.easing) }
        }
        let curve = HmmHoldMenu.Item("Curve…", systemName: "point.topleft.down.to.point.bottomright.curvepath") { [weak self] in self?.graphKey = key }
        let easing = HmmHoldMenu.Item("Feel", systemName: "waveform.path", children: feels + [curve])
        let several = selectedKeys.count > 1
        return HmmHoldMenu(copy: { [weak self] in self?.copyKeys() },
                           paste: holdAction(if: hasKeyClipboard) { [weak self] in self?.pasteKeys() },
                           extras: [easing,
                                    HmmHoldMenu.Item("Reverse", systemName: "arrow.uturn.backward", isEnabled: several) { [weak self] in self?.reverseKeys() },
                                    HmmHoldMenu.Item("Mirror (there and back)", systemName: "arrow.left.and.right", isEnabled: several) { [weak self] in
                                        self?.mirrorKeys()
                                    }],
                           delete: { [weak self] in self?.deleteSelectedKeys() })
    }

    /// A clip on a character's timeline row (with the other picked clips, when it is one of them).
    func holdMenu(forClip segment: ClipSegment) -> HmmHoldMenu {
        if !selectedClips.contains(segment.id) { selectedClips = [segment.id] }
        let inside = time > segment.start + 0.01 && time < segment.end - 0.01
        return HmmHoldMenu(extras: [
            HmmHoldMenu.Item("Split at the playhead", systemName: "scissors", isEnabled: inside) { [weak self] in self?.splitClip(segment.id) },
            HmmHoldMenu.Item(segment.loop ? "Play once" : "Loop", systemName: "repeat") { [weak self] in self?.setPickedClips(loop: !segment.loop) }
        ], delete: { [weak self] in self?.removePickedClips() })
    }

    /// One drawing of a flipbook.
    func holdMenu(forFlipbookDrawing index: Int, of track: String) -> HmmHoldMenu {
        func there(_ action: @escaping @MainActor (EditorModel) -> Void) -> @MainActor () -> Void {
            { [weak self] in
                guard let self else { return }
                showFlipbookDrawing(index, of: track)
                action(self)
            }
        }
        return HmmHoldMenu(duplicate: there { $0.duplicateFlipbookDrawing() }, extras: [
            HmmHoldMenu.Item("Hold longer", systemName: "plus", action: there { $0.changeFlipbookHold(by: 1) }),
            HmmHoldMenu.Item("Hold shorter", systemName: "minus", action: there { $0.changeFlipbookHold(by: -1) })
        ], delete: there { $0.deleteFlipbookDrawing() })
    }

    /// Cuts a clip in two at the playhead; the second half goes on from where the first stops.
    func splitClip(_ id: String) {
        let moment = time
        updateTimeline("Split clip") { timeline in
            for track in timeline.clipTracks.indices {
                guard let index = timeline.clipTracks[track].segments.firstIndex(where: { $0.id == id }) else { continue }
                let whole = timeline.clipTracks[track].segments[index]
                guard moment > whole.start + 0.01, moment < whole.end - 0.01 else { return }
                var first = whole
                first.duration = moment - whole.start
                var second = whole
                second.id = UUID().uuidString.lowercased()
                second.start = moment
                second.duration = whole.end - moment
                second.offset = whole.offset + (moment - whole.start) * whole.speed
                second.blend = 0
                timeline.clipTracks[track].segments[index] = first
                timeline.clipTracks[track].segments.insert(second, at: index + 1)
            }
        }
    }

    private func on(_ ids: [ObjectID], _ action: @escaping @MainActor (EditorModel) -> Void) -> @MainActor () -> Void {
        { [weak self] in
            guard let self else { return }
            if selection != ids { setSelection(ids) }
            action(self)
        }
    }

    /// Hide and Lock (Show, Unlock when that's what they'd undo), then More: everything else an object can do, so the
    /// one menu holds it all (CONTEXT §10.10: Group, Array, To the ground, Swap, Save to the library, Unpack).
    private func objectExtras(_ ids: [ObjectID], _ objects: [SceneObject]) -> [HmmHoldMenu.Item] {
        let hidden = !objects.isEmpty && objects.allSatisfy { !$0.isVisible }
        let locked = !objects.isEmpty && objects.allSatisfy(\.isLocked)
        return [
            HmmHoldMenu.Item(hidden ? "Show" : "Hide", systemName: hidden ? "eye" : "eye.slash") { [weak self] in
                guard let self else { return }
                perform(operations.setFlag(ids, key: .visible, hidden))
            },
            HmmHoldMenu.Item(locked ? "Unlock" : "Lock", systemName: locked ? "lock.open" : "lock") { [weak self] in
                guard let self else { return }
                perform(operations.setFlag(ids, key: .locked, !locked))
            },
            HmmHoldMenu.Item("More", systemName: "ellipsis.circle", children: moreItems(ids, objects))
        ]
    }

    /// The rest of an object's menu; only what these objects can do is listed.
    private func moreItems(_ ids: [ObjectID], _ objects: [SceneObject]) -> [HmmHoldMenu.Item] {
        var items: [HmmHoldMenu.Item] = []
        if objects.count == 1, objects[0].kind == .group {
            items.append(HmmHoldMenu.Item("Ungroup", systemName: "square.on.square.dashed", action: on(ids) { $0.ungroupSelection() }))
        } else if objects.count > 1 {
            items.append(HmmHoldMenu.Item("Group", systemName: "square.on.square", action: on(ids) { $0.groupSelection() }))
        }
        items.append(HmmHoldMenu.Item("Array", systemName: "square.grid.3x3", children: arrayItems(ids)))
        items.append(HmmHoldMenu.Item("To the ground", systemName: "arrow.down.to.line", action: on(ids) { $0.dropSelectionToGround() }))
        items.append(HmmHoldMenu.Item("Settle", systemName: "cube.transparent", action: on(ids) { $0.settleSelection() }))
        if objects.count == 1, case .primitive = objects[0].kind {
            items.append(HmmHoldMenu.Item("Swap for a model…", systemName: "arrow.triangle.swap", action: on(ids) { $0.beginSwap() }))
        }
        items.append(HmmHoldMenu.Item("Save to the library…", systemName: "tray.and.arrow.down", action: on(ids) { $0.savingPrefab = true }))
        if objects.contains(where: { $0.kind.prefabID != nil }) {
            items.append(HmmHoldMenu.Item("Unpack", systemName: "shippingbox", action: on(ids) { $0.unpackSelection() }))
        }
        return items
    }

    /// Copies in a row, a grid, a circle or along a sketch.
    private func arrayItems(_ ids: [ObjectID]) -> [HmmHoldMenu.Item] {
        let step = arrayStep
        var items = [
            HmmHoldMenu.Item("Row of 5", action: on(ids) { $0.array(.line(count: 5, step: Vec3(step, 0, 0))) }),
            HmmHoldMenu.Item("Row of 10", action: on(ids) { $0.array(.line(count: 10, step: Vec3(step, 0, 0))) }),
            HmmHoldMenu.Item("Grid 3 × 3", action: on(ids) { $0.array(.grid(columns: 3, rows: 3, spacingX: step, spacingZ: step)) }),
            HmmHoldMenu.Item("Grid 5 × 5", action: on(ids) { $0.array(.grid(columns: 5, rows: 5, spacingX: step, spacingZ: step)) }),
            HmmHoldMenu.Item("Circle of 8", action: on(ids) { $0.array(.circle(count: 8, radius: max(step * 1.5, 1), faceCenter: true)) }),
            HmmHoldMenu.Item("Circle of 12", action: on(ids) { $0.array(.circle(count: 12, radius: max(step * 2, 1.5), faceCenter: true)) })
        ]
        if !sketches.isEmpty {
            items.append(HmmHoldMenu.Item("Along a sketch", action: on(ids) { $0.arrayAlongSketch(align: false) }))
            items.append(HmmHoldMenu.Item("Along a sketch, turning with it", action: on(ids) { $0.arrayAlongSketch(align: true) }))
        }
        return items
    }
}

/// Save to the library, wherever it was asked for (an object's menu on the stage, in the outliner, in its panel).
struct PrefabSaveAlert: ViewModifier {
    @Bindable var editor: EditorModel
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: editor.savingPrefab) { _, saving in
                if saving { name = editor.singleSelection?.name ?? "" }
            }
            .alert("Save to your library", isPresented: $editor.savingPrefab) {
                TextField("Name", text: $name)
                Button("Save a copy") { editor.saveSelectionAsPrefab(name: name, replaceSelection: false) }
                Button("Save & link") { editor.saveSelectionAsPrefab(name: name, replaceSelection: true) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Build once, reuse it everywhere. Linked copies update when you edit the original.")
            }
    }
}

/// Rename, wherever it was asked for (a hold menu on the stage, in the outliner, on a timeline row).
struct ObjectRenameAlert: ViewModifier {
    @Bindable var editor: EditorModel
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .onChange(of: editor.renamingObject) { _, id in
                if let id { name = editor.scene.objects[id]?.name ?? "" }
            }
            .alert("Rename", isPresented: Binding(get: { editor.renamingObject != nil }, set: { if !$0 { editor.renamingObject = nil } })) {
                TextField("Name", text: $name)
                Button("Rename") {
                    if let id = editor.renamingObject { editor.rename(id, to: name) }
                    editor.renamingObject = nil
                }
                Button("Cancel", role: .cancel) { editor.renamingObject = nil }
            }
    }
}
