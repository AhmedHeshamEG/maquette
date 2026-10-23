import Foundation

/// A review pin (U8): a note stuck on a spot of the scene, carried in the file and answered in place. It rides on a
/// thing (its point is in the thing's own space, so the note follows it when it moves) or, with no thing under it, on
/// the world. A resolved note stays in the file, out of the way.
public struct ReviewNote: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    /// The thing it's stuck on.
    public var object: ObjectID?
    /// Where on it, in the thing's space (in the world's without a thing).
    public var point: Vec3
    /// Where it was in the world when written: kept for a note whose thing has since been deleted.
    public var world: Vec3
    public var author: String
    public var text: String
    public var date: Date
    /// The moment of the film it was written at (a note on a shot).
    public var time: Double?
    public var replies: [ReviewReply]
    public var resolved: Bool

    public init(id: String = UUID().uuidString, object: ObjectID?, point: Vec3, world: Vec3, author: String, text: String,
                date: Date = Date(), time: Double? = nil, replies: [ReviewReply] = [], resolved: Bool = false) {
        self.id = id
        self.object = object
        self.point = point
        self.world = world
        self.author = author
        self.text = text
        self.date = date
        self.time = time
        self.replies = replies
        self.resolved = resolved
    }

    private enum CodingKeys: String, CodingKey {
        case id, object, point, world, author, text, date, time, replies, resolved
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(ObjectID.self, forKey: .object)
        point = try container.decode(Vec3.self, forKey: .point)
        world = try container.decodeIfPresent(Vec3.self, forKey: .world) ?? point
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? Date(timeIntervalSinceReferenceDate: 0)
        time = try container.decodeIfPresent(Double.self, forKey: .time)
        replies = try container.decodeIfPresent([ReviewReply].self, forKey: .replies) ?? []
        resolved = try container.decodeIfPresent(Bool.self, forKey: .resolved) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(object, forKey: .object)
        try container.encode(point, forKey: .point)
        try container.encode(world, forKey: .world)
        try container.encode(author, forKey: .author)
        try container.encode(text, forKey: .text)
        try container.encode(date, forKey: .date)
        try container.encodeIfPresent(time, forKey: .time)
        if !replies.isEmpty { try container.encode(replies, forKey: .replies) }
        if resolved { try container.encode(resolved, forKey: .resolved) }
    }

    /// The pin's place in the world now.
    public func position(in scene: Scene) -> Vec3 {
        guard let object, scene.objects[object] != nil else { return world }
        return scene.worldTransform(of: object).apply(to: point)
    }

    /// Who has written in it, in order of first word.
    public var people: [String] {
        var seen = Set<String>()
        return ([author] + replies.map(\.author)).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

/// An answer in a note's thread.
public struct ReviewReply: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var author: String
    public var text: String
    public var date: Date

    public init(id: String = UUID().uuidString, author: String, text: String, date: Date = Date()) {
        self.id = id
        self.author = author
        self.text = text
        self.date = date
    }
}

/// Insert, replace or remove one note (`Scene.notes`), as `SheetEdit` does for sheets.
public struct NoteEdit: Codable, Hashable, Sendable {
    public var id: String
    public var note: ReviewNote?
    public var index: Int?

    public init(id: String, note: ReviewNote?, index: Int? = nil) {
        self.id = id
        self.note = note
        self.index = index
    }

    public init(_ note: ReviewNote) {
        self.init(id: note.id, note: note)
    }
}

/// Making and answering notes as commands (one undo step each).
public enum ReviewNotes {
    /// A note at `world`, on `object` when there is one under it.
    public static func add(_ text: String, by author: String, at world: Vec3, on object: ObjectID?, time: Double? = nil,
                           in scene: Scene, id: String = UUID().uuidString, date: Date = Date()) -> (EditCommand, ReviewNote) {
        let thing = object.flatMap { scene.objects[$0] != nil ? $0 : nil }
        let point = thing.map { scene.worldTransform(of: $0).inverseApply(to: world) } ?? world
        let note = ReviewNote(id: id, object: thing, point: point, world: world, author: author, text: text, date: date, time: time)
        return (.batch("Add note", [.setNotes([NoteEdit(note)])]), note)
    }

    public static func reply(to id: String, _ text: String, by author: String, in scene: Scene, replyID: String = UUID().uuidString,
                             date: Date = Date()) -> EditCommand? {
        guard var note = scene.note(id), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        note.replies.append(ReviewReply(id: replyID, author: author, text: text, date: date))
        // An answer opens a resolved note again: there's something to read.
        note.resolved = false
        return .batch("Reply", [.setNotes([NoteEdit(note)])])
    }

    public static func setResolved(_ id: String, _ resolved: Bool, in scene: Scene) -> EditCommand? {
        guard var note = scene.note(id), note.resolved != resolved else { return nil }
        note.resolved = resolved
        return .batch(resolved ? "Resolve note" : "Reopen note", [.setNotes([NoteEdit(note)])])
    }

    public static func edit(_ id: String, text: String, in scene: Scene) -> EditCommand? {
        guard var note = scene.note(id), note.text != text else { return nil }
        note.text = text
        return .batch("Edit note", [.setNotes([NoteEdit(note)])])
    }

    public static func delete(_ id: String, in scene: Scene) -> EditCommand? {
        guard scene.note(id) != nil else { return nil }
        return .batch("Delete note", [.setNotes([NoteEdit(id: id, note: nil)])])
    }

    /// Every resolved note removed at once.
    public static func clearResolved(in scene: Scene) -> EditCommand? {
        let resolved = scene.notes.filter(\.resolved)
        guard !resolved.isEmpty else { return nil }
        return .batch("Clear resolved notes", [.setNotes(resolved.map { NoteEdit(id: $0.id, note: nil) })])
    }
}

public extension Scene {
    func note(_ id: String) -> ReviewNote? {
        notes.first { $0.id == id }
    }

    /// Notes still waiting for an answer or a fix.
    var openNotes: [ReviewNote] { notes.filter { !$0.resolved } }
}
