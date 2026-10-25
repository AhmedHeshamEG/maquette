import Foundation

/// A minute of real use, measured touch by touch (an app's Diagnostics ▸ Record). Every touch is followed to the
/// refresh that shows its answer, and its time is split into input, main thread, encode and GPU. The app shares the
/// JSON; a script turns it into a ranked list of the slowest moments. Times are milliseconds unless they say seconds.
public struct FeelRecording: Codable, Sendable, Equatable {
    /// One delivery of touches to the app (a press, a lift, or one frame's worth of a moving finger or Pencil).
    public struct Touch: Codable, Sendable, Equatable {
        /// Seconds from the start of the recording to the touch (the hardware's own timestamp).
        public var t: Double
        /// `began`, `moved`, `ended` or `cancelled`.
        public var phase: String
        /// `finger` or `pencil`.
        public var kind: String
        /// How many touches were down.
        public var count: Int
        /// Where, in points in the window.
        public var x: Double
        public var y: Double
        /// The view the touch landed in (its type, without generic arguments).
        public var target: String
        /// What was on screen (the app says).
        public var screen: String
        /// From the touch to the app receiving it.
        public var input: Double
        /// The main thread's work after receiving it: until it went idle, or until a Metal surface started drawing.
        public var main: Double
        /// A Metal surface's frame that answered it: building and encoding on the CPU, then the GPU.
        public var encode: Double?
        public var gpu: Double?
        /// From the touch to the first refresh that can show the answer.
        public var total: Double
        /// Refreshes missed: 0 when the answer was ready for the first refresh after the app received the touch.
        public var missed: Int
    }

    /// A refresh the screen missed: the display link came late, so the main thread was busy across a refresh.
    public struct Hitch: Codable, Sendable, Equatable {
        public var t: Double
        /// The gap between two refreshes that should have been one apart.
        public var gap: Double
        public var screen: String
    }

    /// The main thread busy for longer than a refresh in one go, touch or not.
    public struct Stall: Codable, Sendable, Equatable {
        public var t: Double
        public var busy: Double
        public var screen: String
    }

    /// A named stretch the app marks (opening a project to its first frame, a panel's first frame).
    public struct Mark: Codable, Sendable, Equatable {
        public var t: Double
        public var name: String
        public var duration: Double
        public var screen: String
    }

    /// A Metal surface's frame: when it started (seconds), its CPU and GPU work.
    public struct SurfaceFrame: Codable, Sendable, Equatable {
        public var t: Double
        public var encode: Double
        public var gpu: Double
    }

    public var app: String
    public var appVersion: String
    public var device: String
    public var system: String
    public var date: Date
    public var seconds: Double = 0
    /// The screen's refresh rate while recording (Hz).
    public var refreshRate: Double = 60
    /// The window's size in points, so a touch's place can be told (a corner cluster, the sidebar, the stage).
    public var width: Double = 0
    public var height: Double = 0
    /// The last cold launch: process start to the first screen (nil when the app didn't measure it).
    public var launch: Double?
    public var touches: [Touch] = []
    public var hitches: [Hitch] = []
    public var stalls: [Stall] = []
    public var marks: [Mark] = []
    public var frames: [SurfaceFrame] = []

    public init(app: String, appVersion: String, device: String, system: String, date: Date = Date()) {
        self.app = app
        self.appVersion = appVersion
        self.device = device
        self.system = system
        self.date = date
    }

    public var fileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let deviceName = device.replacingOccurrences(of: " ", with: "-").replacingOccurrences(of: "/", with: "-")
        return "feel-\(deviceName)-\(appVersion)-\(formatter.string(from: date)).json"
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> FeelRecording {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FeelRecording.self, from: data)
    }
}
