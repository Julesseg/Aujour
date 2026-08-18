import Foundation
import Testing

@testable import AujourCore

// The return key inside a list. Written as the Entry before and the Entry
// after, with the caret drawn into both — where the caret is left is most of
// what this is for, since the next thing that happens is always the user
// typing into the item it just opened.

@Suite("Carrying a list on to the next line")
struct MarkdownReturnTests {

    @Test("a return at the end of an item opens the next one")
    func openingTheNextItem() {
        #expect(returning("- milk|") == "- milk\n- |")
        #expect(returning("* milk|") == "* milk\n* |")
        #expect(returning("- [x] milk|") == "- [x] milk\n- [ ] |")
    }

    // The numbers are what the user reads — this editor draws an Entry's own
    // characters — so the item after 3 is 4, spelled the way they spelled it.
    @Test("a numbered item opens the next number")
    func numbering() {
        #expect(returning("3. milk|") == "3. milk\n4. |")
        #expect(returning("9) milk|") == "9) milk\n10) |")
    }

    @Test("a nested item opens another at the same depth")
    func nesting() {
        #expect(returning("  - milk|") == "  - milk\n  - |")
        #expect(returning("\t- [ ] milk|") == "\t- [ ] milk\n\t- [ ] |")
    }

    // The way out, and the only one that does not mean deleting characters the
    // editor put there: a return on the item nobody typed into ends the list.
    @Test("a return on an item nobody typed into ends the list")
    func endingTheList() {
        #expect(returning("- milk\n- |") == "- milk\n|")
        #expect(returning("- [ ] |") == "|")
        #expect(returning("  - |") == "|")
    }

    // A return in the middle of an item is the user splitting it, and what
    // moves down is the rest of their words — under a marker, because it is
    // still a line of the list.
    @Test("a return inside an item takes the rest of it to the next one")
    func splittingAnItem() {
        #expect(returning("- milk and| bread") == "- milk and\n- | bread")
    }

    @Test("a return anywhere but in a list is just a return")
    func everywhereElse() {
        #expect(returning("Walked to the market.|") == nil)
        #expect(returning("# Sun|day") == nil)
        #expect(returning("> quoted|") == nil)
        #expect(returning("|") == nil)
        // Inside the marker, where the caret is among the characters that make
        // the line a list item rather than among its words.
        #expect(returning("-| milk") == nil)
        #expect(returning("- [|x] milk") == nil)
    }

    // MARK: - Saying where the cursor is

    /// An Entry with the caret written into it as `|`, returned with the
    /// return key's edit made and the caret drawn back in where it was left —
    /// or `nil` where a return is just a return.
    private func returning(_ marked: String) -> String? {
        let parts = marked.components(separatedBy: "|")
        let source = parts.joined()
        let caret = NSRange(location: (parts[0] as NSString).length, length: 0)

        guard let edit = MarkdownReturn.edit(source, over: caret) else { return nil }
        let after = NSMutableString(string: source)
        after.replaceCharacters(in: edit.range, with: edit.replacement)
        after.insert("|", at: (edit.selection ?? caret).location)
        return after as String
    }
}
