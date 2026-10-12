import HmmDesign
import SwiftUI

/// Settings, in order (CONTEXT §10.10): Pencil and hands · Gestures · Stage · Appearance · Assistant · About (with
/// Diagnostics inside), then where projects are kept.
struct SettingsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsDiagnostics = false

    var body: some View {
        NavigationStack {
            Form {
                PencilAndHandsSection()
                Section("Gestures") {
                    NavigationLink("Shortcuts, switched on and off") { GesturesPage() }
                        .accessibilityIdentifier("settings-gestures")
                }
                StageSettingsSection()
                AppearanceSection()
                if FeatureFlags.aiBridge { AssistantSection(app: app, close: { dismiss() }) }
                AboutSection { showsDiagnostics = true }
                StorageSection(app: app)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showsDiagnostics) { DiagnosticsSheet(app: app, editor: app.editor) }
        }
    }
}

/// Settings ▸ Assistant: the laptop bridge (an assistant such as Claude drives the app through MCP), Scripts and
/// Paste script, beside Hesham's note. It is off until it is turned on; a project must be open to pair or run scripts.
private struct AssistantSection: View {
    let app: AppModel
    let close: () -> Void

    var body: some View {
        Section {
            Toggle("Assistant on this network", isOn: Binding(get: { app.bridge.isOn }, set: { app.bridge.setOn($0) }))
                .accessibilityIdentifier("settings-assistant")
            if let editor = app.editor {
                Button("Pair a laptop, see proposals…") { open(.bridge, in: editor) }
                    .accessibilityIdentifier("open-bridge")
                Button("Scripts…") { open(.scripts, in: editor) }
                    .accessibilityIdentifier("open-scripts")
                Button("Paste a script") {
                    close()
                    editor.importScriptFromClipboard()
                }
                .accessibilityIdentifier("Paste script")
            }
        } header: {
            Text("Assistant")
        } footer: {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                Text("We think generative AI is bad for artists, and we stand with them. Nothing in Maquette makes art for you.")
                Text("This switch is for people in other fields who want an assistant to drive the app from their laptop. It stays off until you turn it on.")
            }
        }
    }

    private func open(_ sheet: EditorSheet, in editor: EditorModel) {
        close()
        // The settings sheet leaves first; the editor's next sheet follows it.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            editor.sheet = sheet
        }
    }
}
