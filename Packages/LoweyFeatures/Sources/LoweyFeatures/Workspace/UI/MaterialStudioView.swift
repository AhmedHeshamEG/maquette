import HmmDesign
import LoweyCore
import LoweyEngine
import SwiftUI

/// The Material Studio (U7, D-343), in the Brush Studio's grammar: the ball at the top changing as you go, then pages —
/// Look (the two colours), Surface (roughness, metal, glow), Pattern (which, how big, how strong), Bumps, About. Edits go
/// to the library at once; things already filled keep the copy they were filled with.
struct MaterialStudioView: View {
    let materials: MaterialModel
    let id: String
    /// Fills the thing being painted with the material as it is now.
    let use: (PaintMaterial) -> Void
    @State private var page: Page = .look
    @State private var ball: CGImage?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme

    enum Page: String, CaseIterable, Identifiable {
        case look, surface, pattern, bumps, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .look: "Look"
            case .surface: "Surface"
            case .pattern: "Pattern"
            case .bumps: "Bumps"
            case .about: "About"
            }
        }
    }

    private var material: PaintMaterial {
        materials.material(id) ?? PaintMaterial(id: id, name: "Material", color: .white)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HmmSpacing.m) {
                    HStack {
                        Spacer()
                        Group {
                            if let ball {
                                Image(decorative: ball, scale: 1)
                            } else {
                                Circle().fill(material.color.color).padding(20)
                            }
                        }
                        .frame(width: 180, height: 180)
                        .accessibilityLabel(Text("A ball of \(material.name)"))
                        Spacer()
                    }
                    Picker("Settings", selection: $page) {
                        ForEach(Page.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("material-studio-pages")
                    pageView
                }
                .padding(HmmSpacing.l)
            }
            .navigationTitle(Text(material.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fill with it") {
                        use(material)
                        dismiss()
                    }
                    .accessibilityIdentifier("material-studio-use")
                }
            }
            .task(id: "\(material.hashValue)") {
                try? await Task.sleep(for: .milliseconds(60))
                ball = MaterialModel.cgImage(MaterialPreview.render(material, size: 180))
            }
        }
        .accessibilityIdentifier("material-studio")
    }

    @ViewBuilder private var pageView: some View {
        switch page {
        case .look:
            colourRow("Colour", \.color)
            colourRow("Second colour", \.secondColor)
        case .surface:
            slider("Roughness", \.roughness, hint: "Smooth surfaces shine; rough ones don't.")
            slider("Metal", \.metal, hint: "Metal takes its colour into its shine and mirrors the sky.")
            colourRow("Glow", \.glow)
        case .pattern:
            FlowChips(items: MaterialPattern.allCases.map { ($0.rawValue, $0.title) }, isOn: { $0 == material.pattern.rawValue }) { key in
                change { $0.pattern = MaterialPattern(rawValue: key) ?? .none }
            }
            LabeledSlider(title: "Size", value: material.scale, range: 0.01 ... 2, format: { String(format: "%.2f m", $0) }) { value in
                change { $0.scale = value }
            }
            slider("Strength", \.variation, hint: "How much the second colour shows through the pattern.")
        case .bumps:
            slider("Bumps", \.bumps, hint: "How deep the pattern's relief is: it catches the light.")
        case .about:
            TextField("Name", text: Binding(get: { material.name }, set: { value in change { $0.name = value } }))
                .textFieldStyle(.roundedBorder)
            TextField("Author", text: Binding(get: { material.author ?? "" }, set: { value in change { $0.author = value.isEmpty ? nil : value } }))
                .textFieldStyle(.roundedBorder)
            Hint("Materials are made procedurally: they wrap round any shape with no seams. Things you fill keep their own copy.")
        }
    }

    private func change(_ edit: (inout PaintMaterial) -> Void) {
        var edited = material
        edit(&edited)
        materials.update(edited)
    }

    private func slider(_ title: String, _ key: WritableKeyPath<PaintMaterial, Double>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
            LabeledSlider(title: title, value: material[keyPath: key], range: 0 ... 1, format: NumberFormat.percent) { value in
                change { $0[keyPath: key] = value }
            }
            Hint(hint)
        }
    }

    private func colourRow(_ title: String, _ key: WritableKeyPath<PaintMaterial, RGBA>) -> some View {
        HStack {
            Text(LocalizedStringKey(title)).font(.hmm(.body))
            Spacer()
            ColorPicker(title, selection: Binding(get: { material[keyPath: key].color }, set: { value in
                let resolved = UIColor(value).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                change { $0[keyPath: key] = RGBA(Double(red), Double(green), Double(blue)) }
            }), supportsOpacity: false)
                .labelsHidden()
        }
        .frame(minHeight: HmmTarget.minimum)
    }
}
