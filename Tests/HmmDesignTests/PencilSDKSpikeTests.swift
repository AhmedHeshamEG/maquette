#if canImport(UIKit) && os(iOS)
    import SwiftUI
    import UIKit
    import XCTest

    /// U3's spike: the pinned SDK has what the squeeze menu, the Pencil's haptics and the finger magnifier stand on.
    /// Squeeze and haptics need a Pencil Pro to happen, so the simulator can only prove they build and wire up.
    @MainActor
    final class PencilSDKSpikeTests: XCTestCase {
        private final class Listener: NSObject, UIPencilInteractionDelegate {
            var squeezes: [UIPencilInteraction.Squeeze] = []

            func pencilInteraction(_: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
                squeezes.append(squeeze)
            }
        }

        func testSqueezeAndDoubleTapReachAnInteraction() {
            let listener = Listener()
            let interaction = UIPencilInteraction(delegate: listener)
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            view.addInteraction(interaction)
            XCTAssertTrue(view.interactions.contains { $0 === interaction })
            // The iPad's own Pencil settings (what double-tap and squeeze do) can be read.
            _ = UIPencilInteraction.preferredTapAction
            _ = UIPencilInteraction.preferredSqueezeAction
            XCTAssertTrue(listener.squeezes.isEmpty)
        }

        func testThePencilsHapticsCanBePlayedAtAPoint() {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
            let feedback = UICanvasFeedbackGenerator(view: view)
            feedback.alignmentOccurred(at: CGPoint(x: 10, y: 10))
            feedback.pathCompleted(at: CGPoint(x: 20, y: 20))
        }

        func testTheSystemLoupeOpensOverAnyView() throws {
            // Off screen it may not open (there is nothing to magnify); what matters here is that the API is there.
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
            let session = UITextLoupeSession.begin(at: CGPoint(x: 100, y: 100), fromSelectionWidgetView: nil, in: view)
            session?.move(to: CGPoint(x: 120, y: 110), withCaretRect: .zero, trackingCaret: false)
            session?.invalidate()
        }

        func testSwiftUIHearsTheSqueezeWithItsHoverPose() {
            let view = Color.clear
                .onPencilSqueeze { phase in
                    if case let .ended(value) = phase {
                        _ = value.hoverPose?.anchor
                        _ = value.hoverPose?.location
                    }
                }
                .onPencilDoubleTap { value in _ = value.hoverPose?.anchor }
            let host = UIHostingController(rootView: view)
            XCTAssertNotNil(host.view)
        }
    }
#endif
