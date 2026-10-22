#if canImport(SwiftUI)
    import HmmDesign
    import SwiftUI

    /// A Studio's About page: the thing's name and, when it came in a pack, who made it and what others may do with it.
    public struct HmmStudioAbout: View {
        @Binding private var name: String
        private let origin: HmmPackOrigin?
        private let note: String?
        @Environment(\.hmmTheme) private var theme

        /// `note`: one line of the app's own about the kind of thing (how it's made, what it keeps).
        public init(name: Binding<String>, origin: HmmPackOrigin? = nil, note: String? = nil) {
            _name = name
            self.origin = origin
            self.note = note
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("studio-name")
                if let origin {
                    VStack(alignment: .leading, spacing: HmmSpacing.xxs) {
                        Text("From “\(origin.pack)” by \(origin.author)")
                            .font(.hmm(.footnote, weight: .semibold))
                            .foregroundStyle(theme.text)
                        Text(verbatim: origin.licence.sentence(author: origin.author))
                            .font(.hmm(.footnote))
                            .foregroundStyle(theme.text2)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("studio-origin")
                }
                if let note {
                    Text(LocalizedStringKey(note)).font(.hmm(.footnote)).foregroundStyle(theme.text2)
                }
            }
        }
    }

    /// Sharing things as a pack: its name, who made it and what others may do with it. The author and licence are
    /// remembered by the app for next time; things from someone else's pack keep theirs whatever is chosen here.
    public struct HmmPackForm: View {
        @Binding private var name: String
        @Binding private var author: String
        @Binding private var licence: HmmLicence
        private let count: Int
        @Environment(\.hmmTheme) private var theme

        public init(name: Binding<String>, author: Binding<String>, licence: Binding<HmmLicence>, count: Int) {
            _name = name
            _author = author
            _licence = licence
            self.count = count
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.s) {
                TextField("Pack name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pack-name")
                TextField("Your name", text: $author)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("pack-author")
                HmmLicencePicker(licence: $licence)
                Text(verbatim: licence.sentence(author: author))
                    .font(.hmm(.footnote))
                    .foregroundStyle(theme.text2)
                Text("^[\(count) thing](inflect: true) in this pack. Packs hold only what you made: no code, nothing that runs.")
                    .font(.hmm(.footnote))
                    .foregroundStyle(theme.text3)
            }
        }
    }

    /// What others may do with a shared thing: four choices in words, the last one the author's own.
    public struct HmmLicencePicker: View {
        @Binding private var licence: HmmLicence

        public init(licence: Binding<HmmLicence>) {
            _licence = licence
        }

        public var body: some View {
            VStack(alignment: .leading, spacing: HmmSpacing.xs) {
                Picker("Others may", selection: Binding(get: { kind(of: licence) }, set: { licence = choice($0) })) {
                    ForEach(HmmLicence.choices.indices, id: \.self) { index in
                        Text(LocalizedStringKey(HmmLicence.choices[index].title)).tag(index)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("pack-licence")
                if case let .own(text) = licence {
                    TextField("In your own words", text: Binding(get: { text }, set: { licence = .own($0) }), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2 ... 4)
                }
            }
        }

        private func kind(of licence: HmmLicence) -> Int {
            HmmLicence.choices.firstIndex { $0.sameKind(as: licence) } ?? 0
        }

        private func choice(_ index: Int) -> HmmLicence {
            let picked = HmmLicence.choices[min(max(index, 0), HmmLicence.choices.count - 1)]
            if case .own = picked, case let .own(text) = licence { return .own(text) }
            return picked
        }
    }
#endif
