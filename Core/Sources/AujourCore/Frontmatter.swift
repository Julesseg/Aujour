import Foundation

/// The YAML block Obsidian keeps at the top of a note, read by Obsidian's
/// rule and no looser one (`CONTEXT.md`, *Frontmatter*).
///
/// Cut off the file before the body reaches the editor and joined back byte
/// for byte on save (ADR 0007): the text view holds the body, this holds the
/// block, and the file on disk does not know which side of the cut a line sat
/// on.
///
/// Understood as a whole or not at all. What is understood is the flat shape
/// Obsidian's Properties read — one value to a key, or a list under it — with
/// comments and blank lines left where they are. One line outside that shape
/// and ``properties`` is `nil`: the block is shown as the text it is, and
/// nothing here rewrites it. Nothing in a block is ever guessed at, because a
/// guess about where an unknown construct ends is how somebody else's vault
/// gets corrupted.
///
/// Every write is one Property's lines and no others. ``setting(_:to:)``,
/// ``adding(_:as:)``, ``renaming(_:to:)`` and ``deleting(_:)`` each replace a
/// range of lines in the block and leave the rest — order, quoting, blank
/// lines, comments, the other Properties' own spelling — byte for byte what
/// it was.
public struct Frontmatter: Hashable, Sendable {
    /// The block's own characters, opening fence to closing fence. The
    /// newline after the closing fence, where the file has one, is the
    /// ``Cut``'s to keep.
    public let source: String

    /// What the block says, in the order it says it — or `nil` for a block
    /// with one line outside the flat shape, which is a block Aujour does not
    /// understand and never rewrites.
    public let properties: [Property]?

    public var isUnderstood: Bool { properties != nil }

    /// Reads a block, fence to fence.
    public init(source: String) {
        self.source = source
        self.properties = Frontmatter.read(source.components(separatedBy: "\n"))
    }

    /// A block holding one Property and nothing else: what a day with no
    /// Frontmatter gets when its first Property is added.
    public static func holding(_ key: String, as value: Property.Value) -> Frontmatter {
        Frontmatter(
            source: (["---"] + YAMLScalar.lines(key: key, value: value.under(key), style: nil) + ["---"])
                .joined(separator: "\n")
        )
    }

    // MARK: - Cutting it off a file

    /// A file with its Frontmatter cut off the top.
    public struct Cut: Equatable, Sendable {
        public let frontmatter: Frontmatter

        /// The newline between the closing fence and the body, or nothing at
        /// all for a file that ends at the fence.
        public let separator: String

        /// Everything after the block: what the text view holds.
        public let body: String

        /// The file, byte for byte.
        public var joined: String { frontmatter.source + separator + body }

        /// How far into the file the body starts, counted the way a text
        /// view counts.
        public var blockLength: Int { (frontmatter.source + separator).utf16.count }
    }

    /// Cuts a file by Obsidian's rule: the very first line is `---`, a later
    /// line is `---` or `...`, and what lies between is the block. A `---`
    /// anywhere else, or a fence never closed, is body — `nil` here — and
    /// renders as the rule and the paragraphs it is.
    public static func cut(_ text: String) -> Cut? {
        let lines = text.components(separatedBy: "\n")
        guard lines.first == "---", lines.count > 1 else { return nil }
        guard let closing = lines.indices.dropFirst().first(where: { isAClosingFence(lines[$0]) })
        else { return nil }

        let source = lines[...closing].joined(separator: "\n")
        // A line after the fence, even an empty one, means a newline followed
        // it; a fence that is the last line of the file has none after it.
        let separator = closing < lines.count - 1 ? "\n" : ""
        let body = lines[(closing + 1)...].joined(separator: "\n")
        return Cut(frontmatter: Frontmatter(source: source), separator: separator, body: body)
    }

    private static func isAClosingFence(_ line: String) -> Bool {
        line == "---" || line == "..."
    }

    // MARK: - Writing one Property

    /// The block with this Property's value rewritten and every other line
    /// left as it was. A key the block does not have, or a block that is not
    /// understood, comes back unchanged.
    public func setting(_ key: String, to value: Property.Value) -> Frontmatter {
        guard let property = properties?.first(where: { $0.key == key }) else { return self }
        return replacing(
            property.lines,
            with: YAMLScalar.lines(key: key, value: value.under(key), style: property.style)
        )
    }

    /// The block with a Property added at the end, seeded with this value —
    /// or `nil` for a key that is not one line's worth of name, or one the
    /// block already has, or a block that is not understood.
    public func adding(_ key: String, as value: Property.Value) -> Frontmatter? {
        guard let properties, Property.isAKey(key),
            !properties.contains(where: { $0.key == key })
        else { return nil }
        let closing = source.components(separatedBy: "\n").count - 1
        return replacing(
            closing..<closing, with: YAMLScalar.lines(key: key, value: value.under(key), style: nil)
        )
    }

    /// The block with this Property under another name, its first line
    /// rewritten from the key to the colon and nothing after it — or `nil`
    /// for a name that is not a key or is already taken.
    public func renaming(_ key: String, to newKey: String) -> Frontmatter? {
        guard let properties, Property.isAKey(newKey) else { return nil }
        guard newKey != key else { return self }
        guard !properties.contains(where: { $0.key == newKey }) else { return nil }
        guard let property = properties.first(where: { $0.key == key }) else { return self }

        var lines = source.components(separatedBy: "\n")
        let line = lines[property.lines.lowerBound]
        guard let colon = line.firstIndex(of: ":") else { return nil }
        lines[property.lines.lowerBound] = newKey + line[colon...]
        return Frontmatter(source: lines.joined(separator: "\n"))
    }

    /// The block without this Property's lines — or `nil` when it was the
    /// last one, because a block with nothing to say goes, fences included.
    public func deleting(_ key: String) -> Frontmatter? {
        guard let properties, let property = properties.first(where: { $0.key == key }) else {
            return self
        }
        guard properties.count > 1 else { return nil }
        return replacing(property.lines, with: [])
    }

    private func replacing(_ lines: Range<Int>, with replacement: [String]) -> Frontmatter {
        var all = source.components(separatedBy: "\n")
        all.replaceSubrange(lines, with: replacement)
        return Frontmatter(source: all.joined(separator: "\n"))
    }

    // MARK: - Reading the flat shape

    /// The Properties in a block's lines, fences included, or `nil` at the
    /// first line outside the flat shape.
    private static func read(_ lines: [String]) -> [Property]? {
        guard lines.count >= 2, lines.first == "---", isAClosingFence(lines[lines.count - 1])
        else { return nil }

        var properties: [Property] = []
        var line = 1
        let closing = lines.count - 1
        while line < closing {
            let text = lines[line]
            if YAMLScalar.isBlankOrComment(text) {
                line += 1
                continue
            }
            // A line that is indented, or is an item, belongs under a key —
            // and there is none here to belong to.
            guard let first = text.first, !first.isWhitespace, !YAMLScalar.isAnItem(text),
                let (key, rest) = YAMLScalar.splitKey(text),
                !properties.contains(where: { $0.key == key })
            else { return nil }

            let byName = Property.listsByName.contains(key)
            if rest.isEmpty, line + 1 < closing, YAMLScalar.isAnItem(lines[line + 1]) {
                guard let (items, indent, next) = YAMLScalar.items(in: lines, from: line + 1, until: closing)
                else { return nil }
                properties.append(
                    Property(
                        key: key, value: .list(items), lines: line..<next,
                        style: .blockList(indent: indent)
                    )
                )
                line = next
                continue
            }

            guard let read = YAMLScalar.value(of: rest, asAList: byName) else { return nil }
            properties.append(
                Property(key: key, value: read.value, lines: line..<(line + 1), style: read.style)
            )
            line += 1
        }
        return properties
    }
}

extension Property.Value {
    /// This value as it is written under a key: itself, unless the key is a
    /// list by name, when it is the list it reads as — a list as it is, and
    /// anything else as the one item it says, or none for nothing.
    fileprivate func under(_ key: String) -> Property.Value {
        guard Property.listsByName.contains(key) else { return self }
        switch self {
        case .list: return self
        case .text(let text): return .list(text.isEmpty ? [] : [text])
        default: return .list([YAMLScalar.plain(self)])
        }
    }
}

// MARK: - The scalars, read and written

/// How one value is read off a line and written back onto one: the shapes
/// that decide a Property's kind, and the quoting that keeps text text.
enum YAMLScalar {
    // MARK: Reading

    static func isBlankOrComment(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        return trimmed.isEmpty || trimmed.first == "#"
    }

    /// `- item`, indented or not, or a `-` alone.
    static func isAnItem(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " })
        return trimmed == "-" || trimmed.hasPrefix("- ")
    }

    /// The key before the first `: ` (or a `:` ending the line), and what is
    /// after it — or `nil` for a line that is not `key: value`.
    static func splitKey(_ line: String) -> (key: String, rest: String)? {
        var index = line.startIndex
        while let colon = line[index...].firstIndex(of: ":") {
            let after = line.index(after: colon)
            if after == line.endIndex || line[after] == " " {
                let key = String(line[..<colon])
                guard Property.isAKey(key), !startsWithAnIndicator(key) else { return nil }
                return (key, line[after...].trimmingCharacters(in: .whitespaces))
            }
            index = after
        }
        return nil
    }

    /// The items of a list written one to a line under its key, their
    /// indent, and the line after the last of them.
    static func items(
        in lines: [String], from start: Int, until end: Int
    ) -> (items: [String], indent: String, next: Int)? {
        let indent = String(lines[start].prefix(while: { $0 == " " }))
        var items: [String] = []
        var line = start
        while line < end, isAnItem(lines[line]) {
            guard lines[line].hasPrefix(indent), !lines[line].dropFirst(indent.count).hasPrefix(" ")
            else { return nil }
            let text = lines[line].dropFirst(indent.count + 1).trimmingCharacters(in: .whitespaces)
            guard let item = string(of: text) else { return nil }
            items.append(item)
            line += 1
        }
        return (items, indent, line)
    }

    /// What a value written after `key: ` is, and how it was written — or
    /// `nil` for one outside the flat shape.
    static func value(
        of text: String, asAList: Bool
    ) -> (value: Property.Value, style: Property.WrittenStyle?)? {
        if text.hasPrefix("[") {
            guard let items = flowItems(of: text) else { return nil }
            return (.list(items), .flowList)
        }
        if asAList {
            guard let item = string(of: text) else { return nil }
            return (.list(item.isEmpty ? [] : [item]), nil)
        }
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            guard let quoted = unquoted(text) else { return nil }
            return (.text(quoted), nil)
        }
        guard isAPlainScalar(text) else { return nil }
        return plainValue(text)
    }

    /// A scalar as the text it is: quotes taken off, or the plain words.
    private static func string(of text: String) -> String? {
        if text.hasPrefix("\"") || text.hasPrefix("'") { return unquoted(text) }
        guard isAPlainScalar(text) else { return nil }
        return isNull(text) ? "" : text
    }

    private static func plainValue(_ text: String) -> (value: Property.Value, style: Property.WrittenStyle?) {
        if isNull(text) { return (.text(""), nil) }
        if let checkbox = bool(text) { return (.checkbox(checkbox), nil) }
        if isANumber(text), let number = Double(text) { return (.number(number), nil) }
        if let date = date(text) { return (date.value, date.spaced ? .dateTimeWithASpace : nil) }
        return (.text(text), nil)
    }

    private static func isNull(_ text: String) -> Bool {
        ["", "null", "Null", "NULL", "~"].contains(text)
    }

    private static func bool(_ text: String) -> Bool? {
        switch text {
        case "true", "True", "TRUE": true
        case "false", "False", "FALSE": false
        default: nil
        }
    }

    /// A decimal number as YAML's core schema reads one: digits, one dot,
    /// an optional exponent, an optional sign.
    static func isANumber(_ text: String) -> Bool {
        var rest = Substring(text)
        if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
        let whole = rest.prefix(while: \.isASCIIDigit)
        rest = rest.dropFirst(whole.count)
        var fraction: Substring = ""
        if rest.first == "." {
            fraction = rest.dropFirst().prefix(while: \.isASCIIDigit)
            rest = rest.dropFirst(1 + fraction.count)
        }
        guard !whole.isEmpty || !fraction.isEmpty else { return false }
        if rest.first == "e" || rest.first == "E" {
            rest = rest.dropFirst()
            if rest.first == "-" || rest.first == "+" { rest = rest.dropFirst() }
            let exponent = rest.prefix(while: \.isASCIIDigit)
            guard !exponent.isEmpty else { return false }
            rest = rest.dropFirst(exponent.count)
        }
        return rest.isEmpty
    }

    /// `2026-03-14`, or `2026-03-14T09:05` — Obsidian's two shapes — and
    /// `2026-03-14 09:05`, the same moment with a space where the `T` goes,
    /// which is how a hand writes it. Nothing looser: a time with seconds is
    /// text.
    private static func date(_ text: String) -> (value: Property.Value, spaced: Bool)? {
        let separator: Character = text.contains("T") ? "T" : " "
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count <= 2, let day = calendarDay(parts[0]) else { return nil }
        guard parts.count == 2 else {
            return (.date(year: day.year, month: day.month, day: day.day), false)
        }
        let clock = parts[1].split(separator: ":", omittingEmptySubsequences: false)
        guard clock.count == 2, clock[0].count == 2, clock[1].count == 2,
            let hour = digits(clock[0]), let minute = digits(clock[1]),
            (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return (
            .dateTime(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute),
            separator == " "
        )
    }

    private static func calendarDay(_ text: Substring) -> (year: Int, month: Int, day: Int)? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            let year = digits(parts[0]), let month = digits(parts[1]), let day = digits(parts[2]),
            (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return (year, month, day)
    }

    private static func digits(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy(\.isASCIIDigit) else { return nil }
        return Int(text)
    }

    /// Whether a value written bare is one plain scalar and nothing more
    /// clever: not a block scalar, an anchor, a tag, a flow mapping, a nested
    /// key, or a comment part-way along.
    private static func isAPlainScalar(_ text: String) -> Bool {
        guard let first = text.first else { return true }
        // A Placeholder token is text, whatever a brace means to YAML.
        if text.hasPrefix("{{") { return true }
        if startsWithAnIndicator(text) { return false }
        if first == "-" && (text.count == 1 || text.hasPrefix("- ")) { return false }
        if text.contains(" #") || text.contains("\t#") { return false }
        if text.contains(": ") || text.hasSuffix(":") { return false }
        return true
    }

    /// The characters YAML gives a meaning to at the start of a value, none
    /// of which begins anything in the flat shape.
    static func startsWithAnIndicator(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return "&*!|>%@`?,:[]{}\"'".contains(first)
    }

    /// The text inside a quoted scalar, or `nil` for one that does not close,
    /// runs on past its closing quote, or escapes something this reader does
    /// not know.
    static func unquoted(_ text: String) -> String? {
        guard let quote = text.first, text.count >= 2 else { return nil }
        let inner = text.dropFirst()
        var result = ""
        var index = inner.startIndex
        while index < inner.endIndex {
            let character = inner[index]
            let next = inner.index(after: index)
            switch (quote, character) {
            case ("'", "'"):
                // A doubled quote is one quote; a single one closes the text.
                if next < inner.endIndex, inner[next] == "'" {
                    result.append("'")
                    index = inner.index(after: next)
                    continue
                }
                return next == inner.endIndex ? result : nil
            case ("\"", "\""):
                return next == inner.endIndex ? result : nil
            case ("\"", "\\"):
                guard next < inner.endIndex else { return nil }
                switch inner[next] {
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "n": result.append("\n")
                case "t": result.append("\t")
                case "/": result.append("/")
                default: return nil
                }
                index = inner.index(after: next)
                continue
            default:
                result.append(character)
            }
            index = next
        }
        return nil
    }

    /// The items of `[a, b]`, quotes taken off — or `nil` for anything a flow
    /// sequence of scalars is not.
    private static func flowItems(of text: String) -> [String]? {
        guard text.hasSuffix("]"), text.count >= 2 else { return nil }
        let inner = text.dropFirst().dropLast()
        var items: [String] = []
        var item = ""
        var quote: Character?
        var previous: Character?
        for character in inner {
            if let open = quote {
                item.append(character)
                if character == open, previous != "\\" || open == "'" { quote = nil }
            } else if character == "," {
                items.append(item)
                item = ""
            } else {
                if (character == "\"" || character == "'"), item.allSatisfy({ $0 == " " }) {
                    quote = character
                }
                item.append(character)
            }
            previous = character
        }
        guard quote == nil else { return nil }
        items.append(item)

        var read: [String] = []
        for (index, raw) in items.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            // A comma after the last item is allowed; an empty item anywhere
            // else is not something this reader guesses at.
            if trimmed.isEmpty {
                guard index == items.count - 1 else { return nil }
                if index == 0 { return [] }
                continue
            }
            guard !trimmed.contains(where: { "[]{},".contains($0) }) || trimmed.hasPrefix("\"")
                || trimmed.hasPrefix("'"),
                let string = string(of: trimmed)
            else { return nil }
            read.append(string)
        }
        return read
    }

    // MARK: Writing

    /// The lines that say `key: value`, in whichever shape the value has —
    /// one line for a scalar or a flow list, and a line per item under the
    /// key for a block list.
    static func lines(key: String, value: Property.Value, style: Property.WrittenStyle?) -> [String] {
        switch value {
        case .list(let items):
            guard !items.isEmpty else { return ["\(key): []"] }
            switch style {
            case .flowList:
                return ["\(key): [" + items.map { quotedIfNeeded($0, inFlow: true) }.joined(separator: ", ") + "]"]
            case .blockList(let indent):
                return ["\(key):"] + items.map { indent + "- " + quotedIfNeeded($0, inFlow: false) }
            case .dateTimeWithASpace, nil:
                return ["\(key):"] + items.map { "  - " + quotedIfNeeded($0, inFlow: false) }
            }
        case .text(let text):
            return ["\(key): " + quotedIfNeeded(text, inFlow: false)]
        case .dateTime where style == .dateTimeWithASpace:
            return ["\(key): " + plain(value).replacingOccurrences(of: "T", with: " ")]
        default:
            return ["\(key): " + plain(value)]
        }
    }

    /// A value that is not text, written in its one shape: `true`, `7.5`,
    /// `2026-03-14T09:05` — the number with a dot whatever the locale, and
    /// the date and time with no zone.
    static func plain(_ value: Property.Value) -> String {
        switch value {
        case .text(let text): return text
        case .checkbox(let on): return on ? "true" : "false"
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 {
                return String(Int64(number))
            }
            return String(number)
        case .date(let year, let month, let day):
            return String(format: "%04d-%02d-%02d", year, month, day)
        case .dateTime(let year, let month, let day, let hour, let minute):
            return String(format: "%04d-%02d-%02dT%02d:%02d", year, month, day, hour, minute)
        case .list(let items): return "[" + items.joined(separator: ", ") + "]"
        }
    }

    /// Text unquoted when YAML reads it back as the same plain string, and
    /// double-quoted otherwise.
    static func quotedIfNeeded(_ text: String, inFlow: Bool) -> String {
        needsQuoting(text, inFlow: inFlow) ? quoted(text) : text
    }

    private static func needsQuoting(_ text: String, inFlow: Bool) -> Bool {
        guard let first = text.first, let last = text.last else { return true }
        if first.isWhitespace || last.isWhitespace { return true }
        if text.contains(where: \.isNewline) { return true }
        if text.hasPrefix("{{") { return true }
        if !isAPlainScalar(text) { return true }
        if inFlow, text.contains(where: { "[]{},".contains($0) }) { return true }
        if text.hasPrefix("#") { return true }
        // Read back, it would be a null, a checkbox, a number or a date.
        if isNull(text) || bool(text) != nil || isANumber(text) || date(text) != nil { return true }
        return false
    }

    private static func quoted(_ text: String) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\t": escaped.append("\\t")
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
