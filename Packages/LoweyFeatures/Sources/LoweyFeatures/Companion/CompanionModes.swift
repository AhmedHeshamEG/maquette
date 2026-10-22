import ARKit
import HmmDesign
import LoweyCore
import QuickLook
import SwiftUI
import UIKit

/// The iPhone as the presenter's remote (U8): the shot playing, back and forward a shot, play, and two sticks for
/// walking through.
struct RemoteMode: View {
    let link: CompanionLink
    @State private var walk = SIMD2<Double>.zero
    @State private var look = SIMD2<Double>.zero
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        VStack(spacing: HmmSpacing.l) {
            if let status = link.presenting {
                VStack(spacing: 2) {
                    Text(verbatim: status.shot ?? String(localized: "The free view")).font(.hmm(.title3, weight: .semibold))
                    Text("Shot \(status.shotIndex) of \(status.shotCount)").font(.hmmNumbers(.footnote)).foregroundStyle(theme.text2)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Not presenting yet: press play").font(.hmm(.body)).foregroundStyle(theme.text2)
            }
            HStack(spacing: HmmSpacing.l) {
                big("backward.end.fill", "Previous shot") { link.send(.remote(.previousShot)) }
                big(link.presenting?.playing == true ? "pause.fill" : "play.fill", "Play or pause") { link.send(.remote(.playPause)) }
                big("forward.end.fill", "Next shot") { link.send(.remote(.nextShot)) }
            }
            HStack {
                RemoteStick(label: "Walk") { vector in
                    walk = vector
                    sendSticks()
                }
                Spacer()
                RemoteStick(label: "Look") { vector in
                    look = vector
                    sendSticks()
                }
            }
            HStack {
                Button("From the start") { link.send(.remote(.fromTheStart)) }
                Spacer()
                Button("End presenting", role: .destructive) { link.send(.remote(.endPresenting)) }
            }
            .font(.hmm(.body))
        }
        .padding(HmmSpacing.l)
        .accessibilityIdentifier("companion-remote")
    }

    /// Both sticks at once (y up is forward and looking up).
    private func sendSticks() {
        link.send(.remote(.walk(moveX: walk.x, moveY: -walk.y, lookX: look.x, lookY: -look.y)))
    }

    private func big(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            HmmHaptics.play(.commit)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 76, height: 76)
                .background(Circle().fill(theme.surface2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

/// A stick on the remote: sends where it's pushed (−1…1, y down) a few times a second while held, and zero on release.
private struct RemoteStick: View {
    let label: String
    let changed: (SIMD2<Double>) -> Void
    @State private var offset = CGSize.zero
    @State private var lastSent: CFTimeInterval = 0
    @Environment(\.hmmTheme) private var theme
    private static let radius: CGFloat = 60

    var body: some View {
        ZStack {
            Circle().fill(theme.surface2)
            Circle().fill(theme.text.opacity(0.85)).frame(width: 44, height: 44).offset(offset)
            Text(LocalizedStringKey(label)).font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2).offset(y: Self.radius + 12)
        }
        .frame(width: Self.radius * 2, height: Self.radius * 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let length = max(1, hypot(value.translation.width, value.translation.height))
                    let scale = min(1, Self.radius / length)
                    offset = CGSize(width: value.translation.width * scale, height: value.translation.height * scale)
                    let now = CACurrentMediaTime()
                    guard now - lastSent > 1.0 / 20 else { return }
                    lastSent = now
                    changed(SIMD2(Double(offset.width / Self.radius), Double(offset.height / Self.radius)))
                }
                .onEnded { _ in
                    offset = .zero
                    changed(.zero)
                }
        )
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

/// The scene in AR on the iPhone: Apple's AR Quick Look with the model the iPad sent (life size, or on the table).
struct AugmentedMode: View {
    let link: CompanionLink
    @Environment(\.hmmTheme) private var theme

    var body: some View {
        if let model = link.model {
            ARPreview(url: model).ignoresSafeArea()
        } else {
            VStack(spacing: HmmSpacing.m) {
                ProgressView()
                Text("Waiting for the scene from the iPad…").font(.hmm(.body)).foregroundStyle(theme.text2)
            }
        }
    }
}

/// AR Quick Look in SwiftUI.
private struct ARPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.url = url
            controller.reloadData()
        }
    }

    func makeCoordinator() -> Source { Source(url: url) }

    final class Source: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in _: QLPreviewController) -> Int { 1 }

        func previewController(_: QLPreviewController, previewItemAt _: Int) -> any QLPreviewItem {
            let item = ARQuickLookPreviewItem(fileAt: url)
            item.allowsContentScaling = true
            return item
        }
    }
}
