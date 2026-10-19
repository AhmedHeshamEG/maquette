import HmmDesign
import LoweyCore
import SwiftUI

/// Finish: glow, vignette, grain, grade, outlines over any Look, colour fringe, retro, textures, depth of field; and the print
/// language for any Look (L2): Ben-Day dots, line boil, focus by misregistration.
/// Applied identically on the stage and in exports.
struct FinishSection: View {
    let editor: EditorModel

    private var post: PostSettings { editor.look.post }

    var body: some View {
        PanelSection("Finish") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HmmSpacing.xs) {
                    ForEach(PostSettings.Preset.allCases) { preset in
                        ChoiceChip(title: preset.title, isOn: post == preset.settings) {
                            editor.updatePost { settings in
                                let keepDepth = settings.depthOfField
                                settings = preset.settings
                                settings.depthOfField = keepDepth
                            }
                        }
                    }
                }
            }
            row("Glow", \.bloom)
            row("Vignette", \.vignette)
            row("Grain", \.grain)
            row("Exposure", \.exposure, -2 ... 2)
            row("Contrast", \.contrast, -1 ... 1)
            row("Colour", \.saturation, -1 ... 1)
            row("Warmth", \.temperature, -1 ... 1)
            row("Outlines", \.outline)
            row("Colour fringe", \.chromaticAberration)
            row("Retro", \.retro)
            Picker("Texture", selection: Binding(get: { post.texture }, set: { texture in editor.updatePost { $0.texture = texture } })) {
                ForEach(PostSettings.Texture.allCases) { Text(LocalizedStringKey($0.title)).tag($0) }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("finish-texture")
            if post.texture != .none { row("Texture", \.textureStrength) }
            Toggle("Depth of field from the camera", isOn: Binding(get: { post.depthOfField }, set: { value in editor.updatePost { $0.depthOfField = value } }))
                .font(.hmm(.body))
        }
        PanelSection("Print") {
            row("Ben-Day dots", \.benDay)
            row("Line boil", \.boil)
            Toggle("Focus by misregistration", isOn: Binding(get: { post.misregistration }, set: { value in
                editor.updatePost { $0.misregistration = value }
            }))
            .font(.hmm(.body))
            .accessibilityIdentifier("finish-misregistration")
            Hint("On any Look: colour printed as dots, lines that tremble on twos, and out-of-focus things as slipped colour plates.")
        }
    }

    private func row(_ title: String, _ path: WritableKeyPath<PostSettings, Double>, _ range: ClosedRange<Double> = 0 ... 1) -> some View {
        LabeledSlider(title: title, value: post[keyPath: path], range: range, set: { value in
            editor.updatePost(coalesce: "post-\(title)") { $0[keyPath: path] = value }
        }, done: editor.endGesture)
    }
}

/// The world: sun, sky, ambient, fog, stars and ground.
struct WorldSection: View {
    let editor: EditorModel

    private var look: Look { editor.look }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Fog", isOn: Binding(get: { look.fog.enabled }, set: { value in editor.updateLook { $0.fog.enabled = value } }))
            if look.fog.enabled { slider("Fog distance", \.fog.distance, 5 ... 200) }
            slider("Stars", \.sky.stars, 0 ... 1)
            Toggle("Ground", isOn: Binding(get: { look.ground.visible }, set: { value in editor.updateLook { $0.ground.visible = value } }))
            RealSunSection(editor: editor)
            if look.lighting.realSun == nil {
                slider("Sun height", \.lighting.sunElevation, 2 ... 90)
                slider("Sun direction", \.lighting.sunAzimuth, 0 ... 360)
            }
            slider("Sun strength", \.lighting.sunIntensity, 0 ... 2)
            slider("Ambient", \.lighting.ambientIntensity, 0 ... 2)
            slider("Exposure", \.lighting.exposure, -2 ... 2)
            Toggle("Sun shadows", isOn: Binding(get: { look.lighting.sunShadows }, set: { value in editor.updateLook { $0.lighting.sunShadows = value } }))
            color("Sun colour", \.lighting.sunColor)
            color("Sky top", \.sky.top)
            color("Horizon", \.sky.horizon)
            color("Below", \.sky.bottom)
            color("Fog colour", \.fog.color)
            color("Ground colour", \.ground.color)
            slider("Ground size", \.ground.size, 5 ... 200)
        }
        .font(.hmm(.body))
    }

    private func slider(_ title: String, _ path: WritableKeyPath<Look, Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledSlider(title: title, value: look[keyPath: path], range: range, set: { value in
            editor.updateLook(coalesce: "look-\(title)") { $0[keyPath: path] = value }
        }, done: editor.endGesture)
    }

    private func color(_ title: String, _ path: WritableKeyPath<Look, RGBA>) -> some View {
        ColorPicker(title, selection: Binding(get: { look[keyPath: path].color }, set: { value in
            editor.updateLook(coalesce: "look-\(title)") { $0[keyPath: path] = RGBA(value) }
        }), supportsOpacity: false)
    }
}
