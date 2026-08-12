import Foundation

/// Why a Moment-format string was refused as a Path Template.
///
/// Templates are typed by the user (or pasted over from Obsidian's
/// daily-notes settings), so every rejection carries a sentence that can be
/// shown as-is next to the text field.
public enum PathTemplateError: Error, Hashable, Sendable, CustomStringConvertible {
    /// The format string was empty or only whitespace.
    case emptyFormat

    /// A run of letters that is not one of the supported tokens.
    case unsupportedToken(String)

    /// A `[` with no closing `]`.
    case unterminatedLiteral

    /// An Entry template that leaves out part of the date, and so cannot
    /// name a single day. Carries the missing tokens in `YYYY`, `MM`, `DD`
    /// order.
    case missingDateTokens([String])

    /// A folder or file name that would render empty — a leading, trailing
    /// or doubled `/`.
    case emptyPathComponent

    /// A `.` or `..` folder name, which would point outside the shape the
    /// template describes (and, for `..`, outside the Journal Root).
    case relativePathComponent(String)

    /// The template spells out the `.md` extension that is appended anyway.
    case redundantMarkdownExtension

    public var description: String {
        switch self {
        case .emptyFormat:
            "A Path Template cannot be empty."
        case .unsupportedToken(let token):
            """
            '\(token)' is not a supported token. Aujour supports YYYY, MM and \
            DD; put any other text in [brackets].
            """
        case .unterminatedLiteral:
            "A '[' is missing its closing ']'."
        case .missingDateTokens(let tokens):
            """
            An Entry path has to name one day exactly, so it needs \
            \(tokens.joined(separator: ", ")) as well.
            """
        case .emptyPathComponent:
            """
            This template has an empty folder or file name — check for a \
            leading, trailing or doubled '/'.
            """
        case .relativePathComponent(let component):
            "'\(component)' is not a folder name a Path Template can use."
        case .redundantMarkdownExtension:
            "Leave '.md' off — Aujour appends it to every Entry path."
        }
    }

    public var localizedDescription: String { description }
}
