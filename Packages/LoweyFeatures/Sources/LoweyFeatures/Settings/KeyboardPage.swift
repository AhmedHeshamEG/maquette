import HmmDesign
import SwiftUI

/// Settings ▸ Keyboard (U8): every command a keyboard reaches, with its keys. Tap one and press the new keys; a key
/// another command had moves here and that one is left without (it says so). Hold a row for no key, or its own.
struct KeyboardPage: View {
    let keyboard: HmmKeyboard
    @State private var recording: HmmKeyCommand?
    @State private var note: String?
    @State private var search = ""

    private var menus: [String] {
        var seen = Set<String>()
        return keyboard.commands.map(\.menu).filter { seen.insert($0).inserted }
    }

    private func commands(in menu: String) -> [HmmKeyCommand] {
        keyboard.commands.filter { $0.menu == menu && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)) }
    }

    var body: some View {
        List {
            if let note {
                Section { Text(verbatim: note).font(.hmm(.footnote)) }
            }
            ForEach(menus, id: \.self) { menu in
                let shown = commands(in: menu)
                if !shown.isEmpty {
                    Section(LocalizedStringKey(menu)) {
                        ForEach(shown) { command in row(command) }
                    }
                }
            }
            Section {
                Button("Use the keys they came with", role: .destructive) {
                    keyboard.resetAll()
                    note = nil
                }
                .accessibilityIdentifier("keys-reset")
            }
        }
        .searchable(text: $search, prompt: Text("Find a command"))
        .navigationTitle("Keyboard")
        .sheet(item: $recording) { command in
            KeyRecordSheet(command: command, keyboard: keyboard) { recording = nil; note = $0 }
                .presentationDetents([.height(260)])
        }
    }

    private func row(_ command: HmmKeyCommand) -> some View {
        Button { recording = command } label: {
            HStack {
                Text(LocalizedStringKey(command.title))
                Spacer()
                Text(verbatim: keyboard.shownCombo(for: command)?.display ?? "—")
                    .font(.hmmNumbers(.body))
                    .foregroundStyle(.secondary)
            }
        }
        .contextMenu {
            Button("No key", systemImage: "nosign") { note = Self.moved(keyboard.bind(command, to: nil), combo: nil) }
            if command.standard != nil {
                Button("Its own key", systemImage: "arrow.uturn.backward") {
                    note = Self.moved(keyboard.reset(command), combo: command.standard)
                }
            }
        }
        .accessibilityIdentifier("key-\(command.id)")
    }

    /// What to tell when a key left other commands.
    static func moved(_ losers: [HmmKeyCommand], combo: HmmKeyCombo?) -> String? {
        guard let combo, !losers.isEmpty else { return nil }
        let names = losers.map { String(localized: String.LocalizationValue($0.title)) }.joined(separator: ", ")
        return String(localized: "\(combo.display) was for \(names), which has no key now")
    }
}

/// Listening for the new keys of one command.
private struct KeyRecordSheet: View {
    let command: HmmKeyCommand
    let keyboard: HmmKeyboard
    let done: (String?) -> Void
    @State private var problem: String?
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: HmmSpacing.m) {
            Text("Press the new keys for “\(String(localized: String.LocalizationValue(command.title)))”").font(.hmm(.headline))
                .multilineTextAlignment(.center)
            Text(verbatim: keyboard.shownCombo(for: command)?.display ?? "—").font(.hmmNumbers(.title)).foregroundStyle(theme.text2)
            if let problem { Text(verbatim: problem).font(.hmm(.footnote)).foregroundStyle(theme.text2) }
            Button("Cancel") { done(nil) }
            HmmKeyRecorder { combo in
                guard combo.isUsable else {
                    problem = String(localized: "Add ⌘, ⌃ or ⌥: a key on its own is for typing")
                    return
                }
                done(KeyboardPage.moved(keyboard.bind(command, to: combo), combo: combo))
            }
            .frame(width: 1, height: 1)
            .accessibilityHidden(true)
        }
        .padding(HmmSpacing.l)
        .onAppear { keyboard.isRecording = true }
        .onDisappear { keyboard.isRecording = false }
    }
}
