import Foundation
@testable import HmmDiagnostics
import XCTest

final class FeelLogTests: XCTestCase {
    private let period = 1.0 / 120.0

    private func makeLog() -> FeelLog {
        var log = FeelLog(start: 100, recording: FeelRecording(app: "Test", appVersion: "0.1", device: "iPad", system: "26"))
        log.refresh(at: 100, period: period, screen: "Home")
        return log
    }

    private func delivery(_ phase: String = "ended", touched: Double, delivered: Double, surface: Int? = nil) -> FeelLog.Delivery {
        .init(phase: phase, kind: "finger", count: 1, x: 10, y: 20, target: "UIView", screen: "Home",
              touched: touched, delivered: delivered, surface: surface)
    }

    func testATapAnsweredBeforeTheNextRefreshMissesNothing() throws {
        var log = makeLog()
        log.deliver(delivery(touched: 100.001, delivered: 100.002))
        log.mainIdle(at: 100.005, busySince: 100.002, screen: "Home")
        log.settle(at: 100.006)
        let touch = try XCTUnwrap(log.recording.touches.first)
        XCTAssertEqual(touch.missed, 0)
        XCTAssertEqual(touch.input, 1, accuracy: 1e-6)
        XCTAssertEqual(touch.main, 3, accuracy: 1e-6)
        XCTAssertEqual(touch.total, (period - 0.001) * 1000, accuracy: 1e-6)
        XCTAssertEqual(touch.t, 0.001, accuracy: 1e-9)
        XCTAssertNil(touch.gpu)
    }

    func testASlowPanelMissesRefreshesAndStalls() throws {
        var log = makeLog()
        log.deliver(delivery(touched: 100.001, delivered: 100.002))
        log.mainIdle(at: 100.030, busySince: 100.002, screen: "Editor")
        log.settle(at: 100.031)
        let touch = try XCTUnwrap(log.recording.touches.first)
        // The first refresh after the touch is at 8.3 ms; the work ended at 30 ms: three refreshes went by.
        XCTAssertEqual(touch.missed, 3)
        XCTAssertEqual(touch.total, (4 * period - 0.001) * 1000, accuracy: 1e-6)
        XCTAssertEqual(log.recording.stalls.count, 1)
        XCTAssertEqual(log.recording.stalls[0].busy, 28, accuracy: 1e-6)
        XCTAssertEqual(log.recording.stalls[0].screen, "Editor")
    }

    func testASurfaceTouchWaitsForItsFrame() throws {
        var log = makeLog()
        log.deliver(delivery("moved", touched: 100.001, delivered: 100.002, surface: 7))
        log.mainIdle(at: 100.004, busySince: 100.002, screen: "Editor")
        log.settle(at: 100.005)
        XCTAssertEqual(log.pendingCount, 1, "a touch on the stage waits for the stage's frame")
        // Another surface's frame doesn't answer it.
        log.surfaceFrame(.init(surface: 9, started: 100.003, encoded: 100.004, gpuStart: 100.004, gpuEnd: 100.006))
        log.surfaceFrame(.init(surface: 7, started: 100.003, encoded: 100.005, gpuStart: 100.005, gpuEnd: 100.012))
        log.settle(at: 100.013)
        let touch = try XCTUnwrap(log.recording.touches.first)
        XCTAssertEqual(try XCTUnwrap(touch.encode), 2, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(touch.gpu), 7, accuracy: 1e-6)
        XCTAssertEqual(touch.main, 1, accuracy: 1e-6)
        XCTAssertEqual(touch.missed, 1)
        XCTAssertEqual(log.recording.frames.count, 2)
    }

    func testASurfaceThatNeverRedrawsIsAnsweredByTheInterface() throws {
        var log = makeLog()
        log.deliver(delivery("began", touched: 100.001, delivered: 100.002, surface: 7))
        log.mainIdle(at: 100.003, busySince: nil, screen: "Editor")
        log.settle(at: 100.1)
        XCTAssertEqual(log.pendingCount, 1)
        log.settle(at: 100.3)
        XCTAssertEqual(log.pendingCount, 0)
        XCTAssertNil(try XCTUnwrap(log.recording.touches.first).gpu)
    }

    func testHitchesMarksAndTheFile() throws {
        var log = makeLog()
        log.refresh(at: 100 + period, period: period, screen: "Home")
        log.refresh(at: 100 + 5 * period, period: period, screen: "Home")
        XCTAssertEqual(log.recording.hitches.count, 1)
        XCTAssertEqual(log.recording.hitches[0].gap, 4 * period * 1000, accuracy: 1e-6)
        XCTAssertEqual(log.recording.refreshRate, 120)
        log.describeWindow(width: 1180, height: 820)
        log.mark("Open project", from: 100.5, to: 100.8, screen: "Editor")
        log.deliver(delivery(touched: 101, delivered: 101.001))
        let recording = log.finish(at: 102)
        XCTAssertEqual(recording.seconds, 2, accuracy: 1e-9)
        XCTAssertEqual(recording.touches.count, 1, "the end writes what was still waiting")
        XCTAssertEqual(recording.marks[0].duration, 300, accuracy: 1e-6)
        XCTAssertEqual(recording.width, 1180)
        let decoded = try FeelRecording.decode(recording.json())
        XCTAssertEqual(decoded.touches, recording.touches)
        XCTAssertTrue(recording.fileName.hasPrefix("feel-iPad-0.1-"))
        XCTAssertEqual(recording.fileName.suffix(5), ".json")
    }

    func testNextRefreshWithoutALinkIsNow() {
        let log = FeelLog(start: 0, recording: FeelRecording(app: "A", appVersion: "1", device: "d", system: "s"))
        XCTAssertEqual(log.nextRefresh(after: 3), 3)
    }
}
