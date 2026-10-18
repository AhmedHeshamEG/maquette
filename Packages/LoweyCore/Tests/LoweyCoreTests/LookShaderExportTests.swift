import Foundation
@testable import LoweyCore
import XCTest

/// A1: a Look leaves as a Godot shader and a Unity URP shader with its licence. `ACCEPTANCE_DIR` writes the Ink Look's
/// Godot files for CI, where Godot renders them against a golden picture.
final class LookShaderExportTests: XCTestCase {
    private func text(_ files: [(name: String, data: Data)], _ suffix: String) throws -> String {
        let file = try XCTUnwrap(files.first { $0.name.hasSuffix(suffix) }, "no \(suffix)")
        return String(decoding: file.data, as: UTF8.self)
    }

    func testTheInkLookLeavesForGodotWithItsNumbersAndItsLicence() throws {
        let files = LookShaderExport.files(.ink, engine: .godot, author: "Ada")
        XCTAssertEqual(Set(files.map(\.name)), ["maquette_ink.gdshader", "maquette_ink_outline.gdshader", "maquette_ink.tres", "LICENSE.txt",
                                                "README.txt"])
        let surface = try text(files, "ink.gdshader")
        XCTAssertTrue(surface.hasPrefix("// The Ink Look from Maquette"))
        XCTAssertTrue(surface.contains("shader_type spatial;"))
        XCTAssertTrue(surface.contains("uniform float threshold : hint_range(0.0, 1.0) = 0.5000;"), "the Look's own numbers")
        XCTAssertTrue(surface.contains("uniform int bands : hint_range(2, 3) = 2;"))
        XCTAssertTrue(surface.contains("void light()"))
        let outline = try text(files, "_outline.gdshader")
        XCTAssertTrue(outline.contains("cull_front"))
        XCTAssertTrue(outline.contains("uniform float line_width : hint_range(0.0, 8.0) = 1.6000;"))
        let material = try text(files, ".tres")
        XCTAssertTrue(material.contains("next_pass = SubResource(\"ShaderMaterial_outline\")"))
        XCTAssertTrue(material.contains("path=\"maquette_ink.gdshader\""), "relative to the material, so the folder goes anywhere")
        let licence = try text(files, "LICENSE.txt")
        XCTAssertTrue(licence.contains("Made by Ada with Maquette."))
        XCTAssertTrue(licence.contains("commercial included"))
        XCTAssertTrue(try text(files, "README.txt").contains("never identical"))
        for file in files {
            XCTAssertTrue(String(decoding: file.data, as: UTF8.self).allSatisfy { $0.isASCII }, "\(file.name) is plain ASCII")
        }
        try write(files)
    }

    func testEveryLookLeavesForUnityAsOneShaderWithBothPasses() throws {
        for preset in LookPreset.builtIns {
            let files = LookShaderExport.files(preset, engine: .unity)
            let shader = try text(files, ".shader")
            XCTAssertTrue(shader.contains("Shader \"Maquette/\(preset.name)\""))
            XCTAssertTrue(shader.contains("\"LightMode\" = \"UniversalForward\""))
            XCTAssertTrue(shader.contains("\"LightMode\" = \"SRPDefaultUnlit\""))
            XCTAssertEqual(shader.components(separatedBy: "{").count, shader.components(separatedBy: "}").count, "braces balance")
            XCTAssertTrue(try text(files, "LICENSE.txt").contains("Made with Maquette."))
        }
        let lowPoly = try text(LookShaderExport.files(.lowPoly, engine: .godot), "low_poly.gdshader")
        XCTAssertTrue(lowPoly.contains("uniform bool faceted = true;"), "low-poly keeps its facets")
        let clay = try text(LookShaderExport.files(.clay, engine: .godot), "clay.gdshader")
        XCTAssertTrue(clay.contains("uniform bool clay = true;"))
    }

    func testTheArchiveIsOneFolderNamedForThePerson() throws {
        let (name, data) = LookShaderExport.archive(.comic, engine: .godot)
        XCTAssertEqual(name, "Comic Look for Godot.zip")
        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04], "a zip")
        XCTAssertNotNil(String(decoding: data, as: UTF8.self).range(of: "Comic Look for Godot/maquette_comic.tres"))
        XCTAssertEqual(LookShaderExport.slug("My Ink 2!"), "my_ink_2")
        XCTAssertEqual(LookShaderExport.slug("草"), "look")
    }

    private func write(_ files: [(name: String, data: Data)]) throws {
        guard let directory = ProcessInfo.processInfo.environment["ACCEPTANCE_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("look-shader")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: url.appendingPathComponent(file.name))
        }
    }
}
