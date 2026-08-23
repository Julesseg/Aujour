import Foundation
import Testing

@testable import AujourCore

// What answering {{mood}} leaves in the file. The widget itself needs a screen
// and is the app's; the scale it offers and the sentence a rating becomes are
// decided here, because they are what the folder keeps — and a journal read in
// Obsidian next year is read as that sentence and nothing else.

@Suite("A day's mood, on the scale its widget offers")
struct MoodRatingTests {
    @Test("a rating words itself as the line the file keeps")
    func theSentence() {
        #expect(MoodRating(1)?.answer == "Today's mood: 1/5")
        #expect(MoodRating(4)?.answer == "Today's mood: 4/5")
        #expect(MoodRating(5)?.answer == "Today's mood: 5/5")
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
    // become the sentence, and the day is plain markdown before and after.
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

    // A rating is a sentence, not a mark: what it writes has no markdown syntax
    // in it, so a day answered by the widget reads in every other tool exactly
    // as a day somebody typed the same words into.
    @Test("the sentence a rating writes is words, not markdown")
    func theSentenceIsPlainWords() throws {
        for rating in MoodRating.all {
            let markdown = EntryMarkdown(rating.answer)
            let line = try #require(markdown.lines.first)
            #expect(line.block == .paragraph, "\(rating.answer) was read as \(line.block)")
            #expect(line.inlines.isEmpty, "\(rating.answer) carries markdown of its own")
        }
    }
}
