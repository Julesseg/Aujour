import Foundation

/// A day on its way out of Aujour: which day it is, what it says, and what
/// the file it leaves as is called.
///
/// Sending a day is two things and not one. A **PDF** is the day as it looks
/// — the markdown drawn as what it means, which is a page somebody can read
/// or print without knowing what a hash at the front of a line is for. Plain
/// **text** is the day as it *is*: the file's own characters, which is what
/// somebody wants when the day is going into another journal, another
/// editor, or the middle of a message.
///
/// Neither is a new document. The text form is the Entry byte for byte
/// (ADR 0001), and the PDF is a drawing of exactly those characters — nothing
/// here rewrites a journal on the way past.
///
/// What a page *looks like* is not decided here, because it cannot be: a page
/// needs fonts, and Core has none. This is the half of exporting that is
/// arithmetic on a day and a string — which day, what it says, what the file
/// is called, and whether there is anything to send at all — and it is
/// unit-tested where that arithmetic is, rather than against a rendered page.
public struct EntryExport: Equatable, Sendable {
    /// The two things a day can be sent as.
    public enum Form: Hashable, Sendable {
        /// The Entry drawn as what it means: headings large, emphasis
        /// slanted, marks left out — a page to read rather than markdown to
        /// edit.
        case pdf

        /// The Entry's own characters, exactly as the file holds them.
        case plainText

        /// What the file is called by.
        ///
        /// `md` rather than `txt` for the text form, deliberately. An Entry
        /// *is* markdown, and what leaves Aujour as plain text should be a
        /// file that could go straight back into a vault — opened by
        /// Obsidian, read as a document by anything that renders markdown,
        /// and still nothing but text everywhere else.
        public var fileExtension: String {
            switch self {
            case .pdf: "pdf"
            case .plainText: "md"
            }
        }
    }

    /// The Journal Day being sent.
    public let day: JournalDay

    /// What the Entry says — and, verbatim, the text form of it.
    ///
    /// The editor's own text rather than the file's, so that a day being
    /// written in shares the words on screen: the last second of typing has
    /// not reached the folder yet, and a share sheet is a strange place to
    /// discover that.
    public let markdown: String

    public init(_ day: JournalDay, markdown: String) {
        self.day = day
        self.markdown = markdown
    }

    /// Whether there is anything here worth sending.
    ///
    /// A day nobody has written in yet is an empty page and an empty file,
    /// and offering to send one is offering nothing. The offer is simply not
    /// made — the same answer the photo suggestions panel gives a day the
    /// camera missed.
    public var hasWords: Bool {
        !markdown.allSatisfy(\.isWhitespace)
    }

    /// What the exported file is called: the Journal Day, then the form's own
    /// extension — `2026-03-14.pdf`, `2026-03-14.md`.
    ///
    /// Named after the day for the reason an Attachment is: a folder somebody
    /// exported a month into sorts the way the journal does, and a name that
    /// is a date is one they can find again.
    public func fileName(as form: Form) -> String {
        "\(day).\(form.fileExtension)"
    }

    /// What the document is called where a name is read rather than sorted —
    /// the PDF's own title, and the words above the share sheet.
    ///
    /// With the year, always. An exported day is read away from the app that
    /// knows which week it is, and every February has a 14th.
    public func title(in timeZone: TimeZone = .current, locale: Locale = .current) -> String {
        day.spelledOut(withYear: true, in: timeZone, locale: locale)
    }
}
