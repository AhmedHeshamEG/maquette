import Foundation
import GroupActivities
import HmmLink
import LoweyCore
import Observation
import QuartzCore
import UIKit

/// Reviewing one project together over FaceTime (SharePlay).
struct ReviewActivity: GroupActivity {
    static let activityIdentifier = "studio.h.maquette.review"

    var project: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = String(localized: "Review “\(project)”")
        metadata.subtitle = String(localized: "Turn the model together and leave notes on it")
        metadata.type = .generic
        return metadata
    }
}

/// A review over FaceTime (U8): the person who starts it sends the project (as a `.maquettepack`, through the
/// session); the others open it as a copy of their own. From then on everyone turns the same view, whoever moved it
/// last leading (`ViewLead`), and notes written, answered or resolved reach everyone. The model itself isn't shared
/// edit by edit: it's a review, not two people modelling at once.
@MainActor @Observable
final class ReviewRoom {
    private(set) var isOn = false
    private(set) var people = 0
    /// This iPad started it (it sends the project).
    private(set) var hosting = false
    /// Joined, waiting for the project to arrive.
    private(set) var waitingForProject = false
    /// On a FaceTime call that can share (what shows "Review over FaceTime").
    let call = HmmTogetherCall()

    @ObservationIgnored private let together = HmmTogether<ReviewActivity>()
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private weak var app: AppModel?
    /// The project to send once the session is joined.
    @ObservationIgnored private var outgoing: URL?

    init() {}

    /// Listens for sessions (started here or by someone else on the call), once, at launch.
    func listen(for app: AppModel) {
        guard Held.isOn(.faceTimeReview), listening == nil else { return }
        self.app = app
        together.onMessage = { [weak self] data in self?.received(data) }
        together.onFile = { [weak self] url in self?.projectArrived(url) }
        together.onPeople = { [weak self] count in self?.people = count }
        together.onEnd = { [weak self] in self?.ended() }
        listening = Task { [weak self] in
            for await session in ReviewActivity.sessions() {
                self?.join(session)
            }
        }
    }

    /// Review over FaceTime: the project goes to the people on the call.
    func start(project name: String, package url: URL) async {
        hosting = true
        outgoing = url
        do {
            if try await !HmmTogether<ReviewActivity>.start(ReviewActivity(project: name)) {
                hosting = false
                outgoing = nil
            }
        } catch {
            hosting = false
            outgoing = nil
            app?.show("Couldn't start the review: \(error.localizedDescription)", kind: .error)
        }
    }

    func leave() {
        together.leave()
    }

    private func join(_ session: GroupSession<ReviewActivity>) {
        together.join(session)
        isOn = true
        if hosting, let outgoing {
            together.share(outgoing)
            self.outgoing = nil
            app?.editor?.reviewStarted()
        } else {
            waitingForProject = true
            app?.show("Opening the project being reviewed…")
        }
        send(.hello(name: app?.editor?.yourName ?? UIDevice.current.name))
    }

    private func projectArrived(_ url: URL) {
        guard waitingForProject, let app else { return }
        waitingForProject = false
        Task {
            // The open project is saved and closed first (not `closeEditor`, which closes later, after its card).
            if let editor = app.editor {
                await editor.saveNow(thumbnail: false)
                editor.tearDown()
                app.editor = nil
            }
            guard let opened = app.openReviewCopy(url) else { return }
            app.open(url: opened)
            app.editor?.reviewStarted()
        }
    }

    func send(_ message: ReviewMessage) {
        guard isOn, let data = try? message.encoded() else { return }
        if case .view = message {
            together.send(data, reliable: false)
        } else {
            together.send(data)
        }
    }

    private func received(_ data: Data) {
        guard let message = ReviewMessage.decode(data), let editor = app?.editor else { return }
        switch message {
        case let .hello(name):
            app?.show("\(name) is reviewing with you")
        case let .view(viewpoint, from, sequence):
            editor.receiveView(viewpoint, from: from, sequence: sequence)
        case let .notes(edits):
            editor.receiveNotes(edits)
        case let .time(time, playing, _):
            editor.receiveTime(time, playing: playing)
        }
    }

    private func ended() {
        isOn = false
        hosting = false
        waitingForProject = false
        people = 0
        app?.editor?.reviewEnded()
    }
}

extension AppModel {
    /// The review's project, unpacked as a copy on this iPad (its name says so).
    func openReviewCopy(_ url: URL) -> URL? {
        do {
            let destination = try ProjectPackage.unpack(Data(contentsOf: url), into: projectStore)
            refreshProjects()
            return destination
        } catch {
            show("Couldn't open the project being reviewed: \(error.localizedDescription)", kind: .error)
            return nil
        }
    }

    /// Review over FaceTime with the open project.
    func startReview() {
        guard Held.isOn(.faceTimeReview), let editor, let project = projects.first(where: { $0.url == editor.projectURL }) else { return }
        Task {
            await editor.saveNow(thumbnail: false)
            guard let package = package(project) else { return }
            await review.start(project: project.info.name, package: package)
        }
    }
}

extension EditorModel {
    func reviewStarted() {
        together.reviewing = true
        setNotesShown(true)
    }

    func reviewEnded() {
        together.reviewing = false
        app.show("The review has ended. Its notes are in the project")
    }

    /// The view moved here: the others follow (a few times a second at most).
    func reviewViewMoved(_ viewpoint: Viewpoint) {
        guard together.reviewing else { return }
        let now = CACurrentMediaTime()
        together.lead.movedHere(at: now)
        guard now - together.lastViewSent > 1.0 / 15 else { return }
        together.lastViewSent = now
        together.viewSequence += 1
        app.review.send(.view(viewpoint, from: yourName, sequence: together.viewSequence))
    }

    func receiveView(_ viewpoint: Viewpoint, from sender: String, sequence: Int) {
        guard together.lead.accepts(from: sender, sequence: sequence, at: CACurrentMediaTime()) else { return }
        stage?.setViewpoint(viewpoint, notify: false)
        viewRevision &+= 1
    }

    func receiveTime(_ time: Double, playing: Bool) {
        if playing, !isPlaying { play() }
        if !playing, isPlaying { pause() }
        setTime(time, snap: false)
    }
}
