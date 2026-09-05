import Foundation
import Testing

@testable import AujourCore

// The Entry as the screen holds it: the Frontmatter in its section, the body
// in the text view, and the one text they join back into.

@Suite("Opening a day")
struct CutEntryOpeningTests {
    @Test("a day with a Frontmatter opens on its Properties, with the body below")
    func opens() {
        let cut = CutEntry("---\nmood: 7\n---\n# Title\n")
        #expect(cut.properties.map(\.key) == ["mood"])
        #expect(cut.body == "# Title\n")
        #expect(cut.content == "---\nmood: 7\n---\n# Title\n")
        #expect(!cut.isShowingSource)
        #expect(cut.offersSource)
    }

    @Test("a block that is not understood opens on its source, with no other way offered")
    func notUnderstood() {
        let cut = CutEntry("---\nnested:\n  a: 1\n---\nbody")
        #expect(cut.isShowingSource)
        #expect(!cut.offersSource)
        #expect(cut.source == "---\nnested:\n  a: 1\n---")
        #expect(cut.body == "body")
    }

    @Test("a day with no Frontmatter is all body")
    func none() {
        let cut = CutEntry("# Title\n---\nnot a frontmatter\n---\n")
        #expect(cut.frontmatter == nil)
        #expect(cut.body == "# Title\n---\nnot a frontmatter\n---\n")
        #expect(cut.properties.isEmpty)
    }

    @Test("text arriving from outside is read afresh; the same text is left alone")
    func arriving() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.showSource()
        cut.contentArrived("---\nmood: 7\n---\nbody")
        #expect(cut.isShowingSource, "the same text is not a reason to leave the source")

        cut.contentArrived("---\nmood: 8\n---\nanother body")
        #expect(!cut.isShowingSource)
        #expect(cut.properties.first?.value == .number(8))
        #expect(cut.body == "another body")
    }
}

@Suite("Typing in the body")
struct CutEntryTypingTests {
    @Test("what is typed joins the block byte for byte")
    func typed() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.typed("body, and more")
        #expect(cut.content == "---\nmood: 7\n---\nbody, and more")
        #expect(cut.properties.map(\.key) == ["mood"])
    }

    @Test("a --- on the body's first line under a Frontmatter is a rule, and stays put")
    func ruleUnderTheBlock() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.typed("---\nbody\n---\n")
        cut.caret(at: nil)
        #expect(cut.body == "---\nbody\n---\n")
        #expect(cut.properties.map(\.key) == ["mood"])
        #expect(cut.content == "---\nmood: 7\n---\n---\nbody\n---\n")
    }

    @Test("fences typed by hand are held while the caret is in them, and lift once it has left")
    func lift() {
        var cut = CutEntry("Hello")
        cut.typed("---\nmood: 7\n---\nHello")
        cut.caret(at: 3)
        #expect(cut.frontmatter == nil, "the caret is still in the block")
        #expect(cut.content == "---\nmood: 7\n---\nHello")

        // On the line after the closing fence, where the return just put it.
        cut.caret(at: 16)
        #expect(cut.frontmatter == nil, "the caret has only just left the fence")

        cut.caret(at: 17)
        #expect(cut.properties.map(\.value) == [.number(7)])
        #expect(cut.body == "Hello")
        #expect(cut.content == "---\nmood: 7\n---\nHello")
    }

    @Test("the keyboard going down lifts them too")
    func keyboardDown() {
        var cut = CutEntry("")
        cut.typed("---\nmood: 7\n---\n")
        cut.caret(at: 16)
        #expect(cut.frontmatter == nil)
        cut.caret(at: nil)
        #expect(cut.properties.map(\.key) == ["mood"])
        #expect(cut.body == "")
    }

    @Test("a paste with the caret after the block lifts at once")
    func paste() {
        var cut = CutEntry("")
        cut.typed("---\nmood: 7\n---\nHello there")
        cut.caret(at: 27)
        #expect(cut.properties.map(\.key) == ["mood"])
        #expect(cut.body == "Hello there")
    }

    @Test("a paste of the block alone lifts too, where a return typed after the fence would be held")
    func pasteOfTheBlockAlone() {
        var typed = CutEntry("")
        typed.typed("---\nmood: 7\n---\n")
        typed.caret(at: 16)
        #expect(typed.frontmatter == nil)

        var pasted = CutEntry("")
        pasted.typed("---\nmood: 7\n---\n")
        pasted.caret(at: 16, afterAPaste: true)
        #expect(pasted.properties.map(\.key) == ["mood"])
        #expect(pasted.body == "")

        // Part-way through a pasted block is still in it.
        var inside = CutEntry("")
        inside.typed("---\nmood: 7\n---\nHello")
        inside.caret(at: 10, afterAPaste: true)
        #expect(inside.frontmatter == nil)
    }

    @Test("a fence never closed is never lifted")
    func unclosed() {
        var cut = CutEntry("")
        cut.typed("---\nmood: 7\n")
        cut.caret(at: nil)
        #expect(cut.frontmatter == nil)
        #expect(cut.body == "---\nmood: 7\n")
    }

    @Test("a hand-typed block that is not understood lifts into the source")
    func liftsNotUnderstood() {
        var cut = CutEntry("")
        cut.typed("---\nnested:\n  a: 1\n---\nHello")
        cut.caret(at: nil)
        #expect(cut.frontmatter != nil)
        #expect(cut.isShowingSource)
        #expect(!cut.offersSource)
        #expect(cut.body == "Hello")
    }
}

@Suite("Editing the Properties")
struct CutEntryPropertyTests {
    @Test("a control's write rewrites the Property's line and reaches the content")
    func set() {
        var cut = CutEntry("---\nmood: 7\ndone: false\n---\nbody")
        cut.set("done", to: .checkbox(true))
        #expect(cut.content == "---\nmood: 7\ndone: true\n---\nbody")
        #expect(cut.body == "body")
        #expect(cut.properties.map(\.value) == [.number(7), .checkbox(true)])
    }

    @Test("adding to a day with none makes the block above the body")
    func first() {
        var cut = CutEntry("body")
        let added = cut.add("mood", as: .number(7))
        #expect(added)
        #expect(cut.content == "---\nmood: 7\n---\nbody")
        #expect(cut.body == "body")
        #expect(cut.properties.map(\.key) == ["mood"])
    }

    @Test("adding to an empty day leaves a newline after the fence, and nothing else")
    func firstOnAnEmptyDay() {
        var cut = CutEntry("")
        let added = cut.add("mood", as: .number(7))
        #expect(added)
        #expect(cut.content == "---\nmood: 7\n---\n")
    }

    @Test("a key the block has is refused, and nothing changes")
    func refused() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        let taken = cut.add("mood", as: .number(1))
        let colon = cut.add("a: b", as: .number(1))
        let renamed = cut.rename("mood", to: "a:b")
        #expect(!taken)
        #expect(!colon)
        #expect(!renamed)
        #expect(cut.content == "---\nmood: 7\n---\nbody")
    }

    @Test("renaming and deleting are the same discipline over a whole line")
    func renameAndDelete() {
        var cut = CutEntry("---\nmood: 7\ntags: [a]\n---\nbody")
        let renamed = cut.rename("mood", to: "feeling")
        #expect(renamed)
        #expect(cut.content == "---\nfeeling: 7\ntags: [a]\n---\nbody")
        cut.delete("tags")
        #expect(cut.content == "---\nfeeling: 7\n---\nbody")
    }

    @Test("the block goes with its last Property, fences included")
    func last() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.delete("mood")
        #expect(cut.frontmatter == nil)
        #expect(cut.content == "body")
        #expect(cut.body == "body")
    }

    @Test("nothing rewrites a block that is not understood")
    func notUnderstood() {
        var cut = CutEntry("---\nnested:\n  a: 1\n---\nbody")
        cut.set("nested", to: .number(1))
        let added = cut.add("x", as: .number(1))
        #expect(!added)
        cut.delete("nested")
        #expect(cut.content == "---\nnested:\n  a: 1\n---\nbody")
    }
}

@Suite("The source")
struct CutEntrySourceTests {
    @Test("the source is the block's own characters, fence to fence, and edits reach the content")
    func roundTrip() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.showSource()
        #expect(cut.isShowingSource)
        #expect(cut.source == "---\nmood: 7\n---")

        cut.typedSource("---\nmood: 8\ndone: true\n---")
        #expect(cut.content == "---\nmood: 8\ndone: true\n---\nbody")

        cut.showProperties()
        #expect(!cut.isShowingSource)
        #expect(cut.properties.map(\.value) == [.number(8), .checkbox(true)])
        #expect(cut.body == "body")
    }

    @Test("leaving the source with a fence gone drops the lines into the body")
    func fenceGone() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.showSource()
        cut.typedSource("---\nmood: 7")
        cut.showProperties()
        #expect(cut.frontmatter == nil)
        #expect(cut.body == "---\nmood: 7\nbody")
        #expect(cut.content == "---\nmood: 7\nbody")
    }

    @Test("leaving the source with a block that is not understood stays on the source")
    func stillSource() {
        var cut = CutEntry("---\nmood: 7\n---\nbody")
        cut.showSource()
        cut.typedSource("---\nnested:\n  a: 1\n---")
        cut.showProperties()
        #expect(cut.isShowingSource)
        #expect(!cut.offersSource)
        #expect(cut.source == "---\nnested:\n  a: 1\n---")
    }

    @Test("a day with no Frontmatter has no source to show")
    func none() {
        var cut = CutEntry("body")
        cut.showSource()
        #expect(!cut.isShowingSource)
        #expect(cut.source == "")
    }
}

// Where the caret lands when the text under it changes only at its top: a
// block lifted off the body, or one dropped back into it.
@Suite("The caret when the top of the text changes")
struct CaretShiftTests {
    @Test("a block lifted off the top moves the caret back by its length")
    func lifted() {
        #expect(CutEntry.caretShift(from: "---\nmood: 7\n---\nHello", to: "Hello") == -16)
    }

    @Test("lines dropped onto the top move the caret on by their length")
    func dropped() {
        #expect(CutEntry.caretShift(from: "Hello", to: "---\nmood: 7\nHello") == 12)
    }

    @Test("counted the way a text view counts, not in characters")
    func utf16() {
        #expect(CutEntry.caretShift(from: "🎉\nHello", to: "Hello") == -3)
    }

    @Test("any other change leaves the caret where it was")
    func elsewhere() {
        #expect(CutEntry.caretShift(from: "Hello there", to: "Hello") == 0)
        #expect(CutEntry.caretShift(from: "Hello", to: "Goodbye") == 0)
        #expect(CutEntry.caretShift(from: "Hello", to: "Hello") == 0)
        #expect(CutEntry.caretShift(from: "", to: "Hello") == 0)
        #expect(CutEntry.caretShift(from: "Hello", to: "") == 0)
    }
}
