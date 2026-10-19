import Foundation
import HmmMedia
import HmmVector
@testable import LoweyCore
import XCTest

/// D1, continued: links, letters, morphs, loops, the commands and the bridge's `design`, and the phase's acceptance: a
/// logo extruded, cloned and rippling to a music track loops seamlessly.
final class MotionDesignMoreTests: XCTestCase {
    private typealias Base = MotionDesignTests

    /// A sound with a beat every half second and loudness rising across its length.
    static func music(seconds: Double = 4) -> AudioClip {
        let count = Int(seconds * SoundLevels.rate)
        let loudness = (0 ..< count).map { UInt8(min(255, $0 * 255 / max(count - 1, 1))) }
        let beats = stride(from: 0.0, to: seconds, by: 0.5).map(\.self)
        var clip = AudioClip(id: "music", role: .music, name: "Music", file: "music.m4a", duration: seconds)
        clip.levels = SoundLevels(loudness: loudness, bass: loudness, beats: beats, tempo: 120)
        return clip
    }

    // MARK: Links

    func testAGearTurnsItsNeighbourTheOtherWayAtHalfSpeedPastHalfATurn() throws {
        var document = Base.document([Base.cube("a"), Base.cube("b", at: Vec3(2, 0, 0))], duration: 10)
        document.scene.timeline.behaviors = [Behavior(id: "spin", target: "a", kind: .spin(degreesPerSecond: 90, axis: .y))]
        document.scene.timeline.links = [MotionLink(id: "l", target: "b", channel: .turnY, driver: .thing(id: "a", channel: .turnY), amount: -0.5)]
        for (time, expected) in [(1.0, -45.0), (3.0, -135.0), (5.0, -225.0)] {
            let b = try XCTUnwrap(Animator.evaluate(document, at: time).scene.objects["b"])
            // −225° is the same turn as 135°: compare the turns, not the numbers.
            let want = Quat(angle: expected * .pi / 180, axis: .unitY)
            XCTAssertGreaterThan(abs(b.transform.rotation.normalized.dot(want)), 1 - 1e-6, "\(time) s")
        }
    }

    func testALinkFollowsAMoveAndWaits() throws {
        var document = Base.document([Base.cube("a"), Base.cube("b", at: Vec3(3, 0, 0))])
        document.scene.timeline.tracks = [Track(id: "t", target: "a", property: .position,
                                                keyframes: [Keyframe(time: 0, value: .vec3(.zero), easing: .linear),
                                                            Keyframe(time: 2, value: .vec3(Vec3(0, 2, 0)), easing: .linear)])]
        document.scene.timeline.links = [MotionLink(id: "l", target: "b", channel: .size, driver: .thing(id: "a", channel: .moveY), amount: 0.5, delay: 1)]
        let b = try XCTUnwrap(Animator.evaluate(document, at: 2).scene.objects["b"])
        // a rose 1 m by 1 s (the link waits a second): b grows by half of that.
        XCTAssertEqual(b.transform.scale.y, 1.5, accuracy: 1e-9)
        XCTAssertEqual(b.transform.position.x, 3, accuracy: 1e-9)
    }

    func testASoundMovesAThingThroughItsFades() throws {
        var document = Base.document([Base.cube("c")])
        var clip = Self.music()
        clip.fadeOut = 1
        document.scene.timeline.audio = [clip]
        document.scene.timeline.links = [MotionLink(id: "l", target: "c", channel: .moveY, driver: .sound(clip: "music", feature: .loudness), amount: 2)]
        func height(_ time: Double) -> Double { Animator.evaluate(document, at: time).scene.objects["c"]?.transform.position.y ?? -1 }
        XCTAssertEqual(height(0), 0, accuracy: 1e-6)
        XCTAssertEqual(height(2), 2 * (2 * 60.0 / 239), accuracy: 0.02)
        XCTAssertLessThan(height(3.9), height(3), "fading out")
        XCTAssertEqual(MotionLinks.soundValue(clip, feature: .beat, at: 0.5), 1, accuracy: 1e-9)
        var muted = clip
        muted.muted = true
        XCTAssertEqual(MotionLinks.soundValue(muted, feature: .beat, at: 0.5), 0)
    }

    // MARK: Letters

    func testLettersFlyInOneAfterAnotherAndRest() {
        let letters = TextAnimator(preset: .flyIn, start: 1, stagger: 0.1, length: 0.5)
        XCTAssertEqual(TextAnimator.letterIndices("A B\nC"), [0, nil, 1, nil, 2])
        let before = letters.poses(count: 3, at: 1, size: 1)
        XCTAssertEqual(before[0].opacity, 0, accuracy: 1e-9)
        XCTAssertGreaterThan(before[0].offset.z, 2)
        let during = letters.poses(count: 3, at: 1.3, size: 1)
        XCTAssertGreaterThan(during[0].opacity, during[2].opacity, "the first is further along")
        XCTAssertTrue(letters.poses(count: 3, at: 1.71, size: 1).allSatisfy(\.isResting))
        XCTAssertEqual(letters.end(letters: 3) ?? 0, 1.7, accuracy: 1e-9)
        XCTAssertEqual(TextAnimator(preset: .flyIn, order: .backward).ranks(count: 3), [2, 1, 0])
        XCTAssertEqual(TextAnimator(preset: .flyIn, order: .middle).ranks(count: 5), [2, 1, 0, 1, 2])
        XCTAssertEqual(Set(TextAnimator(preset: .flyIn, order: .random).ranks(count: 6)), Set(0 ..< 6))
    }

    func testEveryPresetArrivesAtRest() {
        for preset in TextAnimator.Preset.allCases where !preset.repeats {
            let letters = TextAnimator.starting(preset, at: 0)
            let end = letters.end(letters: 4) ?? 0
            XCTAssertTrue(letters.poses(count: 4, at: end + 0.01, size: 1).allSatisfy(\.isResting), preset.rawValue)
            XCTAssertFalse(letters.poses(count: 4, at: 0.01, size: 1).allSatisfy(\.isResting), preset.rawValue)
        }
        let wave = TextAnimator.starting(.wave, at: 0)
        for (now, later) in zip(wave.poses(count: 3, at: 0.3, size: 1), wave.poses(count: 3, at: 0.3 + wave.length * 2, size: 1)) {
            XCTAssertEqual(now.offset.y, later.offset.y, accuracy: 1e-9)
        }
    }

    // MARK: Morph

    func testACubeBecomesABall() throws {
        let cube = PrimitiveMesh.make(.cube, shading: .flat)
        let ball = PrimitiveMesh.make(.sphere, shading: .smooth)
        let pair = MorphPair(source: cube, target: ball)
        XCTAssertGreaterThan(pair.source.positions.count, cube.positions.count, "cut finer so it can bend")
        let start = pair.mesh(at: 0)
        XCTAssertEqual(start.positions, pair.source.positions)
        let end = pair.mesh(at: 1)
        let centre = SIMD3<Float>(0, 0.5, 0)
        let radii = end.positions.map { length3($0 - centre) }
        XCTAssertEqual(Double(radii.min() ?? 0), 0.5, accuracy: 0.03)
        XCTAssertEqual(Double(radii.max() ?? 0), 0.5, accuracy: 0.03)
        let halfway = pair.mesh(at: 0.5).positions.map { length3($0 - centre) }
        XCTAssertGreaterThan(halfway.max() ?? 0, radii.max() ?? 0, "a cube's corners are further out than the ball")
    }

    func testAMorphIsOneStepAndHidesItsTarget() throws {
        let document = Base.document([Base.cube("c"), Base.cube("s", at: Vec3(2, 0, 0))])
        var ids = IDFactory.sequential("m")
        let design = MotionDesign(morph: ObjectMorph(target: "s"))
        let command = MorphOperations.command("c", into: "s", design: design, from: 1, duration: 2, in: document, ids: &ids)
        let morphed = try assertReverts(command, on: document)
        XCTAssertEqual(morphed.scene.objects["s"]?.isVisible, false)
        XCTAssertEqual(Animator.evaluate(morphed, at: 2).scene.objects["c"]?.morphAmount ?? 0, 0.5, accuracy: 1e-9)
        let removing = try XCTUnwrap(MorphOperations.removing("c", in: morphed))
        let back = try assertReverts(removing, on: morphed)
        XCTAssertEqual(back.scene.objects["s"]?.isVisible, true)
        XCTAssertNil(back.scene.objects["c"]?.motionDesign)
    }

    // MARK: Loops

    func testASpinThatDoesntFitIsCaughtAndClosed() throws {
        var document = Base.document([Base.cube("c"), Base.cube("k", at: Vec3(2, 0, 0))], duration: 10)
        document.scene.timeline.behaviors = [Behavior(id: "spin", target: "c", kind: .spin(degreesPerSecond: 90, axis: .y))]
        document.scene.timeline.tracks = [Track(id: "t", target: "k", property: .position,
                                                keyframes: [Keyframe(time: 0, value: .vec3(Vec3(2, 0, 0))),
                                                            Keyframe(time: 5, value: .vec3(Vec3(2, 1, 0)))])]
        let range = TimeRange(start: 0, end: 10)
        let seams = LoopCheck.seams(document, range: range)
        XCTAssertEqual(Set(seams.map(\.object)), ["c", "k"])
        XCTAssertEqual(seams.first { $0.object == "c" }?.what, .turns)
        let close = try XCTUnwrap(LoopClose.command(document, range: range))
        let closed = try assertReverts(close, on: document)
        XCTAssertEqual(LoopCheck.seams(closed, range: range), [])
        guard case let .spin(degreesPerSecond, _) = closed.scene.timeline.behaviors[0].kind else { return XCTFail("still a spin") }
        XCTAssertEqual(degreesPerSecond, 108, accuracy: 1e-9, "three turns in ten seconds, the nearest whole number")
        XCTAssertNil(LoopClose.command(closed, range: range), "nothing left to close")
    }

    func testAWiggleCantLoopAndSaysSo() {
        var document = Base.document([Base.cube("c")], duration: 3)
        document.scene.timeline.behaviors = [Behavior(id: "w", target: "c",
                                                      kind: .noise(position: Vec3(0.2, 0.2, 0.2), rotation: .zero, frequency: 1.3))]
        let range = TimeRange(start: 0, end: 3)
        XCTAssertEqual(LoopCheck.seams(document, range: range).map(\.object), ["c"])
        XCTAssertNil(LoopClose.command(document, range: range))
    }

    func testLettersFlyingInOnceDontLoopButAWaveDoes() throws {
        var text = SceneObject(id: "t", name: "Title", kind: .text(TextRecipe(text: "HI")))
        text.motionDesign = MotionDesign(letters: TextAnimator.starting(.flyIn, at: 0))
        let range = TimeRange(start: 0, end: 4)
        XCTAssertEqual(LoopCheck.seams(Base.document([text]), range: range).map(\.what), [.letters])
        text.motionDesign = MotionDesign(letters: TextAnimator(preset: .wave, start: 0, stagger: 0.1, length: 1.5))
        let wavy = Base.document([text])
        XCTAssertEqual(LoopCheck.seams(wavy, range: range).map(\.what), [.letters])
        let close = try XCTUnwrap(LoopClose.command(wavy, range: range))
        XCTAssertEqual(try LoopCheck.seams(assertReverts(close, on: wavy), range: range), [])
    }

    /// The phase's acceptance (PHASES D1): a logo extruded, cloned and rippling to a music track loops seamlessly once
    /// closed: the export renders the stretch's frames, and its end meets its start.
    func testALogoClonedAndRipplingToMusicLoopsSeamlessly() throws {
        let drawing = try SVG.read(Data(Base.badge.utf8))
        var ids = IDFactory.sequential("logo")
        let made = try XCTUnwrap(LogoImport.objects(drawing, name: "Brand", width: 1, depth: 0.1) { ids.next() })
        var document = Base.document(made.objects, duration: 4)
        var design = MotionDesign(clones: ObjectClones(layout: .grid(columns: 4, rows: 4, layers: 1, spacing: Vec3(1.3, 1, 1.3))))
        design.clones?.effects = [CloneEffect.starting(.push, id: "ripple", size: 1), CloneEffect(id: "d", kind: .delay, delay: 0.1)]
        document.scene.objects[made.root]?.motionDesign = design
        document.scene.objects[made.root]?[PropertyKey.effectStrength] = PropertyValue.float(0)
        var clip = Self.music(seconds: 8)
        clip.levels?.beats = stride(from: 0.0, to: 8, by: 0.5).map(\.self)
        clip.levels?.loudness = Array(repeating: 200, count: 480)
        document.scene.timeline.audio = [clip]
        document.scene.timeline.links = [MotionLink(id: "l", target: made.root, channel: .effect, driver: .sound(clip: "music", feature: .beat), amount: 1)]
        document.scene.timeline.behaviors = [Behavior(id: "spin", target: made.root, kind: .spin(degreesPerSecond: 70, axis: .y))]
        let range = TimeRange(start: 0, end: 4)
        XCTAssertFalse(LoopCheck.seams(document, range: range).isEmpty, "the spin and the ripple don't fit four seconds yet")
        let closed = try assertReverts(XCTUnwrap(LoopClose.command(document, range: range)), on: document)
        XCTAssertEqual(LoopCheck.seams(closed, range: range), [])
        // It moves: copies ride the ripple on the beat.
        let shown = Animator.evaluate(closed, at: 1.1).scene
        let heights = (1 ..< 16).compactMap { shown.objects[ClonePlayback.copyID(made.root, $0)]?.transform.position.y }
        XCTAssertGreaterThan(heights.max() ?? 0, 0.05)
    }

    // MARK: Commands and the file

    func testTheCommandsUndoAndTravelAsJSON() throws {
        let document = Base.document([Base.cube("c"), Base.cube("d")])
        let design = MotionDesign(clones: ObjectClones(layout: .path(count: 5, path: "d", along: true),
                                                       effects: [CloneEffect.starting(.push, id: "e", size: 1)]),
                                  letters: TextAnimator.starting(.wave, at: 1))
        _ = try assertReverts(.setMotionDesign("c", design), on: document)
        let link = MotionLink(id: "l", target: "c", channel: .glow, driver: .sound(clip: "music", feature: .bass), amount: 3)
        _ = try assertReverts(.setLinks([link]), on: document)
        var saved = document
        saved.scene.objects["c"]?.motionDesign = design
        saved.scene.timeline.links = [link]
        saved.scene.timeline.audio = [Self.music()]
        let data = try SchemaCoder.shared.encode(saved.scene, kind: .scene)
        XCTAssertEqual(try SchemaCoder.shared.decode(Scene.self, kind: .scene, from: data), saved.scene)
    }
}
