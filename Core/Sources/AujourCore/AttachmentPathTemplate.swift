import Foundation

/// The rule mapping a Journal Day to the folder its Attachments live in,
/// relative to the Journal Root.
///
/// The same restricted Moment engine as `PathTemplate`, minus the two things
/// that only make sense for a file: the `.md` extension, and the demand that
/// the path name a day. A folder may name no day at all (`[attachments]`,
/// everything in one place), and nothing needs to read a date back out of
/// one — an Attachment is identified by the Entry that references it, not by
/// where it sits.
public struct AttachmentPathTemplate: Hashable, Sendable, CustomStringConvertible {
    /// The format string exactly as the user wrote it.
    public let format: String

    private let elements: [MomentFormat.Element]

    public init(_ format: String) throws(PathTemplateError) {
        let elements = try MomentFormat.parse(format)
        try MomentFormat.validatePathShape(elements)

        self.elements = elements
        self.format = format
    }

    /// `[attachments]/YYYY/MM` — a fixed folder, split by year and month so a
    /// long-running journal's photos stay browsable in Files and Obsidian.
    public static let `default` = try! AttachmentPathTemplate("[attachments]/YYYY/MM")

    /// The folder this day's Attachments belong in, relative to the Journal
    /// Root. No trailing slash.
    public func render(_ journalDay: JournalDay) -> String {
        MomentFormat.render(elements, for: journalDay)
    }

    public var description: String { format }
}
