import Foundation

/// The people who support Maquette, read from `SUPPORTERS.md` (the one list; the README links it and each build
/// carries it, so the credits need no network). Founding Supporters are numbered #1 to #100 in the order they joined;
/// everyone who bought a coffee is listed by name.
public struct SupportersList: Equatable, Sendable {
    public struct Founding: Equatable, Sendable {
        public let number: Int
        public let name: String
    }

    /// The numbers stop here: the first 100 keep theirs for good.
    public static let foundingLimit = 100

    public var founding: [Founding]
    public var coffee: [String]

    public init(founding: [Founding] = [], coffee: [String] = []) {
        self.founding = founding
        self.coffee = coffee
    }

    public var isEmpty: Bool { founding.isEmpty && coffee.isEmpty }

    /// Reads the file: under `## Founding Supporters`, lines like `- #7 Name`; under `## Coffee`, lines like `- Name`.
    /// Comments, blank lines and anything else are skipped; numbers outside 1…100 and repeated numbers are dropped.
    public init(markdown: String) {
        var founding: [Founding] = []
        var coffee: [String] = []
        var section = ""
        var inComment = false
        for raw in markdown.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if inComment {
                if line.contains("-->") { inComment = false }
                continue
            }
            if line.hasPrefix("<!--") {
                inComment = !line.contains("-->")
                continue
            }
            if line.hasPrefix("## ") {
                section = line.dropFirst(3).lowercased()
                continue
            }
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            let item = line.dropFirst(2).trimmingCharacters(in: .whitespaces)
            guard !item.isEmpty else { continue }
            if section.hasPrefix("founding") {
                guard item.hasPrefix("#") else { continue }
                let parts = item.dropFirst().split(separator: " ", maxSplits: 1)
                guard parts.count == 2, let number = Int(parts[0]), (1 ... Self.foundingLimit).contains(number),
                      !founding.contains(where: { $0.number == number })
                else { continue }
                let name = parts[1].trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                founding.append(Founding(number: number, name: name))
            } else if section.hasPrefix("coffee") {
                coffee.append(item)
            }
        }
        self.founding = founding.sorted { $0.number < $1.number }
        self.coffee = coffee
    }
}

/// The thank-you card after the first export: it gets one turn, ever. The store is wherever the app keeps its flags.
public struct ThankYouCardGate {
    private let isShown: () -> Bool
    private let markShown: () -> Void

    public init(isShown: @escaping () -> Bool, markShown: @escaping () -> Void) {
        self.isShown = isShown
        self.markShown = markShown
    }

    /// True the first time it's asked after an export, and never again.
    public func takeTurn() -> Bool {
        guard !isShown() else { return false }
        markShown()
        return true
    }
}
