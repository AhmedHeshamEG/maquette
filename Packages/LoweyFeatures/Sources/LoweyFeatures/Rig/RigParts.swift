import HmmDesign
import LoweyCore
import SwiftUI

/// A loose object can become part of a drawn rig (an eye on a drawn head, a hat, something in a hand): it rides the
/// bone nearest to it, and as a face part it answers to the face.
struct PartSection: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if let object = editor.singleSelection {
            if let bone = object[.attachBone]?.stringValue {
                PanelSection("Part") { part(object, bone: bone) }
            } else {
                let hosts = editor.partHosts(for: object)
                if !hosts.isEmpty {
                    PanelSection("Make it part of") {
                        TileGrid(minimum: 96) {
                            ForEach(hosts, id: \.id) { host in
                                TileButton(title: host.name, systemName: "link", identifier: "part-of-\(host.name)") {
                                    editor.attachPart(object.id, to: host.id)
                                }
                            }
                        }
                        Hint("It will move with the nearest bone. An eye, a brow or a mouth can then follow your face.")
                    }
                }
            }
        }
    }

    @ViewBuilder private func part(_ object: SceneObject, bone: String) -> some View {
        let role = object[.faceRole]?.stringValue.flatMap(PartRole.init)
        Menu {
            Button("Nothing: it just rides the bone") { editor.setPartRole(nil, of: object.id) }
            Section("A part of the face") {
                ForEach(PartRole.features) { item in
                    Button(LocalizedStringKey(item.title)) { editor.setPartRole(item, of: object.id) }
                }
            }
            Section("One mouth of a set (they take turns)") {
                ForEach(PartRole.shapes) { item in
                    Button(LocalizedStringKey(item.title)) { editor.setPartRole(item, of: object.id) }
                }
            }
        } label: {
            Label(LocalizedStringKey(role?.title ?? "It rides its bone"), systemImage: "face.smiling").font(.hmm(.body, weight: .semibold))
        }
        .accessibilityIdentifier("part-role")
        if let parent = object.parent, let rig = editor.baseScene.objects[parent]?.rig {
            Menu {
                ForEach(rig.skeleton.names, id: \.self) { joint in
                    Button(joint) { editor.setPartBone(joint, of: object.id) }
                }
            } label: {
                Label("Bone: \(bone)", systemImage: "point.3.connected.trianglepath.dotted").font(.hmm(.body, weight: .semibold))
            }
            .accessibilityIdentifier("part-bone")
        }
        HmmPillButton("Take it off", systemName: "link.badge.plus", role: .destructive) { editor.detachPart(object.id) }
            .accessibilityIdentifier("part-detach")
    }
}

/// Rig ▸ Pose: the joint last touched on the stage can hang loose (hair, ears, a tail), with everything below it.
struct DangleControl: View {
    @Bindable var editor: EditorModel
    let character: ObjectID

    var body: some View {
        if let joint = editor.live.joint, joint.character == character {
            LabeledSlider(title: "Dangle", value: editor.dangle(of: joint.name, on: character), range: 0 ... 1, format: NumberFormat.percent,
                          set: { editor.setDangle($0, joint: joint.name, on: character) }, done: editor.endGesture)
                .accessibilityIdentifier("rig-dangle")
            Hint("The touched bone and everything below it hang loose: they trail when it moves and swing when it stops.")
        } else {
            Hint("Touch a joint on the stage to let it hang loose here: hair, ears, a tail.")
        }
    }
}
