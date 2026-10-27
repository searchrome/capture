import Foundation

enum AgentAction {
    case click(Int, Int, String, Int)
    case typeText(String)
    case pressKey(String, [String])
    case scroll(Int, Int, Int)
    case takeScreenshot

    var pixel: CGPoint? {
        switch self {
        case .click(let x, let y, _, _), .scroll(let x, let y, _): return CGPoint(x: x, y: y)
        default: return nil
        }
    }

    func description(app: String?) -> String {
        switch self {
        case .click(let x, let y, let button, let count):
            let verb = count == 2 ? "Double-click" : button == "right" ? "Right-click" : "Click"
            return "\(verb) at (\(x), \(y))\(app.map { " on \($0)" } ?? "")"
        case .typeText(let text): return "Type “\(text)”"
        case .pressKey(let key, let modifiers):
            let symbols = ["cmd": "⌘", "shift": "⇧", "option": "⌥", "control": "⌃"]
            let keys = [
                "return": "↩", "tab": "⇥", "escape": "⎋", "delete": "⌫", "space": "Space",
                "up": "↑", "down": "↓",
                "left": "←", "right": "→",
            ]
            return "Press " + modifiers.map { symbols[$0] ?? $0 }.joined() + (keys[key] ?? key)
        case .scroll(_, _, let dy): return "Scroll \(dy < 0 ? "up" : "down") \(abs(dy))"
        case .takeScreenshot: return "Take screenshot"
        }
    }
}

enum AgentTools {
    static let keys = [
        "return", "tab", "escape", "delete", "space", "up", "down", "left", "right", "home", "end", "pageup",
        "pagedown",
    ]
    static let modifiers = ["cmd", "shift", "option", "control"]
    private static func schema(_ properties: [String: JSONValue], _ required: [String]) -> [String: JSONValue] {
        [
            "type": .string("object"), "properties": .object(properties),
            "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false),
        ]
    }
    private static func field(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }
    private static func choice(_ values: [String], _ description: String) -> JSONValue {
        .object([
            "type": .string("string"), "enum": .array(values.map { .string($0) }), "description": .string(description),
        ])
    }
    private static let coordinate = field(
        "integer", "Integer pixel coordinate in the most recent screenshot; its size is given in the accompanying text."
    )
    static let definitions: [ChatTool] = [
        ChatTool(
            function: .init(
                name: "click", description: "Click inside the selected area at x,y in the latest screenshot.",
                parameters: schema(
                    [
                        "x": coordinate, "y": coordinate,
                        "button": choice(["left", "right"], "Mouse button; default left."),
                        "count": .object([
                            "type": .string("integer"), "enum": .array([.number(1), .number(2)]),
                            "description": .string("Click count; default 1."),
                        ]),
                    ], ["x", "y"]))),
        ChatTool(
            function: .init(
                name: "type_text", description: "Type Unicode text into the focused field.",
                parameters: schema(["text": field("string", "Text to type.")], ["text"]))),
        ChatTool(
            function: .init(
                name: "press_key", description: "Press a key with optional modifiers.",
                parameters: schema(
                    [
                        "key": choice(keys, "Key to press."),
                        "modifiers": .object([
                            "type": .string("array"), "items": choice(modifiers, "Modifier key"),
                            "description": .string("Optional modifiers; default empty."),
                        ]),
                    ], ["key"]))),
        ChatTool(
            function: .init(
                name: "scroll",
                description: "Scroll at x,y in the latest screenshot; dy is in lines, negative means up.",
                parameters: schema(
                    ["x": coordinate, "y": coordinate, "dy": field("integer", "Number of lines; negative is up.")],
                    ["x", "y", "dy"]))),
        ChatTool(
            function: .init(
                name: "take_screenshot", description: "Recapture the selected screen region.",
                parameters: schema([:], []))),
    ]

    struct ArgumentError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func parse(_ call: ChatToolCall) throws -> AgentAction {
        func fail(_ message: String) -> ArgumentError { ArgumentError(message: "Invalid arguments: \(message)") }
        guard let data = call.function.arguments.data(using: .utf8),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object(let args) = value
        else { throw fail("expected a JSON object.") }
        func validate(_ allowed: Set<String>) throws {
            if !Set(args.keys).isSubset(of: allowed) { throw fail("unexpected parameter.") }
        }
        func int(_ key: String) throws -> Int {
            guard case .number(let n) = args[key], n.isFinite, n.rounded() == n, n >= Double(Int32.min),
                n <= Double(Int32.max)
            else { throw fail("\(key) must be an integer.") }
            return Int(n)
        }
        func string(_ key: String) throws -> String {
            guard case .string(let s) = args[key] else { throw fail("\(key) must be a string.") }
            return s
        }
        switch call.function.name {
        case "click":
            try validate(["x", "y", "button", "count"])
            let x = try int("x")
            let y = try int("y")
            let button = try args["button"].map { _ in try string("button") } ?? "left"
            let count = try args["count"].map { _ in try int("count") } ?? 1
            guard ["left", "right"].contains(button), [1, 2].contains(count) else {
                throw fail("button must be left or right and count must be 1 or 2.")
            }
            return .click(x, y, button, count)
        case "type_text":
            try validate(["text"])
            return .typeText(try string("text"))
        case "press_key":
            try validate(["key", "modifiers"])
            let key = try string("key")
            guard keys.contains(key) else { throw fail("unsupported key.") }
            var mods: [String] = []
            if let value = args["modifiers"] {
                guard case .array(let values) = value else { throw fail("modifiers must be an array.") }
                for value in values {
                    guard case .string(let mod) = value, modifiers.contains(mod), !mods.contains(mod) else {
                        throw fail("invalid modifier.")
                    }
                    mods.append(mod)
                }
            }
            return .pressKey(key, mods)
        case "scroll":
            try validate(["x", "y", "dy"])
            let x = try int("x")
            let y = try int("y")
            let dy = try int("dy")
            guard dy > Int(Int32.min) else { throw fail("dy is out of range.") }
            return .scroll(x, y, dy)
        case "take_screenshot":
            try validate([])
            return .takeScreenshot
        default: throw fail("unknown tool \(call.function.name).")
        }
    }
}
