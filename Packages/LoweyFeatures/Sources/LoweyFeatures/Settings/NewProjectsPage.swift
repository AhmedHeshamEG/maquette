import HmmDesign
import LoweyCore
import SwiftUI

/// Settings ▸ New projects (U8): what the + on Home makes: the set-up, the Look, the units and the brush in the hand.
/// The quiet row under Home's title still starts a set-up as it comes (its own Look and units for its job).
struct NewProjectsPage: View {
    let app: AppModel
    @AppStorage(YourSettings.defaultSetUp) private var setUp = StarterTemplate.Kind.blank.rawValue
    @AppStorage(YourSettings.defaultLook) private var look = ""
    @AppStorage(YourSettings.defaultUnits) private var units = ""
    @AppStorage(YourSettings.defaultBrush) private var brush = ""

    var body: some View {
        Form {
            Section {
                Picker("Set up for", selection: $setUp) {
                    ForEach(StarterTemplate.setUps, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0.rawValue) }
                }
                .accessibilityIdentifier("defaults-setup")
                Picker("Look", selection: $look) {
                    Text("The set-up's own").tag("")
                    ForEach(LookPreset.all(custom: [])) { Text(LocalizedStringKey($0.name)).tag($0.id) }
                }
                .accessibilityIdentifier("defaults-look")
                Picker("Units", selection: $units) {
                    Text("The set-up's own").tag("")
                    ForEach(LengthUnit.allCases, id: \.self) { Text(verbatim: $0.symbol).tag($0.rawValue) }
                }
                .accessibilityIdentifier("defaults-units")
                Picker("Brush", selection: $brush) {
                    Text("The last one used").tag("")
                    ForEach(brushes, id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
                .accessibilityIdentifier("defaults-brush")
            } footer: {
                Text("The + on Home makes this. Change any of it in the project afterwards.")
            }
        }
        .navigationTitle("New projects")
    }

    /// The drawing brushes, in the library's order.
    private var brushes: [Brush] {
        app.brushes.library.sets.filter { !$0.paintsSurfaces }.flatMap(\.brushes).compactMap { app.brushes.library.brush($0) }
    }
}
