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
    /// address, and `match` inverts `render` exactly over that range. A
    /// Journal Day outside it still renders — five digits, or a leading
    /// minus — but no such path reads back as an Entry. Nothing in the app
    /// produces one: days come from the calendar, which cannot reach there.
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
    ///
    /// The comparison is exact, case included. iOS volumes are usually
    /// case-insensitive, so a folder the user already had as `Journal/` holds
    /// the file a `[journal]/…` template addressed; deciding whether to fold
    /// case belongs to the layer that enumerates the Journal Root and knows
    /// the volume, not to this rule.
    public func match(_ relativePath: String) -> JournalDay? {
        guard relativePath.hasSuffix(Self.markdownExtension) else { return nil }
        let withoutExtension = relativePath.dropLast(Self.markdownExtension.count)
        return MomentFormat.match(withoutExtension, against: elements)
    }

    public var description: String { format }

    static let markdownExtension = ".md"
}
