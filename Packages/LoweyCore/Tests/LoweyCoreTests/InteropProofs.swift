/// What proves each `carried`, `baked` and `extras` cell of `docs/INTEROP.md` (X1): the format's section, the row, the
/// direction, the word the cell must say, and the test (`Class.testName`) that shows it.
enum InteropProofs {
    struct Proof {
        var format: String
        var feature: String
        var direction: String
        var claim: String
        var test: String
    }

    static let gltf = "glTF (.glb, .gltf)", folder = "three.js folder (Export ▸ 3D ▸ three.js)"
    static let threeJSON = "three.js JSON (`scene.toJSON()`, `ObjectLoader`)", usd = "USD / USDZ", obj = "OBJ / MTL"
    static let roundTrip = "InteropTests.testGLTFRoundTripKeepsHierarchyMaterialsAndAnimation"
    static let pointers = "GLTFPointerTests.testEveryKeyedNumberComesBack"
    static let threeJSONTest = "ThreeProjectTests.testSceneJSONIsTheGLBInThreesOwnFormat"
    static let folderTest = "ThreeProjectTests.testTheFolderHoldsEverythingNamedOnce"
    static let threeJSONBack = "ThreeObjectReaderTests.testAScenesJSONComesBackAsItWas"
    static let threeMF = "PrintingTests.test3MFRoundTripKeepsPartsColoursAndSize"
    static let drawings = "GuestDrawingTests.testDrawingsLeaveAsPDFSVGAndDXF"

    static let all: [Proof] = gltfProofs + threeProofs + otherProofs

    static let gltfProofs: [Proof] = [
        Proof(format: gltf, feature: "Meshes and hierarchy", direction: "Out", claim: "carried", test: roundTrip),
        Proof(format: gltf, feature: "Meshes and hierarchy", direction: "In", claim: "carried", test: roundTrip),
        Proof(format: gltf, feature: "Paint layers and maps", direction: "Out", claim: "baked",
              test: "TextureExportTests.testAPaintedSmudgedMaskedModelExportsEveryMap"),
        Proof(format: gltf, feature: "Materials", direction: "Out", claim: "carried", test: roundTrip),
        Proof(format: gltf, feature: "Materials", direction: "In", claim: "carried", test: roundTrip),
        Proof(
            format: gltf,
            feature: "Rigs and skins",
            direction: "Out",
            claim: "carried",
            test: "SkinExportTests.testARiggedThingLeavesAsASkinWithItsJointsKeyed"
        ),
        Proof(format: gltf, feature: "Face states", direction: "Out", claim: "extras", test: pointers),
        Proof(format: gltf, feature: "Face states", direction: "In", claim: "extras", test: pointers),
        Proof(format: gltf, feature: "Keys on any property", direction: "Out", claim: "carried", test: pointers),
        Proof(format: gltf, feature: "Keys on any property", direction: "In", claim: "carried", test: pointers),
        Proof(format: gltf, feature: "Lights", direction: "Out", claim: "carried", test: roundTrip),
        Proof(format: gltf, feature: "Lights", direction: "In", claim: "carried", test: roundTrip),
        Proof(format: gltf, feature: "Units and dimensions", direction: "Out", claim: "carried", test: roundTrip),
        Proof(format: gltf, feature: "Units and dimensions", direction: "In", claim: "carried", test: roundTrip)
    ]

    static let threeProofs: [Proof] = [
        Proof(format: folder, feature: "Meshes and hierarchy", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: folder, feature: "Materials", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: folder, feature: "The Looks", direction: "Out", claim: "baked", test: folderTest),
        Proof(format: folder, feature: "Keys on any property", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: folder, feature: "Cameras", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: folder, feature: "Lights", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: folder, feature: "Scenes and shots", direction: "Out", claim: "carried", test: folderTest),
        Proof(format: threeJSON, feature: "Meshes and hierarchy", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: threeJSON, feature: "Materials", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: threeJSON, feature: "Keys on any property", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: threeJSON, feature: "Cameras", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: threeJSON, feature: "Lights", direction: "Out", claim: "carried", test: threeJSONTest),
        Proof(format: threeJSON, feature: "Meshes and hierarchy", direction: "In", claim: "carried", test: threeJSONBack),
        Proof(format: threeJSON, feature: "Materials", direction: "In", claim: "carried", test: threeJSONBack),
        Proof(
            format: threeJSON,
            feature: "Clones and links",
            direction: "In",
            claim: "baked",
            test: "ThreeObjectReaderTests.testAVibeCodedIslandComesInAsThings"
        ),
        Proof(format: threeJSON, feature: "Keys on any property", direction: "In", claim: "carried", test: threeJSONBack),
        Proof(format: threeJSON, feature: "Cameras", direction: "In", claim: "carried", test: threeJSONBack),
        Proof(format: threeJSON, feature: "Lights", direction: "In", claim: "carried", test: threeJSONBack)
    ]

    static let otherProofs: [Proof] = [
        Proof(
            format: usd,
            feature: "Paint layers and maps",
            direction: "Out",
            claim: "baked",
            test: "TextureExportTests.testUSDZCarriesTheMapsAndAPNGSetNamesThem"
        ),
        Proof(format: "FBX", feature: "Rigs and skins", direction: "Out", claim: "carried", test: "SkinExportTests.testARiggedThingLeavesAsAnFBXOfItsOwn"),
        Proof(format: obj, feature: "Meshes and hierarchy", direction: "Out", claim: "baked", test: "InteropTests.testOBJHasEveryCornerFaceAndMaterial"),
        Proof(format: obj, feature: "Materials", direction: "Out", claim: "baked", test: "InteropTests.testOBJHasEveryCornerFaceAndMaterial"),
        Proof(format: obj, feature: "Paint layers and maps", direction: "Out", claim: "baked", test: "PaintExportTests.testUSDZAndOBJCarryTheTexture"),
        Proof(format: obj, feature: "Paint layers and maps", direction: "In", claim: "baked", test: "SculptImportTests.testOBJColoursAfterEachCornerAreRead"),
        Proof(format: "STL", feature: "Meshes and hierarchy", direction: "Out", claim: "baked", test: "PrintingTests.testSTLIsMillimetresWithZUp"),
        Proof(format: "STL", feature: "Meshes and hierarchy", direction: "In", claim: "baked", test: "PrintingTests.testASCIISTLReads"),
        Proof(format: "STL", feature: "Units and dimensions", direction: "Out", claim: "carried", test: "PrintingTests.testSTLIsMillimetresWithZUp"),
        Proof(format: "STL", feature: "Units and dimensions", direction: "In", claim: "carried", test: "PrintingTests.testTheM3BlockExportsAWatertightSTL"),
        Proof(format: "3MF", feature: "Meshes and hierarchy", direction: "Out", claim: "carried", test: threeMF),
        Proof(format: "3MF", feature: "Meshes and hierarchy", direction: "In", claim: "carried", test: threeMF),
        Proof(format: "3MF", feature: "Materials", direction: "Out", claim: "baked", test: threeMF),
        Proof(format: "3MF", feature: "Materials", direction: "In", claim: "baked", test: threeMF),
        Proof(format: "3MF", feature: "Paint layers and maps", direction: "Out", claim: "baked",
              test: "GuestPrintTests.testAMultiColour3MFGivesEachColourItsFilament"),
        Proof(format: "3MF", feature: "Units and dimensions", direction: "Out", claim: "carried", test: threeMF),
        Proof(format: "3MF", feature: "Units and dimensions", direction: "In", claim: "carried", test: threeMF),
        Proof(
            format: "SVG",
            feature: "Text and logos",
            direction: "In",
            claim: "baked",
            test: "MotionDesignTests.testALogoStandsUpOneSolidAColourTheTopColourProud"
        ),
        Proof(format: "SVG", feature: "Units and dimensions", direction: "Out", claim: "baked", test: drawings),
        Proof(format: "DXF", feature: "Units and dimensions", direction: "Out", claim: "baked", test: drawings),
        Proof(format: "DXF", feature: "Units and dimensions", direction: "In", claim: "baked",
              test: "GuestDrawingTests.testADXFUnderlayReadsLinesArcsAndCirclesInItsUnits"),
        Proof(format: "Blender (the package out, the add-on in)", feature: "Meshes and hierarchy", direction: "Out", claim: "carried",
              test: "InteropTests.testThePackageHoldsTheSceneTheSettingsAndTheScript"),
        Proof(format: "Pictures and video (PNG, JPEG, HEIC, EXR, PSD, Lottie, image sequences, MP4, MOV)", feature: "Sheets", direction: "In",
              claim: "baked", test: "DioramaTests.testAFiveLayerDrawingBecomesFiveSheetsStackedInDepth")
    ]
}
