import Foundation

/// The rule mapping a Journal Day to a folder, relative to the Journal Root.
///
/// The Attachment Path Template is one of these: attachments go under the
/// folder it renders for the Entry's day, and are referenced relatively from
/// the Entry. It is the same restricted Moment engine as `PathTemplate`,
/// minus the two things that only make sense for a file — the `.md`
/// extension, and the demand that the path name one day. A folder template
/// may name no day at all (`[attachments]`, everything in one place), and
/// nothing ever needs to read a date back out of it: an attachment is
/// identified by the Entry that references it, not by where it sits.
public struct FolderPathTemplate: Hashable, Sendable, CustomStringConvertible {
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
    public static let attachmentDefault = try! FolderPathTemplate("[attachments]/YYYY/MM")

    /// The folder this day's attachments belong in, relative to the Journal
    /// Root. No trailing slash.
    public func render(_ journalDay: JournalDay) -> String {
        MomentFormat.render(elements, for: journalDay)
    }

    public var description: String { format }
}

// Coded as the bare format string and re-validated on the way in, for the
// same reason as `PathTemplate`: it is a synced setting (ADR 0003).
extension FolderPathTemplate: Codable {
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
