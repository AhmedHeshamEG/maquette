import HmmDesign
import SwiftUI

/// Settings ▸ Gestures: every hand shortcut with its switch (CONTEXT §10.10), the timeline's own two, and the full list.
struct GesturesPage: View {
    @AppStorage(AppSettings.timelineFingerSelects) private var fingerSelects = false
    @AppStorage(AppSettings.timelineHoverScrubs) private var hoverScrubs = true

    var body: some View {
        Form {
            Section {
                ForEach(HmmShortcut.allCases) { shortcut in
                    ShortcutToggle(shortcut: shortcut)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Each one can be switched off. Nothing here pops up on the screen: they are felt in the hand.")
            }
            Section("Timeline") {
                Toggle("Select with a finger (draw around keys and clips)", isOn: $fingerSelects)
                    .accessibilityIdentifier("settings-timeline-finger")
                Toggle("The Pencil's hover scrubs", isOn: $hoverScrubs)
            }
            Section {
                NavigationLink("Every gesture and shortcut") { GestureGuide() }
                    .accessibilityIdentifier("settings-gesture-guide")
            }
        }
        .navigationTitle("Gestures")
    }
}

private struct ShortcutToggle: View {
    let shortcut: HmmShortcut
    @AppStorage private var isOn: Bool

    init(shortcut: HmmShortcut) {
        self.shortcut = shortcut
        _isOn = AppStorage(wrappedValue: true, shortcut.storageKey)
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(shortcut.gesture))
                Text(LocalizedStringKey(shortcut.meaning)).font(.hmm(.footnote)).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("shortcut-\(shortcut.rawValue)")
    }
}
