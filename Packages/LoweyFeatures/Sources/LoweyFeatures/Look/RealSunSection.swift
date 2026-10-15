import HmmDesign
import LoweyCore
import SwiftUI

/// Look ▸ World ▸ Real sun (P1): the sun of a place, a date and a time, or a shadow study that runs the day across the
/// timeline. For architects' sun studies and anyone who wants the light of a real afternoon.
struct RealSunSection: View {
    let editor: EditorModel
    private var sun: RealSun? { editor.look.lighting.realSun }

    var body: some View {
        VStack(alignment: .leading, spacing: HmmSpacing.s) {
            Toggle("Real sun", isOn: Binding(get: { sun != nil }, set: { on in
                editor.updateLook { $0.lighting.realSun = on ? Self.start() : nil }
            }))
            .accessibilityIdentifier("real-sun")
            if let sun { details(sun) }
        }
    }

    /// Rome, today, mid-afternoon.
    static func start() -> RealSun {
        var sun = RealSun.places[0]
        let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        (sun.year, sun.month, sun.day) = (today.year ?? 2026, today.month ?? 6, today.day ?? 21)
        sun.hour = 15
        return sun
    }

    @ViewBuilder
    private func details(_ sun: RealSun) -> some View {
        Menu {
            ForEach(RealSun.places, id: \.place) { place in
                Button(place.place) {
                    change { ($0.place, $0.latitude, $0.longitude, $0.utcOffset) = (place.place, place.latitude, place.longitude, place.utcOffset) }
                }
            }
        } label: {
            Label(sun.place, systemImage: "mappin.and.ellipse").frame(minHeight: 44)
        }
        .accessibilityIdentifier("real-sun-place")
        HStack(spacing: HmmSpacing.xxs) {
            HmmNumberPill("Latitude", value: Binding(get: { sun.latitude }, set: { value in change(coalesce: true) {
                $0.latitude = min(max(value, -90), 90)
                $0.place = String(localized: "Here")
            } }), scrub: HmmScrub(fine: 0.01, range: -90 ... 90), format: { String(format: "%.3f°", $0) }, onEditingChanged: done)
            HmmNumberPill("Longitude", value: Binding(get: { sun.longitude }, set: { value in change(coalesce: true) {
                $0.longitude = min(max(value, -180), 180)
                $0.place = String(localized: "Here")
            } }), scrub: HmmScrub(fine: 0.01, range: -180 ... 180), format: { String(format: "%.3f°", $0) }, onEditingChanged: done)
        }
        DatePicker("Date", selection: Binding(get: { Self.date(sun) }, set: { value in
            let parts = Calendar.current.dateComponents([.year, .month, .day], from: value)
            change { ($0.year, $0.month, $0.day) = (parts.year ?? $0.year, parts.month ?? $0.month, parts.day ?? $0.day) }
        }), displayedComponents: .date)
            .accessibilityIdentifier("real-sun-date")
        Toggle("Shadow study across the timeline", isOn: Binding(get: { sun.study != nil }, set: { on in
            change { $0.study = on ? 7 ... 19 : nil }
        }))
        .accessibilityIdentifier("real-sun-study")
        if let study = sun.study {
            LabeledSlider(title: "From", value: study.lowerBound, range: 0 ... 23, format: Self.clock) { value in
                change(coalesce: true) { $0.study = min(value, study.upperBound - 0.5) ... study.upperBound }
            } done: { editor.endGesture() }
            LabeledSlider(title: "To", value: study.upperBound, range: 1 ... 24, format: Self.clock) { value in
                change(coalesce: true) { $0.study = study.lowerBound ... max(value, study.lowerBound + 0.5) }
            } done: { editor.endGesture() }
        } else {
            LabeledSlider(title: "Time", value: sun.hour, range: 0 ... 24, format: Self.clock) { value in
                change(coalesce: true) { $0.hour = value }
            } done: { editor.endGesture() }
                .accessibilityIdentifier("real-sun-hour")
        }
        LabeledSlider(title: "North points", value: sun.north, range: 0 ... 359, format: { "\(Int($0.rounded()))°" }) { value in
            change(coalesce: true) { $0.north = value }
        } done: { editor.endGesture() }
            .accessibilityIdentifier("real-sun-north")
        Hint("Clock time in \(sun.place) (UTC\(sun.utcOffset >= 0 ? "+" : "")\(String(format: "%g", sun.utcOffset))). North 0° is away from you on the grid.")
    }

    private func change(coalesce: Bool = false, _ edit: (inout RealSun) -> Void) {
        editor.updateLook(coalesce: coalesce ? "real-sun" : nil) { look in
            guard var sun = look.lighting.realSun else { return }
            edit(&sun)
            look.lighting.realSun = sun
        }
    }

    private func done(_ editing: Bool) {
        if !editing { editor.endGesture() }
    }

    static func date(_ sun: RealSun) -> Date {
        Calendar.current.date(from: DateComponents(year: sun.year, month: sun.month, day: sun.day, hour: 12)) ?? Date()
    }

    static func clock(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }
}
