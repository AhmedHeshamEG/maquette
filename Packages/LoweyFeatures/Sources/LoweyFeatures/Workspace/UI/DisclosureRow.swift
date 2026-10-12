import HmmDesign
import SwiftUI

/// A row that opens one step deeper, in place (progressive disclosure). It remembers whether it was open.
struct DisclosureRow<Content: View>: View {
    let title: String
    let systemName: String
    let identifier: String
    @ViewBuilder let content: () -> Content
    @AppStorage private var open: Bool
    @Environment(\.hmmTheme) private var theme

    init(_ title: String, systemName: String, identifier: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemName = systemName
        self.identifier = identifier
        self.content = content
        _open = AppStorage(wrappedValue: false, "inspector.row.\(identifier)")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Button {
                HmmHaptics.play(.selection)
                withHmmAnimation(.snappy) { open.toggle() }
            } label: {
                HStack(spacing: HmmSpacing.s) {
                    Image(systemName: systemName).frame(width: 22).foregroundStyle(theme.text2)
                    Text(LocalizedStringKey(title)).font(.hmm(.body, weight: .semibold)).foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: HmmSpacing.xs)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(theme.text3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .frame(minHeight: 40)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(open ? .isSelected : [])
            .accessibilityIdentifier(identifier)
            if open {
                content().transition(.opacity)
            }
        }
    }
}
