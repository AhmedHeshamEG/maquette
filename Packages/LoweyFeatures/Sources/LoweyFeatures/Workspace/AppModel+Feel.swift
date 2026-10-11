import Foundation
import HmmDiagnostics
import LoweyEngine
import UIKit

/// The feel recorder (Diagnostics ▸ Record): a minute of real use, every touch followed to the frame that answers it
/// (hmm-kit's `FeelProbe`). The file lands beside the benchmark reports, goes into the log export, and
/// `Tools/feel_report.py` turns it into a ranked list of the slowest moments.
extension AppModel {
    /// A minute; UI tests shorten it with `-feel-seconds`.
    static var feelSeconds: Double {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-feel-seconds"), index + 1 < arguments.count, let seconds = Double(arguments[index + 1]) else { return 60 }
        return seconds
    }

    func startFeelRecording() {
        guard !FeelProbe.isRecording else { return }
        let recording = FeelRecording(app: AppIdentity.displayName, appVersion: AppIdentity.shortVersion, device: DiagnosticsCenter.deviceModel,
                                      system: "\(ProcessInfo.processInfo.operatingSystemVersionString) · preview tier \(PreviewQuality.current.tier.rawValue)")
        diagnostics.log("Feel recording started (\(Int(Self.feelSeconds)) s)")
        isRecordingFeel = true
        FeelProbe.start(seconds: Self.feelSeconds, recording: recording, screen: { [weak self] in self?.feelScreen ?? "" }) { [weak self] result in
            self?.feelRecordingFinished(result)
        }
    }

    func stopFeelRecording() {
        FeelProbe.stop()
    }

    private func feelRecordingFinished(_ recording: FeelRecording) {
        isRecordingFeel = false
        let url = diagnostics.benchmarksFolder.appendingPathComponent(recording.fileName)
        do {
            try FileManager.default.createDirectory(at: diagnostics.benchmarksFolder, withIntermediateDirectories: true)
            try recording.json().write(to: url, options: .atomic)
            diagnostics.log("Feel recording saved: \(recording.touches.count) touches, \(recording.hitches.count) hitches, \(url.lastPathComponent)")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            show("Recording saved. Share it from Settings ▸ Diagnostics.")
        } catch {
            show("Couldn't save the recording: \(error.localizedDescription)", kind: .error)
        }
    }

    /// What is on screen, in a few words, for each touch the recorder sees.
    var feelScreen: String {
        guard let editor else { return showsSettings ? "Home · Settings" : "Home" }
        return editor.feelScreen
    }

    /// The first screen is up: the cold launch is measured from the process's start and written to the log.
    func noteLaunched() {
        guard FeelProbe.launchSeconds == nil else { return }
        FeelProbe.noteLaunched()
        if let seconds = FeelProbe.launchSeconds { diagnostics.log("Cold launch to Home: \(Int(seconds * 1000)) ms") }
    }
}

extension EditorModel {
    /// The editor's state in a few words: the tool, what's open, the timeline, the selection, playback.
    var feelScreen: String {
        var parts = ["Editor", tool.rawValue]
        if let openPanel { parts.append("panel \(openPanel.rawValue)") }
        if let sheet { parts.append("sheet \(sheet.rawValue)") }
        if boardShown { parts.append("board") }
        if timelinePresence != .hidden { parts.append("timeline \(timelinePresence)") }
        if !selection.isEmpty { parts.append("\(selection.count) selected") }
        if isPlaying { parts.append("playing") }
        if directorView { parts.append("director") }
        return parts.joined(separator: " · ")
    }

    /// The stage drew its first frame since the project was asked to open: logged, and marked for the recorder.
    func noteFirstFrame() {
        guard let openStarted else { return }
        self.openStarted = nil
        let now = CACurrentMediaTime()
        app.diagnostics.log("Opened to the first frame: \(Int((now - openStarted) * 1000)) ms")
        FeelProbe.mark("Open project", from: openStarted, to: now)
    }
}
