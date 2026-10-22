import HmmDesign
import LoweyCore
import SwiftUI
import UIKit

/// Room ▸ Plans (G1): each floor's plan in black and white from above, cut at 1.2 m, every room named with its area,
/// and the four elevations, drawn as the export draws them (Export ▸ Paper ▸ Plans & elevations prints them).
struct PlanSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme
    @State private var pages: [(title: String, art: LineArt, rooms: [RoomFinder.Room])] = []
    @State private var page = 0
    @State private var working = true

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HmmSpacing.m) {
                if working {
                    ProgressView("Drawing the plans").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pages.isEmpty {
                    Text("Nothing to draw yet: add walls in Model ▸ Add ▸ Building.").foregroundStyle(theme.text2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Picker("Drawing", selection: $page) {
                        ForEach(pages.indices, id: \.self) { Text(LocalizedStringKey(pages[$0].title)).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("plans-page")
                    LineArtView(art: pages[min(page, pages.count - 1)].art)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityIdentifier("plans-drawing")
                    rooms
                }
            }
            .padding(HmmSpacing.l)
            .navigationTitle("Plans")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task { await draw() }
    }

    @ViewBuilder private var rooms: some View {
        let shown = pages[min(page, pages.count - 1)].rooms
        if !shown.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: HmmSpacing.s) {
                    ForEach(shown.indices, id: \.self) { index in
                        VStack(alignment: .leading) {
                            Text(shown[index].name).font(.hmm(.footnote, weight: .semibold))
                            Text(PlanDrawing.area(shown[index].area, units: editor.units)).font(.hmmNumbers(.footnote))
                                .foregroundStyle(theme.text2)
                        }
                        .padding(HmmSpacing.s)
                        .background(theme.surface2, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .accessibilityIdentifier("plans-rooms")
        }
    }

    private func draw() async {
        let (elements, labels) = editor.shownBuilding()
        let units = editor.units
        let made = await Task.detached(priority: .userInitiated) { () -> [(title: String, art: LineArt, rooms: [RoomFinder.Room])] in
            guard !elements.isEmpty else { return [] }
            let floors = BuildingDrawings.floors(elements, labels: labels, units: units)
            let soup = BuildingDrawings.soup(elements).soup
            let elevations = PlanDrawing.Side.allCases.map { side in (side.title, PlanDrawing.elevation(soup, side: side), [RoomFinder.Room]()) }
            return floors.map { ($0.title, $0.art, $0.rooms) } + elevations
        }.value
        pages = made
        working = false
    }
}

/// A line drawing fitted into its frame: cut walls filled black, lines in their weights and dashes, the words.
struct LineArtView: View {
    let art: LineArt

    var body: some View {
        Canvas { context, size in
            guard let bounds = art.bounds else { return }
            let width = max(bounds.max.x - bounds.min.x, 1e-6), height = max(bounds.max.y - bounds.min.y, 1e-6)
            let scale = min((size.width - 40) / width, (size.height - 40) / height)
            let offset = CGPoint(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
            func point(_ p: Vec2) -> CGPoint {
                CGPoint(x: offset.x + (p.x - bounds.min.x) * scale, y: size.height - offset.y - (p.y - bounds.min.y) * scale)
            }
            let pointsPerMillimetre = max(scale / 1000 * 20, 0.6)
            for stroke in art.strokes where stroke.points.count >= 2 {
                var path = Path()
                for loop in [stroke.points] + (stroke.filled ? stroke.holes : []) {
                    path.addLines(loop.map(point))
                    if stroke.closed || stroke.filled { path.closeSubpath() }
                }
                let grey = Color(white: stroke.pen.grey)
                if stroke.filled { context.fill(path, with: .color(Color(white: 0.15)), style: FillStyle(eoFill: true)) }
                context.stroke(path, with: .color(grey), style: StrokeStyle(lineWidth: max(stroke.pen.weight * pointsPerMillimetre, 0.5), lineCap: .round,
                                                                            lineJoin: .round,
                                                                            dash: stroke.pen.dashes.map { $0 * pointsPerMillimetre }))
            }
            for label in art.labels {
                let text = Text(label.text).font(.system(size: max(label.size * 4, 9), weight: label.bold ? .semibold : .regular))
                    .foregroundStyle(Color.black)
                context.draw(text, at: point(label.at), anchor: label.anchor == .start ? .leading : label.anchor == .end ? .trailing : .center)
            }
        }
    }
}

/// Room ▸ Match a photo (G1): two lines along one direction of the room and two along the direction square to it, the
/// ground's origin, and how high the camera was; the shot camera then stands where the photo was taken and the photo
/// shows behind the stage, so what's built sits in it.
struct PhotoMatchSheet: View {
    let editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.hmmTheme) private var theme
    @State private var picking = true
    @State private var photo: UIImage?
    @State private var source: URL?
    /// Points in the photo's pixels: the first pair's ends, the second pair's, the origin.
    @State private var points: [CGPoint] = []
    @State private var height = 1.6

    var body: some View {
        NavigationStack {
            VStack(spacing: HmmSpacing.m) {
                if let photo {
                    Text("Drag the red lines along one direction of the room, the blue along the one square to it, the dot to a point on the ground.")
                        .font(.hmm(.footnote)).foregroundStyle(theme.text2)
                    PhotoLines(photo: photo, points: $points)
                    LabeledSlider(title: "Camera height", value: height, range: 0.3 ... 3, format: { String(format: "%.2f m", $0) }) { height = $0 }
                    HmmPillButton("Match", systemName: "camera.viewfinder", prominent: true) { match(photo) }
                        .accessibilityIdentifier("photo-match")
                } else {
                    HmmPillButton("Choose a photo", systemName: "photo") { picking = true }
                }
            }
            .padding(HmmSpacing.l)
            .navigationTitle("Match a photo")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
            photo = image
            source = url
            points = PhotoLines.starting(image.size)
        }
    }

    private func match(_ photo: UIImage) {
        func line(_ a: Int) -> PhotoMatch.Line { PhotoMatch.Line(Vec2(points[a].x, points[a].y), Vec2(points[a + 1].x, points[a + 1].y)) }
        do throws(PhotoMatch.Failure) {
            let camera = try PhotoMatch.solve(width: photo.size.width, height: photo.size.height, first: (line(0), line(2)), second: (line(4), line(6)),
                                              origin: Vec2(points[8].x, points[8].y), cameraHeight: height)
            Task {
                await editor.applyPhotoMatch(camera, photo: photo)
                dismiss()
            }
        } catch {
            editor.app.show(String.LocalizationValue(error.description), kind: .error)
        }
    }
}

/// The photo with its four lines and the origin to drag.
struct PhotoLines: View {
    let photo: UIImage
    @Binding var points: [CGPoint]

    /// Where the lines start: two leaning one way, two the other, the origin low in the middle.
    static func starting(_ size: CGSize) -> [CGPoint] {
        let w = size.width, h = size.height
        return [CGPoint(x: w * 0.1, y: h * 0.75), CGPoint(x: w * 0.45, y: h * 0.62), CGPoint(x: w * 0.1, y: h * 0.4), CGPoint(x: w * 0.45, y: h * 0.38),
                CGPoint(x: w * 0.9, y: h * 0.75), CGPoint(x: w * 0.55, y: h * 0.62), CGPoint(x: w * 0.9, y: h * 0.4), CGPoint(x: w * 0.55, y: h * 0.38),
                CGPoint(x: w * 0.5, y: h * 0.8)]
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / photo.size.width, geometry.size.height / photo.size.height)
            let shown = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
            ZStack(alignment: .topLeading) {
                Image(uiImage: photo).resizable().frame(width: shown.width, height: shown.height)
                ForEach(0 ..< 4, id: \.self) { pair in
                    if points.count == 9 {
                        Path { path in
                            path.move(to: CGPoint(x: points[pair * 2].x * scale, y: points[pair * 2].y * scale))
                            path.addLine(to: CGPoint(x: points[pair * 2 + 1].x * scale, y: points[pair * 2 + 1].y * scale))
                        }
                        .stroke(pair < 2 ? Color.red : Color.blue, lineWidth: 2)
                    }
                }
                ForEach(points.indices, id: \.self) { index in
                    Circle().fill(index == 8 ? Color.yellow : index < 4 ? Color.red : Color.blue).frame(width: 22, height: 22)
                        .position(x: points[index].x * scale, y: points[index].y * scale)
                        .gesture(DragGesture().onChanged { value in
                            points[index] = CGPoint(x: min(max(value.location.x / scale, 0), photo.size.width),
                                                    y: min(max(value.location.y / scale, 0), photo.size.height))
                        })
                        .accessibilityLabel(index == 8 ? "Origin" : "Line end \(index + 1)")
                }
            }
            .frame(width: shown.width, height: shown.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
