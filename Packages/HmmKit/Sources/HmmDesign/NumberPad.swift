import Foundation

/// Our own number pad (Shapr3D's way): it opens beside the number being typed and never covers the screen as the
/// system keyboard does. This is its typing, pure: what each key makes of the text. The text reads the way the apps
/// already parse typed numbers (`25`, `2*12`, `1.5 cm`, `1 ft 6 in`): ASCII operators, a unit after a number.
public struct HmmNumberPadEntry: Equatable, Sendable {
    public enum Key: Hashable, Sendable {
        case digit(Int)
        case point
        case plus, minus, times, divide
        /// A unit after the number just typed (`mm`, `cm`, `°`…); pressing another unit replaces it.
        case unit(String)
        case backspace
        case clear

        /// What the key shows.
        public var symbol: String {
            switch self {
            case let .digit(value): String(value)
            case .point: "."
            case .plus: "+"
            case .minus: "−"
            case .times: "×"
            case .divide: "÷"
            case let .unit(unit): unit
            case .backspace: "⌫"
            case .clear: "C"
            }
        }

        var operatorCharacter: Character? {
            switch self {
            case .plus: "+"
            case .minus: "-"
            case .times: "*"
            case .divide: "/"
            default: nil
            }
        }
    }

    /// What was typed, in the form the apps parse.
    public private(set) var text: String

    public init(text: String = "") {
        self.text = text
    }

    public var isEmpty: Bool { text.isEmpty }

    /// The text as the pad shows it: real minus, times and divide signs.
    public var display: String {
        String(text.map { character -> Character in
            switch character {
            case "-": "−"
            case "*": "×"
            case "/": "÷"
            default: character
            }
        })
    }

    public mutating func press(_ key: Key) {
        switch key {
        case let .digit(value):
            guard (0 ... 9).contains(value) else { return }
            // After a unit a new number starts (`1 ft 6`).
            if endsWithUnit { text += " " }
            text += String(value)
        case .point:
            if endsWithUnit { text += " " }
            let number = trailingNumber
            guard !number.contains(".") else { return }
            text += number.isEmpty ? "0." : "."
        case .plus, .minus, .times, .divide:
            pressOperator(key)
        case let .unit(unit):
            guard !unit.isEmpty, let last = text.last, !Self.operators.contains(last) else { return }
            if endsWithUnit { removeTrailingUnit() }
            guard text.last.map({ $0.isNumber || $0 == "." || $0 == ")" }) == true else { return }
            text += " " + unit
        case .backspace:
            if endsWithUnit {
                removeTrailingUnit()
            } else if !text.isEmpty {
                text.removeLast()
                while text.last == " " {
                    text.removeLast()
                }
            }
        case .clear:
            text = ""
        }
    }

    /// The typed arithmetic as a plain number (nil while it doesn't read as one, or when it carries a unit: the app
    /// reads those itself).
    public var value: Double? { HmmArithmetic.evaluate(text) }

    // MARK: Pieces of the text

    static let operators: Set<Character> = ["+", "-", "*", "/"]

    private mutating func pressOperator(_ key: Key) {
        guard let symbol = key.operatorCharacter else { return }
        guard let last = text.last else {
            // Only a minus can start: a negative number.
            if symbol == "-" { text = "-" }
            return
        }
        if Self.operators.contains(last) {
            // Another operator replaces the one just typed, except a minus after × or ÷ (`2*-3`).
            if symbol == "-", last == "*" || last == "/" {
                text.append("-")
                return
            }
            if text.count == 1 { return }
            text.removeLast()
            if let previous = text.last, Self.operators.contains(previous) { text.removeLast() }
        }
        if text.last == "." { text.removeLast() }
        text.append(symbol)
    }

    /// The digits and point since the last operator or space.
    private var trailingNumber: Substring {
        let start = text.lastIndex { Self.operators.contains($0) || $0 == " " }.map { text.index(after: $0) } ?? text.startIndex
        return text[start...]
    }

    private var endsWithUnit: Bool {
        guard let last = text.last else { return false }
        return !(last.isNumber || last == "." || Self.operators.contains(last) || last == " " || last == "(" || last == ")")
    }

    private mutating func removeTrailingUnit() {
        while let last = text.last, !(last.isNumber || last == "." || last == " " || Self.operators.contains(last)) {
            text.removeLast()
        }
        while text.last == " " {
            text.removeLast()
        }
    }
}

/// Plain arithmetic on typed numbers: + − × ÷ with the usual precedence and a leading or post-operator minus.
public enum HmmArithmetic {
    public static func evaluate(_ text: String) -> Double? {
        var parser = Parser(characters: Array(text.filter { $0 != " " }))
        guard !parser.characters.isEmpty, let result = parser.sum(), parser.position == parser.characters.count, result.isFinite else {
            return nil
        }
        return result
    }

    private struct Parser {
        let characters: [Character]
        var position = 0

        mutating func sum() -> Double? {
            guard var result = product() else { return nil }
            while position < characters.count, characters[position] == "+" || characters[position] == "-" {
                let symbol = characters[position]
                position += 1
                guard let rhs = product() else { return nil }
                result += symbol == "+" ? rhs : -rhs
            }
            return result
        }

        mutating func product() -> Double? {
            guard var result = factor() else { return nil }
            while position < characters.count, characters[position] == "*" || characters[position] == "/" {
                let symbol = characters[position]
                position += 1
                guard let rhs = factor() else { return nil }
                if symbol == "*" {
                    result *= rhs
                } else {
                    guard rhs != 0 else { return nil }
                    result /= rhs
                }
            }
            return result
        }

        mutating func factor() -> Double? {
            guard position < characters.count else { return nil }
            if characters[position] == "-" {
                position += 1
                return factor().map { -$0 }
            }
            if characters[position] == "(" {
                position += 1
                let inner = sum()
                guard position < characters.count, characters[position] == ")" else { return nil }
                position += 1
                return inner
            }
            let start = position
            while position < characters.count, characters[position].isNumber || characters[position] == "." || characters[position] == "," {
                position += 1
            }
            guard position > start else { return nil }
            return Double(String(characters[start ..< position]).replacingOccurrences(of: ",", with: "."))
        }
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
    import SwiftUI

    /// The number pad's keys and the line that shows what was typed. `commit` gets the typed text; an empty pad commits
    /// nothing. Tapping outside (the popover's edge) leaves the number as it was.
    public struct HmmNumberPad: View {
        private let title: String?
        private let placeholder: String
        private let units: [String]
        private let commit: (String) -> Void
        private let dismiss: () -> Void
        @State private var entry = HmmNumberPadEntry()
        @Environment(\.hmmTheme) private var theme

        public init(title: String? = nil, placeholder: String, units: [String] = [], commit: @escaping (String) -> Void,
                    dismiss: @escaping () -> Void) {
            self.title = title
            self.placeholder = placeholder
            self.units = units
            self.commit = commit
            self.dismiss = dismiss
        }

        private static let rows: [[HmmNumberPadEntry.Key]] = [
            [.digit(7), .digit(8), .digit(9), .divide],
            [.digit(4), .digit(5), .digit(6), .times],
            [.digit(1), .digit(2), .digit(3), .minus],
            [.point, .digit(0), .backspace, .plus]
        ]

        public var body: some View {
            VStack(spacing: HmmSpacing.xs) {
                if let title {
                    Text(LocalizedStringKey(title)).font(.hmm(.caption, weight: .semibold)).foregroundStyle(theme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(entry.isEmpty ? placeholder : entry.display)
                    .font(.hmmNumbers(.title3))
                    .foregroundStyle(entry.isEmpty ? theme.text3 : theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .trailing)
                    .padding(.horizontal, HmmSpacing.xs)
                    .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2))
                    .accessibilityIdentifier("number-pad-display")
                ForEach(Self.rows.indices, id: \.self) { row in
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(Self.rows[row], id: \.self) { key in keyButton(key) }
                    }
                }
                if !units.isEmpty {
                    HStack(spacing: HmmSpacing.xs) {
                        ForEach(units, id: \.self) { unit in keyButton(.unit(unit), height: 36) }
                    }
                }
                HStack(spacing: HmmSpacing.xs) {
                    keyButton(.clear)
                    Button {
                        HmmHaptics.play(.commit)
                        if !entry.isEmpty { commit(entry.text) }
                        dismiss()
                    } label: {
                        Text("Done").font(.hmm(.body, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: HmmTarget.minimum)
                            .foregroundStyle(theme.onAccent)
                            .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.accent))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("number-pad-done")
                }
            }
            .padding(HmmSpacing.s)
            .frame(width: 248)
        }

        private func keyButton(_ key: HmmNumberPadEntry.Key, height: Double = HmmTarget.minimum) -> some View {
            Button {
                HmmHaptics.play(.selection)
                entry.press(key)
            } label: {
                Text(verbatim: key.symbol)
                    .font(.hmmNumbers(.title3, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: height)
                    .foregroundStyle(theme.text)
                    .background(RoundedRectangle(cornerRadius: HmmRadius.control).fill(theme.surface2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: key.symbol))
            .accessibilityIdentifier("number-pad-\(Self.identifier(key))")
        }

        static func identifier(_ key: HmmNumberPadEntry.Key) -> String {
            switch key {
            case let .digit(value): String(value)
            case .point: "point"
            case .plus: "plus"
            case .minus: "minus"
            case .times: "times"
            case .divide: "divide"
            case let .unit(unit): unit
            case .backspace: "backspace"
            case .clear: "clear"
            }
        }
    }

    public extension View {
        /// Opens our number pad beside this view (a popover pointing at the number) while `isPresented`.
        func hmmNumberPad(isPresented: Binding<Bool>, title: String? = nil, placeholder: String, units: [String] = [],
                          commit: @escaping (String) -> Void) -> some View {
            popover(isPresented: isPresented) {
                HmmNumberPad(title: title, placeholder: placeholder, units: units, commit: commit) { isPresented.wrappedValue = false }
                    .presentationCompactAdaptation(.popover)
            }
        }
    }
#endif
