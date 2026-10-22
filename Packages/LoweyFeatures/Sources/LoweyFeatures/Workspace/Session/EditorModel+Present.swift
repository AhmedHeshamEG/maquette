import Foundation
import HmmDesign
import LoweyCore

/// Present mode (U8): one tap hides every control and the stage fills the screen (a TV or a projector shows the iPad's
/// screen, by AirPlay or a cable). It plays the film from the start through its shots and again, walks through a
/// building at eye height, or shows the model to be turned by hand. A tap brings back the presenter's few controls for
/// a moment; the iPhone companion is its remote.
extension EditorModel {
    /// What Present plays first: the film when there is one (cameras, cuts or anything that moves), else the model.
    var presentChoice: PresentKind {
        !cameras.isEmpty || !timeline.cuts.isEmpty || timeline.contentEnd > 0 ? .film : .look
    }

    func startPresenting(_ kind: PresentKind? = nil) {
        let kind = kind ?? presentChoice
        if together.presenting != nil { endPresentedKind() }
        openPanel = nil
        setSelection([])
        chromeHidden = true
        together.notesShown = false
        together.presenting = PresentState(kind: kind)
        ScreenAwake.hold("present", true)
        switch kind {
        case .film:
            if let camera = PresentPlan(timeline).shots.first?.camera ?? cameras.first { lookThrough(camera) }
            setTime(0)
            play()
            watchPresentedFilm()
        case .walk:
            startWalking()
        case .look:
            if directorView { setDirectorView(false) }
            frameSelection()
        }
        showPresentControls()
        sendPresentStatus()
    }

    /// The project closes: presenting, the iPhone's link and a review end with it.
    func endTogether() {
        stopPresenting()
        stopCompanionLink()
        if together.reviewing { app.review.leave() }
    }

    func stopPresenting() {
        guard together.presenting != nil else { return }
        endPresentedKind()
        together.presenting = nil
        together.controlsTask?.cancel()
        chromeHidden = false
        ScreenAwake.hold("present", false)
        sendToPhone(.done)
    }

    private func endPresentedKind() {
        switch together.presenting?.kind {
        case .film: pause()
        case .walk: stopWalking()
        default: break
        }
    }

    /// The presenter's controls come back for three seconds (a tap on the stage, a remote's press).
    func showPresentControls() {
        guard together.presenting != nil else { return }
        together.presenting?.controls = true
        together.controlsTask?.cancel()
        together.controlsTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, !Task.isCancelled else { return }
            together.presenting?.controls = false
        }
    }

    /// The film plays round: at its end it starts again, unless it was paused.
    private func watchPresentedFilm() {
        Task { [weak self] in
            var shot = -1
            while let editor = self, editor.together.presenting?.kind == .film {
                try? await Task.sleep(for: .milliseconds(250))
                if !editor.isPlaying, !editor.together.presentPaused, editor.time >= editor.timeline.duration - 0.05 {
                    editor.setTime(0)
                    editor.play()
                }
                let now = PresentPlan(editor.timeline).index(at: editor.time)
                if now != shot {
                    shot = now
                    editor.sendPresentStatus()
                }
            }
        }
    }

    // MARK: The remote

    func presentRemote(_ command: RemoteCommand) {
        if together.presenting == nil, command != .endPresenting { startPresenting() }
        let plan = PresentPlan(timeline)
        switch command {
        case .playPause:
            if together.presenting?.kind != .film {
                startPresenting(.film)
            } else {
                togglePresentedPlay()
            }
        case .nextShot:
            if let next = plan.next(after: time) { setTime(next, snap: false) }
        case .previousShot:
            setTime(plan.previous(before: time), snap: false)
        case .fromTheStart:
            setTime(0)
            if together.presenting?.kind == .film, !isPlaying { togglePresentedPlay() }
        case let .walk(moveX, moveY, lookX, lookY):
            if together.presenting?.kind != .walk { startPresenting(.walk) }
            flyer.pad.strafe = moveX
            flyer.pad.forward = moveY
            flyer.pad.pan = lookX
            flyer.pad.tilt = lookY
            return
        case .endPresenting:
            stopPresenting()
            return
        }
        showPresentControls()
        sendPresentStatus()
    }

    func togglePresentedPlay() {
        if isPlaying {
            together.presentPaused = true
            pause()
        } else {
            together.presentPaused = false
            play()
        }
        sendPresentStatus()
    }

    var presentStatus: PresentStatus {
        let plan = PresentPlan(timeline)
        let index = plan.index(at: time)
        let camera = plan.shots.indices.contains(index) ? plan.shots[index].camera : nil
        return PresentStatus(playing: isPlaying, walking: together.presenting?.kind == .walk,
                             shot: camera.flatMap { baseScene.objects[$0]?.name }, shotIndex: index + 1, shotCount: plan.shots.count)
    }

    func sendPresentStatus() {
        guard together.presenting != nil else { return }
        sendToPhone(.presenting(presentStatus))
    }
}
