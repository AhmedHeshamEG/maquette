#if canImport(SwiftUI)
    import SwiftUI

    /// A page of a Studio: its title on the page picker.
    public protocol HmmStudioPage: Hashable, CaseIterable, Identifiable where AllCases: RandomAccessCollection {
        var title: String { get }
    }

    /// The Studio grammar (Maquette 0.24): one shape for every place a library thing is made. The thing itself at the
    /// top, changing as you go (a pad to draw on, a ball, a scene in the Look, a burst of the effect); its settings
    /// under it in pages, one page at a time; About last (name, author, licence). The app's toolbar sits on top
    /// (Done, and the one thing to do with it: draw with it, fill with it, use it). Edits apply at once.
    public struct HmmStudio<Page: HmmStudioPage, Preview: View, Content: View>: View {
        private let title: String
        @Binding private var page: Page
        private let identifier: String
        private let previewHeight: CGFloat
        private let preview: Preview
        private let content: (Page) -> Content
        @Environment(\.hmmTheme) private var theme

        /// `identifier` names the Studio for UI tests (`<identifier>` on the whole, `<identifier>-pages` on the picker).
        public init(_ title: String, page: Binding<Page>, identifier: String, previewHeight: CGFloat = 200,
                    @ViewBuilder preview: () -> Preview, @ViewBuilder content: @escaping (Page) -> Content) {
            self.title = title
            _page = page
            self.identifier = identifier
            self.previewHeight = previewHeight
            self.preview = preview()
            self.content = content
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: HmmSpacing.m) {
                    preview
                        .frame(maxWidth: .infinity)
                        .frame(height: previewHeight)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: HmmRadius.card, style: .continuous))
                    Picker("Settings", selection: $page) {
                        ForEach(Array(Page.allCases)) { item in
                            Text(LocalizedStringKey(item.title)).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("\(identifier)-pages")
                    content(page)
                }
                .padding(HmmSpacing.l)
            }
            .navigationTitle(Text(verbatim: title))
            .accessibilityIdentifier(identifier)
        }
    }
#endif
