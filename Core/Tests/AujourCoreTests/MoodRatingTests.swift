import Foundation
import Testing

@testable import AujourCore

// What answering {{mood}} leaves in the file. The widget itself needs a screen
// and is the app's; the scale it offers and how a rating is spelled are decided
// here, because they are what the folder keeps — and a journal read in Obsidian
// next year is read as those words and nothing else.
//
// The sentence around the rating belongs to the token's format rather than to
// the rating (`InteractivePlaceholderTests`), so what is asserted here is the
// mark itself: the number, and the scale it was given on.

@Suite("A day's mood, on the scale its widget offers")
struct MoodRatingTests {
    // The scale travels with the number, wherever a format puts it: a bare `4`
    // in a journal is a number nothing records the scale of, and the line would
    // stop meaning anything the moment anybody wondered.
    @Test("a rating spells itself with the scale it was given on")
    func theMark() {
        #expect(MoodRating(1)?.answer == "1/5")
        #expect(MoodRating(4)?.answer == "4/5")
        #expect(MoodRating(5)?.answer == "5/5")
    }

    // Five of them, and nothing between or beyond: a mood is one of the marks
    // the widget puts up, so a rating that was never offered is not a rating.
    @Test("the scale is the five the widget offers, and nothing off it is a rating")
    func theScale() {
        #expect(MoodRating.all.map(\.value) == [1, 2, 3, 4, 5])
        #expect(MoodRating(0) == nil)
        #expect(MoodRating(6) == nil)
        #expect(MoodRating(-1) == nil)
    }

    // The whole of what answering does, end to end: the token's own characters
    // become the sentence its format words, and the day is plain markdown
    // before and after.
    @Test("answering the token writes the rating in its place")
    func answeringTheToken() throws {
        let entry = "{{mood}}\nWalked home.\n"
        let markdown = EntryMarkdown(entry)
        let token = try #require(markdown.interactivePlaceholders(in: entry).first)
        let rating = try #require(MoodRating(4))

        let edit = try #require(markdown.answering(token, in: entry, with: rating.answer))
        let answered = (entry as NSString).replacingCharacters(
            in: edit.range, with: edit.replacement
        )

        #expect(answered == "Today's mood: 4/5\nWalked home.\n")
        // And there is no question left in the day: nothing anywhere remembers
        // that this line was one, because the token was the whole record of it.
        #expect(EntryMarkdown(answered).interactivePlaceholders(in: answered).isEmpty)
    }

    // What a rating writes has no markdown syntax in it, so a day answered by
    // the widget reads in every other tool exactly as a day somebody typed the
    // same words into.
    @Test("the sentence a rating writes is words, not markdown")
    func theSentenceIsPlainWords() throws {
        for rating in MoodRating.all {
            let written = InteractivePlaceholder.mood.defaultFormat.filled(with: rating.answer)
            let markdown = EntryMarkdown(written)
            let line = try #require(markdown.lines.first)
            #expect(line.block == .paragraph, "\(written) was read as \(line.block)")
            #expect(line.inlines.isEmpty, "\(written) carries markdown of its own")
        }
    }
}
