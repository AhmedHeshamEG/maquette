import HmmDesign
import LoweyCore
import SwiftUI

/// Review notes on the stage (U8): a pin on each spot, its thread beside it when tapped, and the card for a note being
/// written. Drawn in the stage's own points, like the stage, so a pin sits on its spot as the view turns.
struct NotePins: View {
    @Bindable var editor: EditorModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                ForEach(editor.notePins, id: \.note.id) { pin in
                    NotePin(note: pin.note, number: number(of: pin.note), open: editor.together.openNote == pin.note.id) {
                        editor.openNote(pin.note.id)
                    }
                    .position(pin.point)
                    if editor.together.openNote == pin.note.id {
                        NoteThread(editor: editor, note: pin.note)
                            .frame(width: NoteThread.width)
                            .position(Self.cardCenter(beside: pin.point, in: geometry.size))
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                if let point = editor.draftPoint {
                    NotePin(note: nil, number: editor.baseScene.notes.count + 1, open: true) {}
                        .position(point)
                    NoteDraftCard(editor: editor)
                        .frame(width: NoteThread.width)
                        .position(Self.cardCenter(beside: point, in: geometry.size))
                }
            }
        }
        .animation(HmmMotion.snappy.animation(reduceMotion: reduceMotion), value: editor.together.openNote)
    }

    private func number(of note: ReviewNote) -> Int {
        (editor.baseScene.notes.firstIndex { $0.id == note.id } ?? 0) + 1
    }

    /// The card sits beside its pin (right of it, else left), inside the screen.
    static func cardCenter(beside point: CGPoint, in size: CGSize) -> CGPoint {
        let half = NoteThread.width / 2
        let right = point.x + 28 + half
        let x = right + half < size.width - 12 ? right : point.x - 28 - half
        let y = min(max(point.y + 60, 150), size.height - 150)
        return CGPoint(x: min(max(x, half + 12), size.width - half - 12), y: y)
    }
}

/// One pin: a numbered drop of the accent (faint and ticked once resolved).
private struct NotePin: View {
    let note: ReviewNote?
    let number: Int
    let open: Bool
    let action: () -> Void
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(note?.resolved == true ? theme.surface2 : theme.accent)
                Circle().stroke(open ? theme.text : Color.clear, lineWidth: 2)
                if note?.resolved == true {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.text2)
                } else {
                    Text(verbatim: "\(number)").font(.hmmNumbers(.caption, weight: .bold)).foregroundStyle(theme.onAccent)
                }
            }
            .frame(width: 28, height: 28)
            .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            .frame(width: HmmTarget.minimum, height: HmmTarget.minimum)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(note.map { "Note \(number) by \($0.author): \($0.text)" } ?? "New note"))
        .accessibilityIdentifier("note-pin-\(number)")
    }
}

/// A note's thread, answered in place: who wrote what, a reply, Resolve, Delete.
private struct NoteThread: View {
    static let width: CGFloat = 300

    let editor: EditorModel
    let note: ReviewNote
    @State private var reply = ""
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            HStack {
                Text(verbatim: note.author).font(.hmm(.subheadline, weight: .semibold))
                Text(note.date, format: .relative(presentation: .named)).font(.hmm(.caption)).foregroundStyle(theme.text2)
                Spacer()
                HmmButton("xmark", label: "Close", size: 32) { editor.together.openNote = nil }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: HmmSpacing.s) {
                    Text(verbatim: note.text).font(.hmm(.body))
                    ForEach(note.replies) { answer in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: answer.author).font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2)
                            Text(verbatim: answer.text).font(.hmm(.body))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 180)
            HStack(spacing: HmmSpacing.xs) {
                TextField("Reply", text: $reply)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit(send)
                    .accessibilityIdentifier("note-reply")
                HmmButton("arrow.up.circle.fill", label: "Send", size: 36, action: send)
                    .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                HmmPillButton(note.resolved ? "Reopen" : "Resolve", systemName: note.resolved ? "arrow.uturn.backward" : "checkmark") {
                    editor.setNoteResolved(note.id, !note.resolved)
                }
                .accessibilityIdentifier("note-resolve")
                Spacer()
                Button("Delete", role: .destructive) { editor.deleteNote(note.id) }
                    .font(.hmm(.body))
                    .accessibilityIdentifier("note-delete")
            }
        }
        .padding(HmmSpacing.m)
        .hmmPanelBackground(cornerRadius: HmmRadius.panel)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("note-thread")
    }

    private func send() {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        editor.replyToNote(note.id, text)
        reply = ""
    }
}

/// Writing a new note: the words, signed with your name, then Add.
private struct NoteDraftCard: View {
    @Bindable var editor: EditorModel
    @FocusState private var focused: Bool
    @Environment(\.hmmTheme) private var theme

    private var text: Binding<String> {
        Binding(get: { editor.together.draft?.text ?? "" }, set: { editor.together.draft?.text = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Text("A note from \(editor.yourName)").font(.hmm(.caption)).foregroundStyle(theme.text2)
            TextField("What should change here?", text: text, axis: .vertical)
                .lineLimit(2 ... 5)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .accessibilityIdentifier("note-text")
            HStack {
                Button("Cancel") { editor.together.draft = nil }
                Spacer()
                HmmPillButton("Add note", systemName: "mappin", prominent: true) { editor.commitNote() }
                    .accessibilityIdentifier("note-add")
            }
        }
        .padding(HmmSpacing.m)
        .hmmPanelBackground(cornerRadius: HmmRadius.panel)
        .onAppear { focused = true }
    }
}

/// While reviewing over FaceTime: who's here, and Leave.
struct ReviewBadge: View {
    let editor: EditorModel
    @Environment(AppModel.self) private var app
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        HStack(spacing: HmmSpacing.s) {
            Image(systemName: "shareplay").foregroundStyle(theme.accent)
            Text("Reviewing with \(max(app.review.people - 1, 1))").font(.hmm(.subheadline, weight: .semibold))
            Button("Leave") { app.review.leave() }.font(.hmm(.subheadline))
        }
        .padding(.horizontal, HmmSpacing.m)
        .frame(minHeight: HmmTarget.minimum)
        .hmmGlass(in: Capsule(), interactive: false)
        .padding(.top, HmmSpacing.s)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review-badge")
    }
}
