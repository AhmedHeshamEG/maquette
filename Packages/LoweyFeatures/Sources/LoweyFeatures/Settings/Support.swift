import HmmDesign
import LoweyCore
import StoreKit
import SwiftUI

/// Supporting Maquette (O1, CONTEXT §D.32): a Support row and the credits in Settings ▸ About, and one thank-you card
/// in the Export sheet after the first export. Nothing on the canvas, no network, no tracking. The App Store build
/// links out to Ko-fi only on the US storefront (App Review 3.1.1(a) and 3.1.3); everywhere else it shows no link.
@MainActor
enum Support {
    static let koFi = URL(string: "https://ko-fi.com/heshamvox")!

    /// The App Store build (`MaquetteStoreBuild` in the Info.plist). The sideloaded and Debug builds aren't.
    static var isStoreBuild: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "MaquetteStoreBuild") as? String)?.uppercased() == "YES"
    }

    /// Whether this build may show a link to Ko-fi.
    static func linksOut() async -> Bool {
        guard isStoreBuild else { return true }
        return await Storefront.current?.countryCode == "USA"
    }

    /// The list shipped inside this build (`SUPPORTERS.md`, a resource of the app).
    static var supporters: SupportersList {
        guard let url = Bundle.main.url(forResource: "SUPPORTERS", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return SupportersList() }
        return SupportersList(markdown: text)
    }

    /// The card's one turn. UI tests see it only when they ask (`-ui-testing-thanks`, which starts it fresh), so the
    /// other tests' exports stay as they were.
    static let thankYouGate: ThankYouCardGate = {
        let defaults = UserDefaults.standard
        let testsTheCard = ProcessInfo.processInfo.arguments.contains("-ui-testing-thanks")
        if testsTheCard { defaults.removeObject(forKey: AppSettings.thankYouCardShown) }
        let skipped = AppIdentity.isUITesting && !testsTheCard
        return ThankYouCardGate(isShown: { skipped || defaults.bool(forKey: AppSettings.thankYouCardShown) },
                                markShown: { defaults.set(true, forKey: AppSettings.thankYouCardShown) })
    }()
}

/// Settings ▸ About ▸ Support Maquette, and the credits under it.
struct SupportRows: View {
    @State private var linksOut = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if linksOut {
                Button { openURL(Support.koFi) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support Maquette")
                        Text("It's free. If it helped you, you can help it.").font(.hmm(.footnote))
                    }
                }
                .accessibilityIdentifier("support-maquette")
            } else {
                NavigationLink { CreditsView() } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Support Maquette")
                        Text("Maquette is free and open source. Thank you for using it.").font(.hmm(.footnote))
                    }
                }
                .accessibilityIdentifier("support-maquette")
            }
            NavigationLink("Credits") { CreditsView() }
                .accessibilityIdentifier("credits")
        }
        .task { linksOut = await Support.linksOut() }
    }
}

/// The people who keep Maquette free, from the list shipped in this build.
struct CreditsView: View {
    private let list = Support.supporters
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                Text("Made possible by").font(.hmm(.title2, weight: .semibold))
                if list.isEmpty {
                    Text("Nobody yet. The first name here gets a lot of attention.")
                        .font(.hmm(.body)).foregroundStyle(theme.text2)
                }
                if !list.founding.isEmpty {
                    Text("Founding Supporters").font(.hmm(.headline, weight: .semibold))
                    ForEach(list.founding, id: \.number) { person in
                        Text("#\(person.number)  \(person.name)").font(.hmm(.body))
                    }
                }
                if !list.coffee.isEmpty {
                    Text("Everyone who bought a coffee").font(.hmm(.headline, weight: .semibold))
                    Text(list.coffee.joined(separator: " · ")).font(.hmm(.body))
                }
                Text("Made by H (Hesham). Code licensed under the GPL 3.0.")
                    .font(.hmm(.footnote)).foregroundStyle(theme.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(HmmSpacing.l)
        }
        .navigationTitle("Credits")
        .accessibilityIdentifier("credits-list")
    }
}

/// After the first export ever, inside the Export sheet's results: closed with one tap, never shown again.
struct ThankYouCard: View {
    @Bindable var editor: EditorModel
    @State private var linksOut = false
    @Environment(\.openURL) private var openURL
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.xs) {
            Text("You made a thing. In 3D.").font(.hmm(.headline, weight: .semibold))
            Text(linksOut ? "Maquette is free, and it'll stay free. If you want to help it grow, there's a coffee button."
                : "Maquette is free, and it'll stay free. Go show someone what you made.")
                .font(.hmm(.footnote)).foregroundStyle(theme.text2)
            HStack(spacing: HmmSpacing.xs) {
                if linksOut {
                    HmmPillButton("Maybe later") { editor.app.showsThankYou = false }
                        .accessibilityIdentifier("thanks-close")
                    HmmPillButton("Support", systemName: "cup.and.saucer", prominent: true) {
                        editor.app.showsThankYou = false
                        openURL(Support.koFi)
                    }
                    .accessibilityIdentifier("thanks-support")
                } else {
                    HmmPillButton("Done", prominent: true) { editor.app.showsThankYou = false }
                        .accessibilityIdentifier("thanks-close")
                }
            }
        }
        .padding(HmmSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HmmRadius.card).fill(theme.surface2))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("thank-you-card")
        .task { linksOut = await Support.linksOut() }
    }
}
