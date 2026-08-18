import Foundation
import Testing

@testable import AujourCore

// What the accessory row's controls do to an Entry. Every one of them is a
// rewrite of the markdown the user could have typed by hand, so every test
// here is written as the Entry before and the Entry after — with the cursor
// drawn into both, because where the caret is left is half of what a
// formatting control does.

@Suite("Formatting an entry from the accessory row")
struct MarkdownFormattingTests {

    // MARK: - Bold and italic

    @Test("the word the caret is standing in is the word that is wrapped")
    func wrappingTheWordAtTheCaret() {
        #expect(formatted(.strong, "Walked to the mar|ket.") == "Walked to the **mar|ket**.")
        #expect(formatted(.emphasis, "Walked to the mar|ket.") == "Walked to the *mar|ket*.")
        // The end of a word is in it: a caret there is somebody who has just
        // finished typing the word they mean.
        #expect(formatted(.strong, "Walked to the market|.") == "Walked to the **market|**.")
    }

    @Test("the selected words are wrapped, and are still the selected words")
    func wrappingASelection() {
        #expect(
            formatted(.strong, "Walked to |the market| today.")
                == "Walked to **|the market|** today."
        )
    }

    // `**the market **` is not bold in any markdown renderer — a closing mark
    // with a space in front of it closes nothing — so the spaces a selection
    // happened to take in stay outside the marks.
    @Test("the spaces at the edges of a selection stay outside the marks")
    func wrappingTrimsWhitespace() {
        #expect(
            formatted(.strong, "Walked to |the market |today.")
                == "Walked to **|the market|** today."
        )
    }

    @Test("with no word to wrap, the marks are put down for what comes next")
    func wrappingNothing() {
        #expect(formatted(.strong, "Walked to |") == "Walked to **|**")
        #expect(formatted(.emphasis, "Walked to | today.") == "Walked to *|* today.")
    }

    @Test("pressing it again inside what it wrapped takes the marks away")
    func unwrapping() {
        #expect(formatted(.strong, "Walked to **the |market**.") == "Walked to the |market.")
        #expect(formatted(.emphasis, "Walked to *the |market*.") == "Walked to the |market.")
    }

    @Test("selecting the marks along with the words takes them away too")
    func unwrappingAWholeSelectedSpan() {
        #expect(formatted(.strong, "|**milk**|") == "|milk|")
    }

    // Bold inside italic is one span inside another, and the button acts on
    // the one it is about: the italic is still there afterwards.
    @Test("bold inside italic-and-bold leaves the italic behind")
    func unwrappingTheInnerSpan() {
        #expect(formatted(.strong, "***bo|th***") == "*bo|th*")
        #expect(formatted(.emphasis, "***bo|th***") == "**bo|th**")
    }

    // What the button means at the end of a bold word is "stop being bold",
    // which is a caret that steps over the closing marks — not a bold word
    // undone, and certainly not a second pair of marks against the first.
    @Test("at the end of what it wrapped, it steps out rather than undoing it")
    func steppingOutOfASpan() {
        #expect(formatted(.strong, "Walked to **the market|**.") == "Walked to **the market**|.")
        #expect(formatted(.strong, "Walked to **the market**|.") == nil)
    }

    // A span is read one line at a time (`EntryMarkdown`), so marks around a
    // line break would be marks around nothing.
    @Test("emphasis does not cross a line, so a selection that does stops at the first")
    func wrappingAcrossLines() {
        #expect(
            formatted(.strong, "|Walked to the market\nand back|.")
                == "**|Walked to the market|**\nand back."
        )
    }

    // MARK: - Headings

    @Test("a line becomes a heading, and pressing the same level again takes it back")
    func headings() {
        #expect(formatted(.heading(level: 1), "Wal|ked to the market") == "# Wal|ked to the market")
        #expect(formatted(.heading(level: 1), "# Wal|ked to the market") == "Wal|ked to the market")
    }

    @Test("a heading at another level is re-levelled rather than removed")
    func changingHeadingLevel() {
        #expect(formatted(.heading(level: 3), "# Sun|day") == "### Sun|day")
        #expect(formatted(.heading(level: 1), "### Sun|day") == "# Sun|day")
    }

    // MARK: - Lists

    @Test("every line the selection touches becomes a list item")
    func makingAList() {
        #expect(formatted(.bulletList, "|milk\nbread\neggs|") == "- |milk\n- bread\n- eggs|")
        #expect(formatted(.taskList, "|milk\nbread|") == "- [ ] |milk\n- [ ] bread|")
    }

    @Test("pressing it again takes the markers away")
    func unmakingAList() {
        #expect(formatted(.bulletList, "- |milk\n- bread|") == "|milk\nbread|")
        #expect(formatted(.taskList, "- [x] mi|lk") == "mi|lk")
    }

    // Three states rather than two, and the reason is the one thing a box
    // cannot do: it is drawn over characters rather than being a view, so a
    // finger on the glass is the only thing that can tick one on the page.
    // Round the cycle, a Task can be made, ticked and unmade by somebody who
    // never touches it.
    @Test("the checkbox goes round: a task, a task that is done, and neither")
    func tickingFromTheRow() {
        #expect(formatted(.taskList, "mi|lk") == "- [ ] mi|lk")
        #expect(formatted(.taskList, "- [ ] mi|lk") == "- [x] mi|lk")
        #expect(formatted(.taskList, "- [x] mi|lk") == "mi|lk")
        // A selection of tasks that are not all in the same state is a
        // selection somebody is making into tasks.
        #expect(
            formatted(.taskList, "|- [x] milk\n- [ ] bread|") == "|- [ ] milk\n- [ ] bread|"
        )
    }

    // The numbers are what the user reads — the editor draws an Entry's own
    // characters — so a list that starts under `3.` starts at 4.
    @Test("a numbered list counts, and carries on from the line above it")
    func numbering() {
        #expect(formatted(.numberedList, "|milk\nbread|") == "1. |milk\n2. bread|")
        #expect(formatted(.numberedList, "3. milk\n|bread|") == "3. milk\n4. |bread|")
    }

    // One line, one shape: the marker a line has is the one it gives up. A
    // quote's `> ` goes the same way a heading's hashes do — it is the mark
    // that made the line what it was, and the line is something else now.
    @Test("a line can only be one thing, so the marker it had gives way")
    func replacingAMarker() {
        #expect(formatted(.heading(level: 2), "- [ ] mi|lk") == "## mi|lk")
        #expect(formatted(.taskList, "1. mi|lk") == "- [ ] mi|lk")
        #expect(formatted(.bulletList, "# Sun|day") == "- Sun|day")
        #expect(formatted(.bulletList, "> mi|lk") == "- mi|lk")
    }

    // The commonest press of all: a list is started on the empty line the
    // return key just made, before there is anything to put in it. So a line
    // with nothing on it takes the marker like any other, and the same control
    // takes it away again.
    @Test("a line with nothing on it takes the marker too")
    func emptyLines() {
        #expect(formatted(.taskList, "milk\n|") == "milk\n- [ ] |")
        #expect(formatted(.taskList, "milk\n- [ ] |") == "milk\n- [x] |")
        #expect(formatted(.heading(level: 2), "|") == "## |")
        // And the room the next line is going to be typed in is made before
        // there is anything in it.
        #expect(formatted(.indent, "- milk\n|") == "- milk\n  |")
        #expect(formatted(.bulletList, "|milk\n\nbread|") == "- |milk\n- \n- bread|")
    }

    // Dragging down to the start of the next paragraph is a selection of the
    // one above it: the highlight the user can see stops there, and so does
    // the control.
    @Test("a selection that ends where a line begins does not reach that line")
    func selectingUpToALineStart() {
        #expect(formatted(.bulletList, "|milk\n|bread") == "- |milk\n|bread")
    }

    // A rule is nothing but its own characters. There are no words behind
    // `---` for a marker to introduce, so they are what the control keeps.
    @Test("a rule keeps its own characters")
    func thematicBreaks() {
        #expect(formatted(.bulletList, "-|--") == "- -|--")
    }

    // MARK: - Indenting

    @Test("indenting puts one level in front of the line, and outdenting takes it back")
    func indenting() {
        #expect(formatted(.indent, "- mi|lk") == "  - mi|lk")
        #expect(formatted(.outdent, "  - mi|lk") == "- mi|lk")
        #expect(formatted(.outdent, "- mi|lk") == nil)
    }

    // A vault written in Obsidian is indented with tabs, and a line that has
    // been indented one way is not indented the other way next to it.
    @Test("a line indented with tabs is indented with another tab")
    func indentingWithTabs() {
        #expect(formatted(.indent, "\t- mi|lk") == "\t\t- mi|lk")
        #expect(formatted(.outdent, "\t\t- mi|lk") == "\t- mi|lk")
    }

    // Markdown nests a list item under the column its parent's words start in:
    // two spaces under a `- `, three under a `1. `. A step of the wrong width
    // is the next item along rather than a nested one, which is what the user
    // would see in Obsidian.
    @Test("a step in is as wide as the marker on the line above it")
    func indentingUnderAList() {
        #expect(formatted(.indent, "1. milk\n|bread") == "1. milk\n   |bread")
        #expect(formatted(.outdent, "1. milk\n   |bread") == "1. milk\n|bread")
        // A task's box is not part of the step: `- [ ] milk` is a bullet whose
        // words happen to begin with a box.
        #expect(formatted(.indent, "- [ ] milk\n|bread") == "- [ ] milk\n  |bread")
    }

    // The cursor stays with the characters it was against — the whole of both
    // lines is still what is selected, and the room made in front of them is
    // not part of what the user had hold of.
    @Test("indenting reaches every line the selection touches")
    func indentingASelection() {
        #expect(formatted(.indent, "|- milk\n\n- bread|") == "  |- milk\n  \n  - bread|")
    }

    // MARK: - What a control leaves behind

    // The one thing every control here has in common: it rewrites markdown a
    // user could have typed, and the Entry is a plain markdown file before and
    // after (ADR 0001). So what comes out reads back as the shape it claims.
    @Test("what a control writes reads back as the shape it made")
    func whatIsWrittenReadsBack() {
        let commands: [(MarkdownFormatting, MarkdownBlock)] = [
            (.heading(level: 2), .heading(level: 2)),
            (.bulletList, .bulletItem),
            (.numberedList, .numberedItem(number: 1)),
            (.taskList, .taskItem(isDone: false)),
        ]
        for (command, block) in commands {
            let (source, selection) = cursor(in: "mi|lk")
            let edit = try! #require(command.edit(source, over: selection))
            let after = rewritten(source, by: edit)
            #expect(EntryMarkdown(after).lines.first?.block == block, "\(after)")
        }

        let (source, selection) = cursor(in: "mi|lk")
        let bold = try! #require(MarkdownFormatting.strong.edit(source, over: selection))
        let line = try! #require(EntryMarkdown(rewritten(source, by: bold)).lines.first)
        #expect(line.inlines.map(\.style) == [.strong])
    }

    @Test("a control with nothing to do says so rather than rewriting anything")
    func nothingToDo() {
        #expect(MarkdownFormatting.outdent.edit("milk", over: NSRange(location: 0, length: 0)) == nil)
        // Past the end of the Entry, which is where a stale selection points
        // after the file moved on underneath the editor.
        #expect(
            MarkdownFormatting.bulletList.edit("milk", over: NSRange(location: 400, length: 0))
                != nil
        )
    }

    // MARK: - Saying where the cursor is

    /// An Entry with the cursor written into it: `|` is the caret, and two of
    /// them are the ends of a selection.
    ///
    /// The markers are not text — they are taken out before anything reads the
    /// markdown, and put back into the answer — which is what lets a test say
    /// what a control did to the words *and* to the caret in one line.
    private func cursor(in marked: String) -> (source: String, selection: NSRange) {
        let parts = marked.components(separatedBy: "|")
        let source = parts.joined()
        return (
            source,
            NSRange(
                location: (parts[0] as NSString).length,
                length: parts.count > 2 ? (parts[1] as NSString).length : 0
            )
        )
    }

    /// The Entry `marked` describes, with `command` applied to it and the
    /// cursor drawn back in where the control left it — or `nil` where the
    /// control had nothing to do.
    private func formatted(_ command: MarkdownFormatting, _ marked: String) -> String? {
        let (source, selection) = cursor(in: marked)
        guard let edit = command.edit(source, over: selection) else { return nil }

        let after = NSMutableString(string: rewritten(source, by: edit))
        let cursor = edit.selection ?? selection
        if cursor.length > 0 { after.insert("|", at: cursor.upperBound) }
        after.insert("|", at: cursor.location)
        return after as String
    }

    private func rewritten(_ source: String, by edit: MarkdownEdit) -> String {
        let text = NSMutableString(string: source)
        text.replaceCharacters(in: edit.range, with: edit.replacement)
        return text as String
    }
}
