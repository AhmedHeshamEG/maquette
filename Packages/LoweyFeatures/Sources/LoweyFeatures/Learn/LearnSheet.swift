import HmmDesign
import SwiftUI

/// Learn, one place (from Home and from Actions): the tour, every gesture, and the switch for the short instructions
/// inside panels (on by default: a beginner needs them).
struct LearnSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage(HmmInstructions.storageKey) private var showsInstructions = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        dismiss()
                        app.startTour()
                    } label: {
                        Label("Take the tour", systemImage: "hand.wave")
                    }
                    .accessibilityIdentifier("learn-tour")
                    NavigationLink {
                        GestureGuide()
                    } label: {
                        Label("Gestures and shortcuts", systemImage: "hand.draw")
                    }
                    .accessibilityIdentifier("learn-gestures")
                } footer: {
                    Text("The tour takes a minute, on a real project: each step waits until you have done it.")
                }
                Section {
                    Toggle("Instructions in panels", isOn: $showsInstructions)
                        .accessibilityIdentifier("learn-instructions")
                } footer: {
                    Text("The short explanations under controls. Turn them off once you know your way around.")
                }
            }
            .navigationTitle("Learn")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
