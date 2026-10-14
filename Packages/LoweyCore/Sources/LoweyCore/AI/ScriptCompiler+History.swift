import Foundation

// MARK: - The editable history (H1)

/// `{"do": "model", "target": "Block", "op": "steps"}` lists a shape's modelling steps and their numbers in the reply;
/// `{"op": "step", "step": 1, "number": "diameter", "value": 0.008}` changes one (metres) and replays the steps after it.
extension ScriptState {
    mutating func modelSteps(_ id: ObjectID, _: JSONValue) throws {
        guard let object = scene.objects[id], let history = object.modelHistory else {
            report.append("\(scene.objects[id]?.name ?? "It") has no modelling steps yet")
            return
        }
        let fixed = history.earlier.count
        for (index, step) in (history.earlier + history.steps).enumerated() {
            let numbers = step.numbers.map { "\($0.name.rawValue) \(Self.short($0.value))" }.joined(separator: ", ")
            report.append("\(index + 1). \(step.name)\(numbers.isEmpty ? "" : " (\(numbers))")\(index < fixed ? " — fixed" : "")")
        }
        if let lock = ModelingOperations.historyLock(of: object) { report.append(lock.description) }
    }

    mutating func modelStep(_ id: ObjectID, _ action: JSONValue) throws {
        guard let history = scene.objects[id]?.modelHistory else { throw fail("this has no modelling steps") }
        guard let position = number(action, "step").map({ Int($0) - 1 }), let value = number(action, "value") else {
            throw fail("step needs “step” (1 is the first, as \"op\": \"steps\" lists them) and “value” (metres)")
        }
        let index = position - history.earlier.count
        guard history.steps.indices.contains(index) else {
            throw fail(position >= 0 && position < history.earlier.count ? ModelingOperations.HistoryFailure.fixed.description : "no such step")
        }
        let numbers = history.steps[index].numbers
        let chosen: Int? = if let name = string(action, "number") {
            numbers.firstIndex { $0.name.rawValue == name }
        } else {
            number(action, "number").map { Int($0) - 1 } ?? (numbers.isEmpty ? nil : 0)
        }
        guard let chosen, numbers.indices.contains(chosen) else {
            throw fail("“number” is one of \(numbers.map(\.name.rawValue).joined(separator: ", "))")
        }
        do {
            let command = try ModelingOperations.changeStep(id, step: index, number: chosen, to: value, in: scene) { "\(Self.short($0)) m" }
            try run(command, label: "Step \(position + 1): \(numbers[chosen].name.rawValue) \(Self.short(value)) m")
        } catch let failure as ModelingOperations.HistoryFailure {
            throw fail(failure.description)
        }
    }
}
