import Foundation
import Testing

@testable import AujourCore

// The block at the top of a file, read by Obsidian's rule and no looser one,
// and rewritten a Property at a time with the rest of it left byte for byte.

// MARK: - Cutting the block off the file

@Suite("Cutting the Frontmatter off a file")
struct FrontmatterCutTests {
    @Test("a file opening with --- and closing with --- is a Frontmatter and a body")
    func cut() throws {
        let cut = try #require(Frontmatter.cut("---\nmood: 7\n---\n# Title\n"))
        #expect(cut.frontmatter.source == "---\nmood: 7\n---")
        #expect(cut.separator == "\n")
        #expect(cut.body == "# Title\n")
    }

    @Test("... closes a block as well as ---")
    func dots() throws {
        let cut = try #require(Frontmatter.cut("---\nmood: 7\n...\nbody"))
        #expect(cut.frontmatter.source == "---\nmood: 7\n...")
        #expect(cut.body == "body")
    }

    @Test("the join is the file, byte for byte, whether or not a newline follows the fence")
    func join() {
        for text in [
            "---\nmood: 7\n---\n# Title\n", "---\nmood: 7\n---", "---\nmood: 7\n---\n",
            "---\nmood: 7\n---\n\nblank line first", "---\n---\n", "---\n---",
        ] {
            let cut = Frontmatter.cut(text)
            #expect(cut != nil, "\(text.debugDescription) was not read as a Frontmatter")
            #expect(cut?.joined == text)
        }
    }

    @Test("a fence anywhere but the very first line is body")
    func notFirst() {
        #expect(Frontmatter.cut("\n---\nmood: 7\n---\n") == nil)
        #expect(Frontmatter.cut("# Title\n---\nmood: 7\n---\n") == nil)
        #expect(Frontmatter.cut(" ---\nmood: 7\n---\n") == nil)
    }

    @Test("a fence never closed is body")
    func unclosed() {
        #expect(Frontmatter.cut("---\nmood: 7\n") == nil)
        #expect(Frontmatter.cut("---") == nil)
        #expect(Frontmatter.cut("---\n") == nil)
    }

    @Test("a fence line is exactly three dashes, nothing looser")
    func exactFences() {
        #expect(Frontmatter.cut("--- \nmood: 7\n---\n") == nil)
        #expect(Frontmatter.cut("----\nmood: 7\n---\n") == nil)
        #expect(Frontmatter.cut("---\nmood: 7\n--- \n---\n")?.frontmatter.source == "---\nmood: 7\n--- \n---")
    }

    @Test("an empty pair of fences is a block with nothing in it")
    func empty() throws {
        let cut = try #require(Frontmatter.cut("---\n---\nbody"))
        #expect(cut.frontmatter.properties?.isEmpty == true)
        #expect(cut.body == "body")
    }

    @Test("the block's length is measured the way a text view counts")
    func length() throws {
        let cut = try #require(Frontmatter.cut("---\ntitle: café 🎉\n---\nbody"))
        #expect(cut.blockLength == ("---\ntitle: café 🎉\n---\n" as NSString).length)
    }
}

// MARK: - Reading the Properties

@Suite("Reading a Frontmatter's Properties")
struct FrontmatterReadingTests {
    private func properties(_ block: String) -> [Property]? {
        Frontmatter(source: block).properties
    }

    @Test("a kind is the shape of the value")
    func kinds() throws {
        let read = try #require(
            properties(
                """
                ---
                title: A walk
                mood: 7
                weight: 71.5
                done: false
                created: 2026-03-14
                at: 2026-03-14T09:05
                tags: [walk, market]
                ---
                """
            )
        )
        #expect(
            read.map(\.value) == [
                .text("A walk"), .number(7), .number(71.5), .checkbox(false),
                .date(year: 2026, month: 3, day: 14),
                .dateTime(year: 2026, month: 3, day: 14, hour: 9, minute: 5),
                .list(["walk", "market"]),
            ]
        )
        #expect(read.map(\.key) == ["title", "mood", "weight", "done", "created", "at", "tags"])
    }

    @Test("a list under its key, one item to a line")
    func blockList() throws {
        let read = try #require(
            properties("---\ntags:\n  - walk\n  - market\nmood: 7\n---")
        )
        #expect(read.map(\.value) == [.list(["walk", "market"]), .number(7)])
        #expect(read[0].lines == 1..<4)
        #expect(read[1].lines == 4..<5)
    }

    @Test("tags, aliases and cssclasses are lists by name, whatever they hold")
    func listsByName() throws {
        let read = try #require(
            properties("---\ntags: walk\naliases:\ncssclasses: []\n---")
        )
        #expect(read.map(\.value) == [.list(["walk"]), .list([]), .list([])])
    }

    @Test("quoted text is text, whatever it looks like")
    func quoted() throws {
        let read = try #require(
            properties(
                """
                ---
                a: "7"
                b: 'true'
                c: "2026-03-14"
                d: "say \\"hi\\" and \\\\ back"
                e: 'it''s'
                f: ""
                ---
                """
            )
        )
        #expect(
            read.map(\.value) == [
                .text("7"), .text("true"), .text("2026-03-14"), .text("say \"hi\" and \\ back"),
                .text("it's"), .text(""),
            ]
        )
    }

    @Test("an empty value, or a null, is empty text")
    func emptyValues() throws {
        let read = try #require(properties("---\na:\nb: null\nc: ~\nd:   \n---"))
        #expect(read.map(\.value) == [.text(""), .text(""), .text(""), .text("")])
    }

    @Test("a Placeholder token left in a value is text")
    func placeholder() throws {
        let read = try #require(properties("---\nmood: {{mood}}\n---"))
        #expect(read.map(\.value) == [.text("{{mood}}")])
    }

    @Test("what is not quite a date or a number is text")
    func almost() throws {
        let read = try #require(
            properties("---\na: 2026-13-14\nb: 2026-03-14T25:00\nc: 7pm\nd: 1,5\ne: 2026-03-14  09:05\nf: 2026-03-14T09:05:30\n---")
        )
        #expect(
            read.map(\.value) == [
                .text("2026-13-14"), .text("2026-03-14T25:00"), .text("7pm"), .text("1,5"),
                .text("2026-03-14  09:05"), .text("2026-03-14T09:05:30"),
            ]
        )
    }

    @Test("a date and time with a space where the T goes is the same moment, and keeps its space")
    func spacedDateTime() throws {
        let block = Frontmatter(source: "---\nat: 2026-03-14 09:05\nlater: 2026-03-14T09:05\n---")
        let read = try #require(block.properties)
        let moment = Property.Value.dateTime(year: 2026, month: 3, day: 14, hour: 9, minute: 5)
        #expect(read.map(\.value) == [moment, moment])

        let written = block
            .setting("at", to: .dateTime(year: 2026, month: 9, day: 5, hour: 10, minute: 48))
            .setting("later", to: .dateTime(year: 2026, month: 9, day: 5, hour: 10, minute: 48))
        #expect(written.source == "---\nat: 2026-09-05 10:48\nlater: 2026-09-05T10:48\n---")
        #expect(block.adding("new", as: moment)?.source.hasSuffix("new: 2026-03-14T09:05\n---") == true)
    }

    @Test("a Placeholder standing alone in a value is the token, and its answer is the bare value")
    func placeholderInAValue() throws {
        let alone = try #require(Property.Value.text("{{location}}").placeholder)
        #expect(alone.placeholder == .location)
        #expect(Property.answer(alone, with: "The market") == "The market")

        let worded = try #require(Property.Value.text("{{mood:{value} out of 5}}").placeholder)
        #expect(Property.answer(worded, with: "4") == "4 out of 5")

        #expect(Property.Value.text("{{location}} today").placeholder == nil)
        #expect(Property.Value.text("{{nothing}}").placeholder == nil)
        #expect(Property.Value.number(7).placeholder == nil)
    }

    @Test("comments and blank lines are kept, and are nobody's Property")
    func commentsAndBlanks() throws {
        let read = try #require(
            properties("---\n# the day\n\nmood: 7\n\n# tags\ntags:\n- walk\n\n---")
        )
        #expect(read.map(\.key) == ["mood", "tags"])
        #expect(read[0].lines == 3..<4)
        #expect(read[1].lines == 6..<8)
    }

    @Test("each Property keeps the lines it stands on")
    func lineRanges() throws {
        let read = try #require(properties("---\na: 1\nb: [x]\nc:\n- y\n- z\nd: 4\n---"))
        #expect(read.map(\.lines) == [1..<2, 2..<3, 3..<6, 6..<7])
    }

    @Test("a key may have spaces in it, and a value may hold a colon")
    func looseKeysAndColons() throws {
        let read = try #require(properties("---\nmy key: a\nurl: https://example.com\n---"))
        #expect(read.map(\.key) == ["my key", "url"])
        #expect(read.map(\.value) == [.text("a"), .text("https://example.com")])
    }

    @Test("one line outside the flat shape makes the block not understood")
    func notUnderstood() {
        for block in [
            "---\nnested:\n  child: 1\n---",
            "---\ntext: |\n  two\n  lines\n---",
            "---\ntext: >\n  folded\n---",
            "---\n- item\n---",
            "---\nmood: 7 # inline comment\n---",
            "---\na: {b: 1}\n---",
            "---\na: [b, [c]]\n---",
            "---\nno colon here\n---",
            "---\n  indented: 1\n---",
            "---\na: &anchor 1\n---",
            "---\na: *alias\n---",
            "---\na: !!str 1\n---",
            "---\na: b: c\n---",
            "---\na: \"unterminated\n---",
            "---\na: \"trailing\" words\n---",
            "---\na: \"bad \\q escape\"\n---",
            "---\ntags:\n  - a\n  b: 1\n---",
            "---\n: novalue\n---",
            "---\na: [b\n---",
            "---\na: 1\na: 2\n---",
            "---\n? complex\n---",
        ] {
            #expect(properties(block) == nil, "\(block.debugDescription) was understood")
        }
    }
}

// MARK: - Writing one Property

@Suite("Rewriting a Property and nothing else")
struct FrontmatterWritingTests {
    private let block = """
        ---
        # A comment kept as it is
        title: 'A walk'

        mood: 7
        tags: [walk, market]
        places:
          - the market
          - home
        done: false
        ---
        """

    @Test("a control's write rewrites that Property's lines and no others")
    func setOne() {
        let written = Frontmatter(source: block).setting("mood", to: .number(8))
        #expect(
            written.source == """
                ---
                # A comment kept as it is
                title: 'A walk'

                mood: 8
                tags: [walk, market]
                places:
                  - the market
                  - home
                done: false
                ---
                """
        )
        #expect(written.properties?.first { $0.key == "mood" }?.value == .number(8))
    }

    @Test("a list keeps the style it had: flow stays flow, and block stays block with its indent")
    func listStyle() {
        let flow = Frontmatter(source: block).setting("tags", to: .list(["walk", "rain"]))
        #expect(flow.source.contains("\ntags: [walk, rain]\n"))
        let blockStyle = Frontmatter(source: block).setting("places", to: .list(["home"]))
        #expect(blockStyle.source.contains("\nplaces:\n  - home\ndone: false\n"))
        #expect(!blockStyle.source.contains("the market"))
    }

    @Test("an unindented block list keeps its own indent too")
    func flushList() {
        let written = Frontmatter(source: "---\ntags:\n- a\n---").setting("tags", to: .list(["b", "c"]))
        #expect(written.source == "---\ntags:\n- b\n- c\n---")
    }

    @Test("an emptied list is written as [] so that it reads back as a list")
    func emptiedList() {
        let written = Frontmatter(source: block).setting("places", to: .list([]))
        #expect(written.source.contains("\nplaces: []\ndone: false\n"))
        #expect(written.properties?.first { $0.key == "places" }?.value == .list([]))
    }

    @Test("a checkbox, a date and a date and time are written in their one shape")
    func shapes() {
        let source = Frontmatter(source: "---\na: 1\nb: 2\nc: 3\n---")
            .setting("a", to: .checkbox(true))
            .setting("b", to: .date(year: 2026, month: 3, day: 4))
            .setting("c", to: .dateTime(year: 2026, month: 3, day: 4, hour: 9, minute: 5))
            .source
        #expect(source == "---\na: true\nb: 2026-03-04\nc: 2026-03-04T09:05\n---")
    }

    @Test("a number is written with a dot, whole numbers without one")
    func numbers() {
        let source = Frontmatter(source: "---\na: 1\nb: 2\nc: 3\nd: 4\n---")
            .setting("a", to: .number(7))
            .setting("b", to: .number(71.5))
            .setting("c", to: .number(-0.25))
            .setting("d", to: .number(1_000_000))
            .source
        #expect(source == "---\na: 7\nb: 71.5\nc: -0.25\nd: 1000000\n---")
    }

    @Test("text is unquoted when YAML reads it back as the same string, and double-quoted otherwise")
    func quoting() {
        let cases: [(String, String)] = [
            ("A walk", "A walk"),
            ("7", "\"7\""),
            ("7.5", "\"7.5\""),
            ("true", "\"true\""),
            ("null", "\"null\""),
            ("~", "\"~\""),
            ("", "\"\""),
            ("2026-03-14", "\"2026-03-14\""),
            ("2026-03-14T09:05", "\"2026-03-14T09:05\""),
            ("2026-03-14 09:05", "\"2026-03-14 09:05\""),
            (" leading", "\" leading\""),
            ("trailing ", "\"trailing \""),
            ("a: b", "\"a: b\""),
            ("ends with:", "\"ends with:\""),
            ("say # this", "\"say # this\""),
            ("#hashtag", "\"#hashtag\""),
            ("- dash", "\"- dash\""),
            ("-dash", "-dash"),
            ("[bracket", "\"[bracket\""),
            ("{brace", "\"{brace\""),
            ("{{mood}}", "\"{{mood}}\""),
            ("'quote", "\"'quote\""),
            ("\"quote", "\"\\\"quote\""),
            ("back\\slash", "back\\slash"),
            ("two\nlines", "\"two\\nlines\""),
            ("it's fine", "it's fine"),
            ("C# notes", "C# notes"),
            ("https://example.com", "https://example.com"),
            ("café 🎉", "café 🎉"),
            ("&amp", "\"&amp\""),
            ("*star", "\"*star\""),
            ("!bang", "\"!bang\""),
            ("|pipe", "\"|pipe\""),
            (">fold", "\">fold\""),
            ("%pct", "\"%pct\""),
            ("@at", "\"@at\""),
            ("`tick", "\"`tick\""),
            ("?q", "\"?q\""),
            (",comma", "\",comma\""),
            (":colon", "\":colon\""),
        ]
        for (text, expected) in cases {
            let written = Frontmatter(source: "---\na: x\n---").setting("a", to: .text(text))
            #expect(written.source == "---\na: \(expected)\n---", "for \(text.debugDescription)")
            #expect(
                written.properties?.first?.value == .text(text),
                "\(text.debugDescription) did not read back"
            )
        }
    }

    @Test("a flow list quotes an item a comma or a bracket would cut short")
    func flowQuoting() {
        let written = Frontmatter(source: "---\na: [x]\n---")
            .setting("a", to: .list(["one, two", "b]", "plain", "7"]))
        #expect(written.source == "---\na: [\"one, two\", \"b]\", plain, \"7\"]\n---")
        #expect(written.properties?.first?.value == .list(["one, two", "b]", "plain", "7"]))
    }

    @Test("a flow list is read with its quoted items")
    func flowReading() {
        let read = Frontmatter(source: "---\na: [\"one, two\", 'it''s', plain , \"7\"]\n---")
        #expect(read.properties?.first?.value == .list(["one, two", "it's", "plain", "7"]))
    }

    @Test("a key nobody has is left alone")
    func unknownKey() {
        let written = Frontmatter(source: block).setting("nobody", to: .number(1))
        #expect(written.source == block)
    }

    @Test("the whole file round-trips: every Property written back as read is the same block")
    func roundTrip() {
        let source = """
            ---
            title: A walk
            mood: 7
            weight: 71.5
            done: false
            created: 2026-03-14
            at: 2026-03-14T09:05
            tags: [walk, market]
            places:
              - the market
            ---
            """
        var frontmatter = Frontmatter(source: source)
        for property in frontmatter.properties ?? [] {
            frontmatter = frontmatter.setting(property.key, to: property.value)
        }
        #expect(frontmatter.source == source)
    }
}

// MARK: - Adding, renaming, deleting

@Suite("Adding, renaming and deleting a Property")
struct FrontmatterShapeTests {
    @Test("adding puts the Property at the end of the block, seeded in its kind's shape")
    func adding() throws {
        let block = Frontmatter(source: "---\nmood: 7\n---")
        #expect(block.adding("title", as: .text(""))?.source == "---\nmood: 7\ntitle: \"\"\n---")
        #expect(block.adding("n", as: .number(0))?.source == "---\nmood: 7\nn: 0\n---")
        #expect(block.adding("done", as: .checkbox(false))?.source == "---\nmood: 7\ndone: false\n---")
        #expect(
            block.adding("on", as: .date(year: 2026, month: 3, day: 14))?.source
                == "---\nmood: 7\non: 2026-03-14\n---"
        )
        #expect(block.adding("things", as: .list([]))?.source == "---\nmood: 7\nthings: []\n---")
        #expect(
            block.adding("things", as: .list(["a", "b"]))?.source
                == "---\nmood: 7\nthings:\n  - a\n  - b\n---"
        )
    }

    @Test("a list by name is a list however it was seeded")
    func addingByName() {
        let block = Frontmatter(source: "---\nmood: 7\n---")
        #expect(block.adding("tags", as: .text(""))?.properties?.last?.value == .list([]))
        #expect(block.adding("tags", as: .text("walk"))?.source == "---\nmood: 7\ntags:\n  - walk\n---")
    }

    @Test("a key has no colon and no leading or trailing space, and is never one the block has")
    func keyRules() {
        let block = Frontmatter(source: "---\nmood: 7\n---")
        #expect(block.adding("mood", as: .number(0)) == nil)
        #expect(block.adding("a: b", as: .number(0)) == nil)
        #expect(block.adding(" a", as: .number(0)) == nil)
        #expect(block.adding("a ", as: .number(0)) == nil)
        #expect(block.adding("", as: .number(0)) == nil)
        #expect(block.adding("a\nb", as: .number(0)) == nil)
        #expect(block.adding("#a", as: .number(0)) == nil)
        #expect(block.adding("my key", as: .number(0)) != nil)
        #expect(Property.isAKey("my key"))
        #expect(!Property.isAKey("a:b"))
    }

    @Test("a key the reader would not read as one is refused, so the block stays understood")
    func keysTheReaderRefuses() {
        let block = Frontmatter(source: "---\nmood: 7\n---")
        for key in ["@home", "*a", "[x", "- x", "-", "?q", "'quoted", "\"quoted", "&a", "!t", "|b", ">f", "%p", "`t", ",c", "{m", "]x", "}x"] {
            #expect(!Property.isAKey(key), "\(key.debugDescription) was accepted")
            #expect(block.adding(key, as: .number(1)) == nil, "\(key.debugDescription) was added")
            #expect(block.renaming("mood", to: key) == nil, "\(key.debugDescription) was renamed to")
        }
        for key in ["-x", "a-b", "my key", "C#", "日記", "x.y"] {
            #expect(Property.isAKey(key), "\(key.debugDescription) was refused")
            #expect(block.adding(key, as: .number(1))?.isUnderstood == true, "\(key.debugDescription) broke the block")
        }
    }

    @Test("renaming rewrites the key on the Property's first line and nothing else")
    func renaming() {
        let block = Frontmatter(source: "---\n# c\nmood:   7\ntags:\n  - a\n---")
        #expect(block.renaming("mood", to: "feeling")?.source == "---\n# c\nfeeling:   7\ntags:\n  - a\n---")
        #expect(block.renaming("tags", to: "labels")?.source == "---\n# c\nmood:   7\nlabels:\n  - a\n---")
        #expect(block.renaming("mood", to: "tags") == nil)
        #expect(block.renaming("mood", to: "a: b") == nil)
        #expect(block.renaming("mood", to: "mood")?.source == block.source)
        #expect(block.renaming("nobody", to: "x")?.source == block.source)
    }

    @Test("deleting takes the Property's lines, and the block goes with its last Property")
    func deleting() {
        let block = Frontmatter(source: "---\nmood: 7\ntags:\n  - a\n---")
        #expect(block.deleting("tags")?.source == "---\nmood: 7\n---")
        #expect(block.deleting("mood")?.source == "---\ntags:\n  - a\n---")
        #expect(block.deleting("mood")?.deleting("tags") == nil)
        #expect(block.deleting("nobody")?.source == block.source)
    }

    @Test("a block with only comments left in it goes too")
    func deletingLeavesNoHusk() {
        let block = Frontmatter(source: "---\n# note\nmood: 7\n\n---")
        #expect(block.deleting("mood") == nil)
    }

    @Test("nothing rewrites a block that is not understood")
    func notUnderstoodIsNeverWritten() {
        let block = Frontmatter(source: "---\nnested:\n  a: 1\n---")
        #expect(block.properties == nil)
        #expect(block.setting("nested", to: .number(1)).source == block.source)
        #expect(block.adding("x", as: .number(1)) == nil)
        #expect(block.renaming("nested", to: "x") == nil)
        #expect(block.deleting("nested")?.source == block.source)
    }

    @Test("a first Property makes the block, fences and all")
    func first() {
        #expect(Frontmatter.holding("mood", as: .number(7)).source == "---\nmood: 7\n---")
        #expect(
            Frontmatter.holding("tags", as: .list(["a"])).source == "---\ntags:\n  - a\n---"
        )
    }
}

// MARK: - The kinds

@Suite("A Property's kinds")
struct PropertyKindTests {
    @Test("each kind seeds a value of its own shape")
    func seeds() {
        let day = JournalDay(year: 2026, month: 3, day: 14)
        #expect(Property.Kind.text.seed(on: day, at: (9, 5)) == .text(""))
        #expect(Property.Kind.number.seed(on: day, at: (9, 5)) == .number(0))
        #expect(Property.Kind.checkbox.seed(on: day, at: (9, 5)) == .checkbox(false))
        #expect(Property.Kind.date.seed(on: day, at: (9, 5)) == .date(year: 2026, month: 3, day: 14))
        #expect(
            Property.Kind.dateTime.seed(on: day, at: (9, 5))
                == .dateTime(year: 2026, month: 3, day: 14, hour: 9, minute: 5)
        )
        #expect(Property.Kind.list.seed(on: day, at: (9, 5)) == .list([]))
    }

    @Test("a value knows its kind")
    func kindOfValue() {
        #expect(Property.Value.text("").kind == .text)
        #expect(Property.Value.number(1).kind == .number)
        #expect(Property.Value.checkbox(true).kind == .checkbox)
        #expect(Property.Value.date(year: 1, month: 1, day: 1).kind == .date)
        #expect(Property.Value.dateTime(year: 1, month: 1, day: 1, hour: 0, minute: 0).kind == .dateTime)
        #expect(Property.Value.list([]).kind == .list)
    }

    @Test("a date Property is a moment on the device's clock, and back")
    func moments() {
        let date = Property.Value.date(year: 2026, month: 3, day: 14)
        let moment = date.moment(in: paris)
        #expect(moment == instant(2026, 3, 14, 0, in: paris))
        #expect(Property.Value.date(of: instant(2026, 3, 14, 23, 59, in: paris), in: paris) == date)
        let dateTime = Property.Value.dateTime(year: 2026, month: 3, day: 14, hour: 9, minute: 5)
        #expect(dateTime.moment(in: paris) == instant(2026, 3, 14, 9, 5, in: paris))
        #expect(Property.Value.dateTime(of: instant(2026, 3, 14, 9, 5, 30, in: paris), in: paris) == dateTime)
        #expect(Property.Value.date(year: 2026, month: 2, day: 30).moment(in: paris) == nil)
        #expect(Property.Value.text("x").moment(in: paris) == nil)
        #expect(Property.clock(at: instant(2026, 3, 14, 9, 5, in: paris), in: paris) == (9, 5))
    }

    @Test("a number typed with either decimal separator is read")
    func typedNumbers() {
        #expect(Property.number(typed: "7") == 7)
        #expect(Property.number(typed: "7.5") == 7.5)
        #expect(Property.number(typed: "7,5") == 7.5)
        #expect(Property.number(typed: "-0.5") == -0.5)
        #expect(Property.number(typed: " 7 ") == 7)
        #expect(Property.number(typed: "") == nil)
        #expect(Property.number(typed: "7.") == nil)
        #expect(Property.number(typed: "seven") == nil)
        #expect(Property.number(typed: "1e3") == nil)
    }
}
