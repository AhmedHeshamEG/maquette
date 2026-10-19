import HmmDesign
import HmmDocuments
import LoweyCore
import SwiftUI

/// The Effect Studio (L2, D-484), in the Studio grammar: the effect playing at the top (the same particles the stage
/// draws, seen from the side), then pages: Amount, Motion, Look, About. Edits go to the effect in Yours; things already
/// placed keep the recipe they were placed with.
struct EffectStudioView: View {
    let editor: EditorModel
    let id: String
    @State private var page: EffectStudioPage = .amount
    @State private var sharing: IdentifiedURL?
    @Environment(\.dismiss) private var dismiss

    private var effect: SavedEffect? { editor.library.manifest.effect(id) }

    var body: some View {
        if let effect {
            HmmStudio(effect.name, page: $page, identifier: "effect-studio", previewHeight: 220) {
                ParticlePreview(recipe: effect.recipe)
            } content: { page in
                EffectStudioPageView(editor: editor, effect: effect, page: page)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Share as a pack", systemImage: "square.and.arrow.up") {
                        sharing = editor.app.writePack([.effect(id)], name: effect.name, author: editor.app.packAuthor,
                                                       licence: editor.app.packLicence).map(IdentifiedURL.init)
                    }
                    Button("Add to the scene") {
                        editor.addSavedEffect(effect)
                        dismiss()
                    }
                    .accessibilityIdentifier("effect-studio-use")
                }
            }
            .sheet(item: $sharing) { ShareSheet(items: [$0.url]) }
        }
    }
}

enum EffectStudioPage: String, CaseIterable, HmmStudioPage {
    case amount, motion, look, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amount: "Amount"
        case .motion: "Motion"
        case .look: "Look"
        case .about: "About"
        }
    }
}

struct EffectStudioPageView: View {
    let editor: EditorModel
    let effect: SavedEffect
    let page: EffectStudioPage

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            switch page {
            case .amount:
                slider(effect.recipe.burst ? "Pieces" : "Per second", \.rate, 1 ... 400)
                slider("Lifetime", \.lifetime, 0.1 ... 8, format: { String(format: "%.1f s", $0) })
                Toggle("All at once", isOn: Binding(get: { effect.recipe.burst }, set: { on in change { $0.recipe.burst = on } }))
                Hint("All at once goes off at the moment it's placed, as an explosion does.")
            case .motion:
                slider("Speed", \.speed, 0 ... 12)
                slider("Spread", \.spread, 0 ... 180, format: { "\(Int($0))°" })
                slider("Gravity", \.gravity, -12 ... 6)
                slider("Air drag", \.drag, 0 ... 4)
                slider("Swirl", \.turbulence, 0 ... 2)
                slider("Where it starts", \.radius, 0 ... 3, format: { String(format: "%.2f m", $0) })
            case .look:
                slider("Size", \.size, 0.01 ... 2, format: { String(format: "%.2f m", $0) })
                slider("Size at the end", \.endSize, 0 ... 6, format: { String(format: "×%.1f", $0) })
                slider("Glow", \.glow, 0 ... 8)
                colour("First colour", index: 0)
                colour("Last colour", index: max(effect.recipe.colors.count - 1, 0))
                Picker("Shape", selection: Binding(get: { effect.recipe.shape }, set: { shape in change { $0.recipe.shape = shape } })) {
                    Text("Diamond").tag(ParticleRecipe.Shape.diamond)
                    Text("Streak").tag(ParticleRecipe.Shape.streak)
                    Text("Card").tag(ParticleRecipe.Shape.card)
                    Text("Puff").tag(ParticleRecipe.Shape.puff)
                }
                .pickerStyle(.segmented)
            case .about:
                HmmStudioAbout(name: Binding(get: { effect.name }, set: { value in change { $0.name = value } }),
                               origin: editor.library.origin(.effect, effect.id),
                               note: "Effects are drawn in the scene's Look and play the same on the stage and in every export.")
            }
        }
        .font(.hmm(.body))
    }

    private func change(_ edit: (inout SavedEffect) -> Void) {
        var edited = effect
        edit(&edited)
        editor.library.updateEffect(edited)
    }

    private func slider(_ title: String, _ path: WritableKeyPath<ParticleRecipe, Double>, _ range: ClosedRange<Double>,
                        format: @escaping (Double) -> String = { NumberFormat.short($0) }) -> some View {
        LabeledSlider(title: title, value: effect.recipe[keyPath: path], range: range, format: format) { value in
            change { $0.recipe[keyPath: path] = value }
        }
    }

    private func colour(_ title: String, index: Int) -> some View {
        ColorPicker(title, selection: Binding(get: { effect.recipe.colors[safe: index]?.color ?? .white }, set: { value in
            change { saved in
                guard saved.recipe.colors.indices.contains(index) else { return }
                let alpha = saved.recipe.colors[index].a
                var colour = RGBA(value)
                colour.a = alpha
                saved.recipe.colors[index] = colour
            }
        }), supportsOpacity: false)
    }
}

/// The effect playing, seen from the side, drawn from the same particles the stage draws.
struct ParticlePreview: View {
    let recipe: ParticleRecipe
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            Canvas { canvas, size in
                var playing = recipe
                let cycle = max(recipe.lifetime * 1.6, 0.5)
                let clock = context.date.timeIntervalSinceReferenceDate
                let time = recipe.burst ? clock.truncatingRemainder(dividingBy: cycle) : clock.truncatingRemainder(dividingBy: 600) + cycle
                playing.burstTime = 0
                let bounds = ParticleSimulator.bounds(playing)
                let reach = max(bounds.max.x - bounds.min.x, bounds.max.y - bounds.min.y, 0.5)
                let scale = Double(min(size.width, size.height)) * 0.9 / reach
                let floor = Double(size.height) * 0.92
                for particle in ParticleSimulator.particles(playing, at: time) {
                    let x = Double(size.width) / 2 + particle.position.x * scale
                    let y = floor - (particle.position.y - bounds.min.y) * scale
                    let radius = max(particle.size * scale * 0.5, 1)
                    let colour = particle.color
                    canvas.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                with: .color(Color(.sRGB, red: colour.r, green: colour.g, blue: colour.b, opacity: colour.a)))
                }
            }
        }
        .background(Color.black.opacity(0.85))
        .accessibilityLabel(Text("The effect playing"))
    }
}
