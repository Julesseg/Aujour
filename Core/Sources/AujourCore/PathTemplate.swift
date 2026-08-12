import Foundation

/// The rule mapping a Journal Day to an Entry's file path, relative to the
/// Journal Root — and back again.
///
/// The format is a restricted Moment string (see `MomentFormat`): slashes
/// create subfolders, `[bracketed]` text is literal, and `.md` is appended
/// automatically. An Obsidian daily-notes format inside the subset can be
/// pasted over verbatim and produce the same files Obsidian would.
public struct PathTemplate: Hashable, Sendable, CustomStringConvertible {
    /// The format string exactly as the user wrote it.
    public let format: String

    private let elements: [MomentFormat.Element]

    public init(_ format: String) throws(PathTemplateError) {
        // Ahead of parsing, because `.md` is four letters the tokenizer would
        // otherwise reject one at a time — and "'m' is not a supported token"
        // is no help to someone who simply typed the extension out.
        guard !format.lowercased().hasSuffix(Self.markdownExtension) else {
            throw PathTemplateError.redundantMarkdownExtension
        }

        let elements = try MomentFormat.parse(format)
        try MomentFormat.validatePathShape(elements)

        // Without all three fields the template would render the same path
        // for many days, and reading a path back could not name one — Entry
        // identity would stop being a function of the date.
        let missing = MomentFormat.Field.allCases.filter { !elements.contains(.field($0)) }
        guard missing.isEmpty else {
            throw PathTemplateError.missingDateTokens(missing.map(\.rawValue))
        }

        // The same extension, this time spelled with brackets: `[.md]` parses
        // as a literal, so only the rendering gives it away.
        let rendering = MomentFormat.render(elements, for: MomentFormat.shapeSample)
        guard !rendering.lowercased().hasSuffix(Self.markdownExtension) else {
            throw PathTemplateError.redundantMarkdownExtension
        }

        self.elements = elements
        self.format = format
    }

    /// `YYYY/MM/YYYY-MM-DD` — a year folder, a month folder, and an
    /// ISO-8601-dated file.
    public static let `default` = try! PathTemplate("YYYY/MM/YYYY-MM-DD")

    /// The path an Entry for this Journal Day belongs at, relative to the
    /// Journal Root.
    ///
    /// `YYYY` is four digits, so years 0 through 9999 are what a path can
    /// address — the range a calendar the user navigates can reach many times
    /// over.
    public func render(_ journalDay: JournalDay) -> String {
        MomentFormat.render(elements, for: journalDay) + Self.markdownExtension
    }

    /// The Journal Day whose Entry lives at `relativePath`, or `nil` if no day
    /// does — which is exactly the question "is this file an Entry?"
    ///
    /// A file is an Entry when, and only when, its path relative to the
    /// Journal Root is what this template renders for some day (ADR 0002).
    /// Everything else in the vault — other notes, Parked Files, attachments,
    /// files left behind by a declined migration — answers `nil`.
    public func match(_ relativePath: String) -> JournalDay? {
        guard relativePath.hasSuffix(Self.markdownExtension) else { return nil }
        let withoutExtension = relativePath.dropLast(Self.markdownExtension.count)
        return MomentFormat.match(withoutExtension, against: elements)
    }

    public var description: String { format }

    static let markdownExtension = ".md"
}

// Coded as the bare format string, and re-validated on the way in: the
// template travels through iCloud key-value storage (ADR 0003), so a value
// written by a hand or an older build is refused rather than quietly
// deciding which files count as Entries.
extension PathTemplate: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let format = try container.decode(String.self)
        do {
            try self.init(format)
        } catch {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\(error)")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(format)
    }
}
