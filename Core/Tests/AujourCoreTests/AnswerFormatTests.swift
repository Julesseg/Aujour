import Foundation
import Testing

@testable import AujourCore

// The words an answered placeholder is written down as. The slot is spelled
// `{value}` rather than punctuation because a journal is markdown: most of what
// is worth testing here is that a pattern full of somebody's emphasis, braces
// and apostrophes comes out the other side as the sentence they wrote.

@Suite("Wording an answer")
struct AnswerFormatTests {
    private func filled(_ pattern: String, with answer: String = "4/5") -> String? {
        AnswerFormat(pattern)?.filled(with: answer)
    }

    @Test("the slot is where the answer goes")
    func theSlot() {
        #expect(filled("The mood for today was {value}") == "The mood for today was 4/5")
        #expect(filled("{value}") == "4/5")
        #expect(filled("Mood {value} — and better by noon") == "Mood 4/5 — and better by noon")
    }

    // A pattern that names the answer twice means it twice.
    @Test("every slot is filled")
    func everySlot() {
        #expect(
            filled("{value} in the morning, {value} by dark")
                == "4/5 in the morning, 4/5 by dark"
        )
    }

    // The whole reason the slot is a word in braces: a template writes bold
    // labels and italic words, and punctuation for a slot would have meant
    // guessing which asterisks were somebody's formatting.
    @Test("markdown in the pattern is left exactly as it was written")
    func markdownIsLeftAlone() {
        #expect(filled("**Mood:** {value}") == "**Mood:** 4/5")
        #expect(filled("*rough day* — {value}") == "*rough day* — 4/5")
        #expect(filled("A day I'd call {value}, on balance") == "A day I'd call 4/5, on balance")
    }

    // Spelled the way a placeholder's own name is read: spaces inside the
    // braces, and capitals that decide nothing.
    @Test("the slot is read the way a placeholder's name is")
    func theSlotIsSpelledLoosely() {
        #expect(filled("Woke up feeling { value }") == "Woke up feeling 4/5")
        #expect(filled("Woke up feeling {Value}") == "Woke up feeling 4/5")
        #expect(filled("Woke up feeling {VALUE}") == "Woke up feeling 4/5")
    }

    // Braces around anything else are braces: a template may hold them for
    // reasons of its own, and none of them is a slot.
    @Test("braces around anything else are not a slot")
    func otherBraces() {
        #expect(AnswerFormat("Woke up feeling {mood}") == nil)
        #expect(AnswerFormat("{}") == nil)
        #expect(AnswerFormat("{value") == nil)
        #expect(filled("{tag} {value}") == "{tag} 4/5")
    }

    @Test("a pattern with nowhere to put the answer is not a format")
    func noSlot() {
        #expect(AnswerFormat("Woke up feeling") == nil)
        #expect(AnswerFormat("") == nil)
        #expect(AnswerFormat("   ") == nil)
    }

    // For writing about a slot rather than filling one — the escape markdown
    // already has, which stays in the file and goes on being one.
    @Test("an escaped slot is left where it stands")
    func escapedSlots() {
        #expect(filled(#"\{value} is the slot — {value}"#) == #"\{value} is the slot — 4/5"#)
        #expect(AnswerFormat(#"Write \{value} to name it"#) == nil)
    }

    // The braces are not where anybody indents a line.
    @Test("the pattern is trimmed of its own whitespace")
    func trimming() {
        #expect(AnswerFormat("  Woke up feeling {value}  ")?.pattern == "Woke up feeling {value}")
        #expect(filled("  Woke up feeling {value}  ") == "Woke up feeling 4/5")
    }

    // An answer is whatever the widget handed over, and this puts it where the
    // slot is without opinion — a place name has spaces and punctuation in it.
    @Test("the answer goes in as it was handed over")
    func theAnswerIsVerbatim() {
        #expect(
            filled("Wrote this from {value}", with: "Café de Flore")
                == "Wrote this from Café de Flore"
        )
    }
}
