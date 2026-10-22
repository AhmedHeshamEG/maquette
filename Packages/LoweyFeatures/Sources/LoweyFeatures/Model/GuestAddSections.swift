import HmmDesign
import LoweyCore
import SwiftUI
import UniformTypeIdentifiers

/// Model ▸ Add's guest kit (G1): what the project is set up for puts its pieces here, and a Blank project shows none.
/// Room: the building tools and its plans, walk, underlays, a photo to match and a room scan. Print: the jar and lid,
/// bolts and nuts. Game: the greybox kit.
struct GuestAddSections: View {
    @Bindable var editor: EditorModel
    @State private var importingUnderlay = false

    var body: some View {
        switch editor.projectSetUp {
        case .room: room
        case .print: print
        case .game: game
        default: EmptyView()
        }
    }

    private var room: some View {
        Group {
            PanelSection("Building") {
                TileGrid {
                    ForEach(BuildTool.building) { build in
                        TileButton(title: build.title, systemName: build.systemImage, identifier: "build-\(build.rawValue)") {
                            editor.startModeling(.build(build))
                            editor.openPanel = nil
                        }
                    }
                }
                Picker("Roof", selection: $editor.guest.roofKind) {
                    ForEach(RoomParts.RoofKind.allCases, id: \.self) { Text(LocalizedStringKey($0.title)).tag($0) }
                }
                .accessibilityIdentifier("roof-kind")
                Hint("Walls follow the corners you tap; doors and windows go where you tap a wall; a roof follows the walls' tops.")
            }
            PanelSection("Plans and the site") {
                TileGrid {
                    TileButton(title: "Plans", systemName: "square.split.2x2", identifier: "room-plans") { editor.sheet = .plans }
                    TileButton(title: "Walk through", systemName: "figure.walk", identifier: "room-walk") {
                        editor.openPanel = nil
                        editor.startWalking()
                    }
                    TileButton(title: "Underlay", systemName: "doc.viewfinder", identifier: "room-underlay") { importingUnderlay = true }
                    TileButton(title: "Match a photo", systemName: "photo.badge.checkmark", identifier: "room-photo") { editor.sheet = .matchPhoto }
                    if RoomScanSheet.isSupported {
                        TileButton(title: "Scan a room", systemName: "camera.metering.matrix", identifier: "room-scan") { editor.sheet = .roomScan }
                    }
                }
                Hint("An underlay is a PDF, DXF or picture of a plan: lay it flat, set it to scale with two taps, trace it.")
            }
        }
        .fileImporter(isPresented: $importingUnderlay,
                      allowedContentTypes: EditorModel.underlayTypes.compactMap { UTType(filenameExtension: $0) }) { result in
            if case let .success(url) = result {
                editor.openPanel = nil
                editor.importUnderlay(url)
            }
        }
    }

    private var print: some View {
        PanelSection("Print") {
            TileGrid {
                ForEach(ModelingOperations.PrintPiece.allCases, id: \.self) { piece in
                    TileButton(title: piece.title, systemName: piece.systemImage, identifier: "print-\(piece.rawValue)") {
                        editor.addPrintPiece(piece)
                        editor.openPanel = nil
                    }
                }
            }
            Picker("Screw", selection: $editor.guest.screw) {
                ForEach(MetricScrew.allCases) { Text($0.rawValue).tag($0) }
            }
            .accessibilityIdentifier("print-screw")
            Hint("Bolts and nuts are the screw size above; the lid fits the jar by the fit in Model ▸ Edit ▸ 3D print.")
        }
    }

    private var game: some View {
        PanelSection("Greybox") {
            TileGrid {
                ForEach(GreyboxPiece.allCases) { piece in
                    TileButton(title: piece.title, systemName: piece.systemImage, identifier: "greybox-\(piece.rawValue)") {
                        editor.addGreybox(piece)
                        editor.openPanel = nil
                    }
                }
            }
            Hint("Pieces sit on the metre grid and snap edge to edge; turn them a quarter at a time.")
        }
    }
}
