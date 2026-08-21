/// Where the markdown a new Entry is spawned from comes from.
///
/// A seam rather than a path, because finding the file is not the domain's
/// business. The user points at it with the system's file picker and it may be
/// anywhere they keep their writing — inside the Journal Root beside their
/// entries, in a `Templates` folder elsewhere in their Obsidian vault, in
/// iCloud Drive, or on a drive plugged into the iPad — and reaching any of
/// those means bookmarks and security scopes, which belong to the App layer
/// (ADR 0005). What crosses here is markdown, or nothing.
///
/// Asked every time a day is spawned, deliberately: the template is a file the
/// user edits in whatever app they like, and Aujour keeps no copy of it. What
/// they changed this morning is what tomorrow starts from.
public protocol ContentTemplateSource: Sendable {
    /// The template's markdown as it reads right now, or `nil` where there is
    /// no template or it cannot be read.
    ///
    /// Unreadable is `nil` and never an error. The file is the user's, in
    /// their own folder: they may have renamed it, moved it, or not yet had it
    /// down from iCloud. Both answers mean the same thing here — a blank page,
    /// which is what a day started as before they set a template at all — and
    /// a day that refused to open because of it would be a day they cannot
    /// write in.
    func markdown() async -> String?
}

/// A Content Template that is simply this markdown.
///
/// For previews and tests, and for anything that has the template in hand
/// already: the file is the App layer's to find, and everything below that is
/// only ever the text it found.
public struct FixedContentTemplate: ContentTemplateSource {
    public let text: String

    public init(_ text: String) {
        self.text = text
    }

    public func markdown() async -> String? { text }
}
