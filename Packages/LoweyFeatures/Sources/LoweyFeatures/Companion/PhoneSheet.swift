import HmmDesign
import HmmLink
import LoweyCore
import SwiftUI

/// Actions ▸ Your iPhone (U8): the iPhone beside the iPad. Open Maquette on the phone, on the same Wi-Fi, and it finds
/// this iPad; pick what it does here and the phone switches to it by itself.
struct PhoneSheet: View {
    @Bindable var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        NavigationStack {
            List {
                Section { status } footer: {
                    Text("Open \(AppIdentity.displayName) on your iPhone, on the same Wi-Fi as this iPad. Nothing leaves your network.")
                }
                Section("Use it as") {
                    ForEach(modes) { mode in
                        Button { choose(mode) } label: { row(mode) }
                            .accessibilityIdentifier("phone-\(mode.rawValue)")
                    }
                }
            }
            .navigationTitle("Your iPhone")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onAppear { editor.startCompanionLink() }
    }

    /// What this phone can do (all of them until it has said what it is).
    private var modes: [CompanionMode] {
        guard let phone = editor.together.phone else { return CompanionMode.allCases }
        return CompanionMode.allCases.filter { phone.abilities.can($0) }
    }

    private var status: some View {
        HStack(spacing: HmmSpacing.s) {
            Image(systemName: editor.together.phone == nil ? "iphone.slash" : "iphone.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(editor.together.phone == nil ? theme.text3 : theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: editor.together.phone?.name ?? String(localized: "Looking for your iPhone…")).font(.hmm(.headline))
                if let asked = editor.together.asked {
                    Text("Asked for: \(String(localized: String.LocalizationValue(asked.title)))").font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("phone-status")
    }

    private func row(_ mode: CompanionMode) -> some View {
        HStack(spacing: HmmSpacing.s) {
            Image(systemName: mode.systemImage).frame(width: 28).foregroundStyle(editor.together.asked == mode ? theme.accent : theme.text)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(mode.title)).font(.hmm(.body)).foregroundStyle(theme.text)
                Text(LocalizedStringKey(mode.subtitle)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
            }
        }
        .frame(minHeight: HmmTarget.minimum)
    }

    private func choose(_ mode: CompanionMode) {
        HmmHaptics.play(.selection)
        switch mode {
        case .face:
            editor.ask(.face)
            editor.startFaceCapture(useIPhone: true)
            dismiss()
        case .camera:
            editor.usePhoneAsCamera()
            dismiss()
        case .remote:
            editor.ask(.remote)
            dismiss()
            editor.startPresenting()
        case .augmented, .roomScan, .objectScan:
            editor.ask(mode)
        }
    }
}
