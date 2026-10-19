import Foundation
import HmmDesign
import HmmMedia
import LoweyCore

/// Links (D1): a thing's motion driving another's (tap the driver), a sound driving a thing (its loudness, bass or beat,
/// measured in the background the first time), and the loop check that closes a loop for export.
extension EditorModel {
    // MARK: Things driving things

    /// Make it move ▸ Link: the next tap names the thing whose motion moves the selection.
    func beginLink(_ preset: LinkPreset) {
        guard let id = singleSelection?.id else { return }
        design.wait = .link(id, preset)
        app.show(String.LocalizationValue(DesignWait.link(id, preset).hint))
    }

    func link(_ target: ObjectID, to driver: ObjectID, _ preset: LinkPreset) {
        guard driver != target, let name = baseScene.objects[driver]?.name else {
            return app.show("It can't drive itself. Tap another thing", kind: .error)
        }
        let mapping = preset.mapping
        let link = MotionLink(id: ObjectID.make().raw, target: target, channel: mapping.channel, driver: .thing(id: driver, channel: mapping.from),
                              amount: mapping.amount)
        perform(.setLinks(timeline.links + [link]))
        HmmHaptics.play(.commit)
        app.show("Linked to \(name). Play to see them move together")
    }

    /// The links that move a thing.
    func links(of id: ObjectID) -> [MotionLink] { timeline.links.filter { $0.target == id } }

    func updateLink(_ id: String, coalesce: String? = nil, _ change: (inout MotionLink) -> Void) {
        var links = timeline.links
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        change(&links[index])
        guard links != timeline.links else { return }
        perform(.setLinks(links), coalesceKey: coalesce)
    }

    func removeLink(_ id: String) {
        perform(.setLinks(timeline.links.filter { $0.id != id }))
    }

    /// What drives a link, in words.
    func driverName(_ link: MotionLink) -> String {
        switch link.driver {
        case let .thing(id, channel):
            "\(baseScene.objects[id]?.name ?? "?") · \(channel.title)"
        case let .sound(clip, feature):
            "\(timeline.audio.first { $0.id == clip }?.name ?? "?") · \(feature.title)"
        }
    }

    // MARK: Sounds driving things

    /// Make it move ▸ To the music: the selection follows a clip's loudness, bass or beat. A clip not yet measured is
    /// measured first (in the background); the link arrives with the measure, as one step.
    func linkToSound(_ clipID: String, feature: MotionLink.SoundFeature, channel: MotionLink.Channel) {
        guard let id = singleSelection?.id, let clip = timeline.audio.first(where: { $0.id == clipID }) else { return }
        let link = MotionLink(
            id: ObjectID.make().raw,
            target: id,
            channel: channel,
            driver: .sound(clip: clipID, feature: feature),
            amount: channel.soundAmount
        )
        guard clip.levels == nil else { return addSoundLink(link, levels: nil) }
        guard !design.measuring.contains(clipID) else { return }
        design.measuring.insert(clipID)
        let url = projectURL.appendingPathComponent(ProjectLayout.audioFolder).appendingPathComponent(clip.file)
        app.show("Listening to \(clip.name)…")
        Task { [weak self] in
            let levels = await Task.detached(priority: .userInitiated) { try? SoundReader.levels(of: url) }.value
            guard let self else { return }
            design.measuring.remove(clipID)
            guard let levels else { return app.show("Couldn't read \(clip.name)", kind: .error) }
            addSoundLink(link, levels: (clipID, levels))
        }
    }

    private func addSoundLink(_ link: MotionLink, levels: (String, SoundLevels)?) {
        var edited = timeline
        if let levels, let index = edited.audio.firstIndex(where: { $0.id == levels.0 }) {
            edited.audio[index].levels = levels.1
        }
        edited.links.append(link)
        var commands: [EditCommand] = [.setTimeline(edited)]
        // A ripple on the beat starts from nothing and rises with the sound.
        if link.channel == .effect {
            commands.append(.setProperties([PropertyChange(object: link.target, key: .effectStrength, value: .float(0))]))
        }
        perform(.batch("Link to the sound", commands))
        HmmHaptics.play(.commit)
        if let tempo = levels?.1.tempo { app.show("\(Int(tempo.rounded())) beats a minute. Play to see it move to the sound") }
    }

    /// Whether a clip is being measured now.
    func isMeasuring(_ clipID: String) -> Bool { design.measuring.contains(clipID) }

    // MARK: Loops

    /// The stretch an export loops over: the loop region, else the whole timeline.
    var loopRange: TimeRange { timeline.loop ?? TimeRange(start: 0, end: timeline.duration) }

    /// What doesn't meet between the loop's end and its start (empty: it loops seamlessly).
    var loopSeams: [LoopCheck.Seam] { LoopCheck.seams(document, range: loopRange, rigs: rigs()) }

    /// Closes the loop: keys back where they began, repeats retimed to fit (one step).
    func closeTheLoop() {
        guard let command = LoopClose.command(document, range: loopRange) else {
            return app.show("Nothing here can be made to repeat: a wiggle or a one-off move never meets itself")
        }
        perform(command)
        HmmHaptics.play(.commit)
        let left = loopSeams
        app.show(left.isEmpty ? "It loops seamlessly now" : "Closer. Still jumps: \(left.map(\.name).joined(separator: ", "))")
    }
}
