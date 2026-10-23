import HmmDesign
import SwiftUI

/// Settings ▸ Your layout (U8): the hand you hold the Pencil in (left mirrors the canvas's chrome), each corner's
/// buttons in your order with any hidden, the sidebar's place, and one Reset layout. Buttons never change corner, and
/// the tutorials show the layout as it comes.
struct YourLayoutPage: View {
    @AppStorage(HmmHand.storageKey) private var hand = HmmHand.right.rawValue
    @AppStorage(ChromeGroup.document.storageKey) private var document = Data()
    @AppStorage(ChromeGroup.making.storageKey) private var making = Data()
    @AppStorage(ChromeGroup.view.storageKey) private var view = Data()
    @AppStorage(YourSettings.sidebarPlace) private var sidebarPlace = 0.0
    @State private var confirmsReset = false

    var body: some View {
        Form {
            Section {
                Picker("Hand", selection: $hand) {
                    ForEach(HmmHand.allCases) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("layout-hand")
            } header: {
                Text("The Pencil is in your")
            } footer: {
                Text(
                    "Left hand: the top corners swap, the sidebar moves right and the bottom corners swap. Words and time still read left to right."
                )
            }
            ForEach(ChromeGroup.allCases) { group in
                GroupSection(group: group, data: binding(group))
            }
            if sidebarPlace != 0 {
                Section {
                    Button("Put the sidebar back in the middle") { sidebarPlace = 0 }
                } footer: {
                    Text("Drag the short line under the sidebar to move it along its edge.")
                }
            }
            Section {
                Button("Reset layout", role: .destructive) { confirmsReset = true }
                    .accessibilityIdentifier("layout-reset")
            } footer: {
                Text("Back to the layout as it comes, the one the lessons show. Your keys and defaults stay.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Your layout")
        .confirmationDialog("Reset layout?", isPresented: $confirmsReset, titleVisibility: .visible) {
            Button("Reset layout", role: .destructive, action: reset)
                .accessibilityIdentifier("layout-reset-confirm")
        }
    }

    private func binding(_ group: ChromeGroup) -> Binding<Data> {
        switch group {
        case .document: $document
        case .making: $making
        case .view: $view
        }
    }

    private func reset() {
        YourSettings.resetLayout()
        hand = HmmHand.right.rawValue
        document = Data()
        making = Data()
        view = Data()
        sidebarPlace = 0
        HmmHaptics.play(.commit)
    }
}

/// One corner's buttons: drag to reorder, the menu to move one or hide it.
private struct GroupSection: View {
    let group: ChromeGroup
    @Binding var data: Data
    @Environment(\.hmmTheme) private var theme

    private var arrangement: HmmArrangement { ChromeGroup.arrangement(data) }

    var body: some View {
        Section {
            ForEach(arrangement.ordered(group.ids), id: \.self) { id in
                row(id)
            }
            .onMove { source, destination in
                change { $0.move(fromOffsets: source, toOffset: destination, in: group.ids) }
            }
        } header: {
            Text(LocalizedStringKey(group.title))
        } footer: {
            if group == .document {
                Text("Top to bottom is left to right. Home and Actions always stay.")
            }
        }
    }

    private func row(_ id: String) -> some View {
        let label = ChromeGroup.label(id)
        let hidden = arrangement.hidden.contains(id) && !group.fixed.contains(id)
        return HStack(spacing: HmmSpacing.s) {
            Image(systemName: label.systemImage).frame(width: 28)
            Text(LocalizedStringKey(label.title))
            Spacer()
            Menu {
                Button("Move left", systemImage: "arrow.left") { change { $0.move(id, by: -1, in: group.ids) } }
                    .accessibilityIdentifier("layout-left-\(id)")
                Button("Move right", systemImage: "arrow.right") { change { $0.move(id, by: 1, in: group.ids) } }
                    .accessibilityIdentifier("layout-right-\(id)")
                if !group.fixed.contains(id) {
                    Button(hidden ? "Show" : "Hide", systemImage: hidden ? "eye" : "eye.slash") { change { $0.setHidden(id, !hidden) } }
                        .accessibilityIdentifier("layout-hide-\(id)")
                }
            } label: {
                Image(systemName: hidden ? "eye.slash" : "ellipsis.circle").frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            }
            .accessibilityLabel(Text("\(label.title) options"))
            .accessibilityIdentifier("layout-menu-\(id)")
        }
        .foregroundStyle(hidden ? theme.text3 : theme.text)
    }

    private func change(_ body: (inout HmmArrangement) -> Void) {
        var arrangement = arrangement
        body(&arrangement)
        data = arrangement.isDefault ? Data() : (try? JSONEncoder().encode(arrangement)) ?? Data()
        HmmHaptics.play(.selection)
    }
}
