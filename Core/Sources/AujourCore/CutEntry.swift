import Foundation

/// An Entry as the screen holds it: the Frontmatter cut off the top for its
/// own section, the body under it for the text view, and the one text the
/// two join back into (ADR 0007).
///
/// The text is the truth and this is a reading of it. Whatever the screen
/// does — a keystroke in the body, a toggle in the section, a line typed into
/// the source — comes through here as a change to one half, and leaves
/// ``content`` as the whole file for the Entry Editor to save. Text arriving
/// the other way, from the folder, is read afresh (``contentArrived(_:)``).
///
/// Two things here are not readings of the text, and are why this is a value
/// with a memory rather than a function of the content:
///
/// - **A block typed by hand is held while the caret is in it.** Fences and a
///   Property written at the top of a day that had none are a Frontmatter by
///   the rule, but lifting them into the section the moment the closing fence
///   is typed would take the words from under the caret. So the lift waits
///   for the caret to leave, or the keyboard to go down (``caret(at:)``) —
///   the rule every Drawn Element keeps.
/// - **The source is edited as typed.** While the block's own characters are
///   in a field, they are not read until the field is left: a fence deleted
///   part-way through an edit is not yet a Frontmatter that has gone.
///   ``showProperties()`` is where the reading happens, and it honours what
///   it finds — Properties, the source still, or no block at all.
public struct CutEntry: Equatable, Sendable {
    /// The block, or `nil` for a day with none. Stale while the source is
    /// being typed into, when ``source`` is what the screen shows.
    public private(set) var frontmatter: Frontmatter?

    /// What the text view holds: everything after the block.
    public private(set) var body: String

    /// The whole Entry, block and body joined byte for byte — what the Entry
    /// Editor is handed after every change here.
    public private(set) var content: String

    /// Whether the section is showing the block's own characters rather than
    /// its Properties. Always true of a block that is not understood, which
    /// has no Properties to show.
    public private(set) var isShowingSource: Bool

    /// The newline between the closing fence and the body, kept so that a
    /// file ending at its fence is written back ending at its fence.
    private var separator: String

    /// The block as it is being typed into the source field, or `nil` while
    /// the Properties are showing.
    private var sourceDraft: String?

    /// Reads a day's text by Obsidian's rule. A day always opens on its
    /// Properties, and a block that is not understood opens on its source.
    public init(_ content: String) {
        self.content = content
        frontmatter = nil
        separator = ""
        body = content
        isShowingSource = false
        if let cut = Frontmatter.cut(content) { take(cut) }
    }

    /// Shows a file cut by the rule: the block in the section, the body in
    /// the text view — on the Properties, unless there are none to show.
    private mutating func take(_ cut: Frontmatter.Cut) {
        frontmatter = cut.frontmatter
        separator = cut.separator
        body = cut.body
        isShowingSource = !cut.frontmatter.isUnderstood
    }

    /// The Properties the section shows: none for a day without a block, and
    /// none for a block that is not understood.
    public var properties: [Property] { frontmatter?.properties ?? [] }

    /// Whether the section can be switched to the source and back: only a
    /// block that is understood has Properties to come back to.
    public var offersSource: Bool { frontmatter?.isUnderstood == true }

    /// The block's own characters, fence to fence — as typed, while the
    /// source field is up.
    public var source: String { sourceDraft ?? frontmatter?.source ?? "" }

    // MARK: - Text from elsewhere

    /// Reads text that reached the Entry from outside — a day being opened,
    /// or its file having moved on underneath it. The text this produced
    /// itself is left alone, which is what keeps a block being typed by hand
    /// held where it is.
    public mutating func contentArrived(_ text: String) {
        guard text != content else { return }
        self = CutEntry(text)
    }

    // MARK: - The body

    /// What the text view holds now.
    public mutating func typed(_ body: String) {
        self.body = body
        join()
    }

    /// Where the caret is in the body, as a text view counts, or `nil` while
    /// nobody is writing in it — which is when a block typed by hand is
    /// lifted into the section.
    ///
    /// Held while the caret is anywhere up to the start of the line after
    /// the closing fence, which is where the return that finished the fence
    /// leaves it. Past that, or gone, and the block is lifted.
    ///
    /// - Parameter pasted: whether the caret got here by a paste rather than
    ///   a keystroke. A paste that left the caret right after the block
    ///   lifts at once: nobody is typing there, and the words were never
    ///   under the caret to vanish from.
    public mutating func caret(at caret: Int?, afterAPaste pasted: Bool = false) {
        guard frontmatter == nil, let cut = Frontmatter.cut(body) else { return }
        if let caret, pasted ? caret < cut.blockLength : caret <= cut.blockLength { return }
        take(cut)
    }

    /// How far a caret moves when the text under it changes only at its
    /// top: a block lifted off the body takes its characters with it, and
    /// one dropped back into the body puts them in front of everything.
    /// Either way the caret stays on the character it was on. Nought for
    /// any other change, which has no such character to stay on — and for
    /// a text that was empty on either side, which has no character at all.
    ///
    /// Counted the way a text view counts.
    public static func caretShift(from old: String, to new: String) -> Int {
        let before = old.utf16
        let after = new.utf16
        guard !before.isEmpty, !after.isEmpty else { return 0 }
        let difference = after.count - before.count
        if difference < 0, before.dropFirst(-difference).elementsEqual(after) { return difference }
        if difference > 0, after.dropFirst(difference).elementsEqual(before) { return difference }
        return 0
    }

    // MARK: - The Properties

    /// Rewrites one Property's lines and nothing else.
    public mutating func set(_ key: String, to value: Property.Value) {
        guard let frontmatter else { return }
        self.frontmatter = frontmatter.setting(key, to: value)
        join()
    }

    /// Adds a Property at the end of the block — or makes the block, for a
    /// day that had none. `false`, and nothing written, for a key that is
    /// not one line's worth of name or is already taken.
    @discardableResult
    public mutating func add(_ key: String, as value: Property.Value) -> Bool {
        if let frontmatter {
            guard let added = frontmatter.adding(key, as: value) else { return false }
            self.frontmatter = added
        } else {
            guard Property.isAKey(key) else { return false }
            frontmatter = Frontmatter.holding(key, as: value)
            separator = "\n"
        }
        join()
        return true
    }

    /// Gives a Property another name. `false`, and nothing written, for a
    /// name that is not a key or is already taken.
    @discardableResult
    public mutating func rename(_ key: String, to newKey: String) -> Bool {
        guard let frontmatter, let renamed = frontmatter.renaming(key, to: newKey) else {
            return false
        }
        self.frontmatter = renamed
        join()
        return true
    }

    /// Takes a Property's lines out — and the block with them, fences
    /// included, when it was the last.
    public mutating func delete(_ key: String) {
        guard let frontmatter else { return }
        if let remaining = frontmatter.deleting(key) {
            self.frontmatter = remaining
        } else {
            self.frontmatter = nil
            separator = ""
        }
        join()
        // What is left at the top of the body is read by the rule like
        // anything else: a `---` that stood right under the block is a fence
        // now, if a later line closes it.
        caret(at: nil)
    }

    // MARK: - The source

    /// Shows the block's own characters, for a day that has a block.
    public mutating func showSource() {
        guard let frontmatter else { return }
        isShowingSource = true
        sourceDraft = frontmatter.source
    }

    /// What the source field holds now. Joined to the body as typed, and not
    /// read until the field is left.
    public mutating func typedSource(_ text: String) {
        guard isShowingSource else { return }
        sourceDraft = text
        join()
    }

    /// Leaves the source, reading what it says by the rule and honouring what
    /// it finds: Properties again, the source still because the block is not
    /// understood, or no Frontmatter at all because a fence went — in which
    /// case its lines are body now.
    public mutating func showProperties() {
        self = CutEntry(content)
    }

    private mutating func join() {
        content = (sourceDraft ?? frontmatter?.source ?? "") + separator + body
    }
}
