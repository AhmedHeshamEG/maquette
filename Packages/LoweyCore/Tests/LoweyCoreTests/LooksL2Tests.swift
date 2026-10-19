import Foundation
@testable import LoweyCore
import XCTest

/// L2's Looks, Finish, drawn effects and grounds (Maquette 0.24).
final class LooksL2Tests: XCTestCase {
    func testTheNewLooksCarryWhatMakesThem() {
        XCTAssertGreaterThan(LookPreset.painterly.paint?.strokes ?? 0, 0.5, "Painterly is brush strokes")
        XCTAssertGreaterThan(LookPreset.watercolour.paint?.wetEdges ?? 0, 0.5, "washes pool at their edges")
        XCTAssertGreaterThan(LookPreset.watercolour.paint?.paper ?? 0, 0, "the paper shows through")
        XCTAssertEqual(LookPreset.gouache.paint?.paper ?? 1, 0, "gouache is opaque")
        XCTAssertEqual(LookPreset.paperman.finish.saturation, -1, "Paperman is black and white")
        XCTAssertTrue(LookPreset.paperman.finish.accentKeepsColor)
        XCTAssertEqual(LookPreset.paperman.shading.model, .clay)
        XCTAssertNotNil(LookPreset.animeCel.shading.shadowTint)
        XCTAssertLessThan(LookPreset.animeCel.shading.edgeSoftness, 0.01, "cel shadows are hard")
        XCTAssertEqual(LookPreset.animeCel.stepping, .onTwos)
        XCTAssertGreaterThan(LookPreset.cleanProduct.shading.reflection ?? 0, 0)
        XCTAssertFalse(LookPreset.cleanProduct.lines.enabled)
        XCTAssertEqual(LookPreset.pixel.pixel?.colors, 8)
        XCTAssertEqual(LookPreset.builtIns.filter { $0.shading.shadowTint != nil }.map(\.id), ["animeCel"], "only Anime cel tints its shadows")
        XCTAssertEqual(LookPreset.builtIns.filter { $0.paint != nil }.map(\.id), ["painterly", "watercolour", "gouache"])
    }

    func testOlderLooksReadWithoutTheNewFields() throws {
        let data = try LoweyJSON.encode(LookPreset.ink)
        let text = String(decoding: data, as: UTF8.self)
        for key in ["paint", "pixel", "shadowTint", "reflection"] {
            XCTAssertFalse(text.contains("\"\(key)\""), "\(key) is written only when used")
        }
        XCTAssertEqual(try LoweyJSON.decode(LookPreset.self, from: data), .ink)
        let painted = try LoweyJSON.decode(LookPreset.self, from: LoweyJSON.encode(LookPreset.watercolour))
        XCTAssertEqual(painted, .watercolour)
    }

    func testPixelBlocksFollowThePictureHeight() {
        let style = PixelStyle(size: 4, colors: 8)
        XCTAssertEqual(style.blockPixels(height: 1080), 4)
        XCTAssertEqual(style.blockPixels(height: 2160), 8, "a 4K export looks like the preview")
        XCTAssertEqual(style.blockPixels(height: 100), 1)
        XCTAssertEqual(PixelStyle(size: 500, colors: 8).blockPixels(height: 1080), 64)
    }

    func testTheFinishReadsOldFilesAndWritesOnlyWhatsUsed() throws {
        let old = Data(#"{"bloom":0.2,"vignette":0,"grain":0,"exposure":0,"contrast":0,"saturation":0,"temperature":0,"outline":0,"#.utf8)
            + Data(##""outlineColor":"#1A1A1A","chromaticAberration":0,"retro":0,"depthOfField":true,"##.utf8)
            + Data(#""texture":"paper","textureStrength":0.5}"#.utf8)
        let read = try JSONDecoder().decode(PostSettings.self, from: old)
        XCTAssertEqual(read.bloom, 0.2)
        XCTAssertEqual(read.texture, .paper)
        XCTAssertFalse(read.misregistration)
        XCTAssertEqual(read.benDay, 0)
        let future = Data(#"{"texture":"hologram"}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(PostSettings.self, from: future).texture, PostSettings.Texture.none)
        var finish = PostSettings(texture: .riso, misregistration: true, boil: 0.4, benDay: 0.6)
        XCTAssertFalse(finish.isNeutral)
        XCTAssertEqual(try JSONDecoder().decode(PostSettings.self, from: JSONEncoder().encode(finish)), finish)
        finish = PostSettings()
        XCTAssertTrue(finish.isNeutral)
        let plain = String(decoding: try JSONEncoder().encode(finish), as: UTF8.self)
        XCTAssertFalse(plain.contains("benDay"))
        XCTAssertEqual(PostSettings.Texture.allCases.map(\.shaderIndex), Array(0 ..< 7), "the shader's numbers follow the list")
    }

    func testDrawnEffectsAimAndFollow() {
        let lines = ScreenEffect(id: "f", kind: .focusLines, start: 1, center: Vec2(0.3, 0.6))
        let dots = ScreenEffect(id: "k", kind: .kirbyDots, start: 1, target: "hero")
        let atStart = ScreenEffects.state(at: 1, effects: [lines, dots], fps: 24)
        XCTAssertEqual(atStart.focusLines, 0, "focus lines close in")
        let middle = ScreenEffects.state(at: 1.6, effects: [lines, dots], fps: 24) { $0 == "hero" ? Vec2(0.8, 0.2) : nil }
        XCTAssertEqual(middle.focusLines, 1, accuracy: 1e-9)
        XCTAssertEqual(middle.focusCenter, Vec2(0.3, 0.6))
        XCTAssertEqual(middle.kirbyCenter, Vec2(0.8, 0.2), "Kirby dots follow the thing")
        XCTAssertEqual(middle.kirbySpread, 0.4, accuracy: 1e-9)
        XCTAssertFalse(middle.isEmpty)
        let lost = ScreenEffects.state(at: 1.6, effects: [dots], fps: 24)
        XCTAssertEqual(lost.kirbyCenter, Vec2(0.5, 0.5), "a thing that can't be found leaves them in the middle")
        let impact = ScreenEffects.state(at: 2, effects: [ScreenEffect(id: "i", kind: .impact, start: 2)], fps: 24)
        XCTAssertEqual(impact.impact, 1, "an impact frame is there at once")
        XCTAssertEqual(ScreenEffects.state(at: 2, effects: [], fps: 24).drawnSeed, ScreenEffects.state(at: 2.04, effects: [], fps: 24).drawnSeed,
                       "drawn on twos: two frames share a drawing")
        XCTAssertTrue(ScreenEffect.Kind.kirbyDots.aims)
        XCTAssertFalse(ScreenEffect.Kind.flash.aims)
    }

    func testGroundsAreMadeOfSomething() throws {
        let snow = Ground().made(of: .snow)
        XCTAssertEqual(snow.surface, .snow)
        XCTAssertEqual(snow.color, GroundSurface.snow.color)
        XCTAssertTrue(snow.visible)
        XCTAssertEqual(Ground().made(of: .roomFloor).size, 12, "a room is a room")
        let plain = snow.made(of: nil)
        XCTAssertNil(plain.surface)
        XCTAssertEqual(plain.color, snow.color, "back to plain keeps the colour")
        XCTAssertEqual(GroundSurface.allCases.map(\.shaderIndex), Array(1 ... 8))
        XCTAssertEqual(GroundSurface.allCases.count, 8)
        let data = try JSONEncoder().encode(Ground())
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("surface"))
        XCTAssertEqual(try JSONDecoder().decode(Ground.self, from: JSONEncoder().encode(snow)), snow)
    }

    func testTheLibraryKeepsYourLooksEffectsPartsAndWhereThingsCameFrom() throws {
        var library = LibraryManifest()
        XCTAssertFalse(String(decoding: try LoweyJSON.encode(library), as: UTF8.self).contains("styles"))
        library.styles = [LookPreset.painterly.duplicated(id: "mine", name: "My Painterly")]
        library.effects = [SavedEffect(id: "e", name: "Blue fire", recipe: .preset(.fire), added: Date(timeIntervalSince1970: 1))]
        library.parts = [SavedPart(id: "p", name: "Horn", job: .extra, fragment: SceneFragment(objects: [], roots: []),
                                   added: Date(timeIntervalSince1970: 1))]
        library.origins[LibraryKind.effect.key("e")] = HmmPackOrigin(author: "Lina", licence: .credit, pack: "Fires",
                                                                     imported: Date(timeIntervalSince1970: 2))
        let data = try SchemaCoder.shared.encode(library, kind: .library)
        let read = try SchemaCoder.shared.decode(LibraryManifest.self, kind: .library, from: data)
        XCTAssertEqual(read.style("mine")?.name, "My Painterly")
        XCTAssertEqual(read.effect("e")?.recipe, .preset(.fire))
        XCTAssertEqual(read.part("p")?.job, .extra)
        XCTAssertEqual(read.origin(.effect, "e")?.author, "Lina")
        XCTAssertNil(read.origin(.brush, "e"))
    }
}
