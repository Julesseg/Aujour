import Testing
import UIKit

@testable import Aujour

// How a Property's row divides between the name and the value. The drawing is
// the UI suite's to check; this is the rule the drawing follows — that a value
// which is read whole is measured first and the name is what gives, down to a
// floor, and under that floor the row is two lines instead of one.

@Suite("A Property's row")
struct PropertyRowLayoutTests {
    private let spacing: CGFloat = Spacing.comfortable

    private func division(of width: CGFloat, forAValueWanting wanted: CGFloat)
        -> PropertyRowLayout.Division
    {
        PropertyRowLayout.division(of: width, forAValueWanting: wanted, spacing: spacing)
    }

    @Test("gives the name its column and the value the rest, where there is room")
    func roomy() {
        let row = division(of: 400, forAValueWanting: 190)

        #expect(row.key == PropertyRowLayout.key)
        #expect(row.value == 400 - PropertyRowLayout.key - spacing)
        #expect(!row.isStacked)
    }

    @Test("a value with no width to ask for leaves the name its whole column")
    func indivisibleOrNot() {
        // What every row of words comes out as: nothing is asking, so the
        // name's column is the name's column.
        let row = division(of: 200, forAValueWanting: 0)

        #expect(row.key == PropertyRowLayout.key)
        #expect(row.value == 200 - PropertyRowLayout.key - spacing)
    }

    @Test("takes the room a wide value needs out of the name, not out of the value")
    func squeezed() {
        let row = division(of: 327, forAValueWanting: 231)

        #expect(row.value == 231)
        #expect(row.key == 327 - 231 - spacing)
        #expect(row.key < PropertyRowLayout.key)
        #expect(row.key > PropertyRowLayout.narrowestKey)
        #expect(!row.isStacked)
    }

    @Test("squeezes the name to the floor and no further")
    func floor() {
        let atTheFloor = division(
            of: PropertyRowLayout.narrowestKey + Spacing.comfortable + 231,
            forAValueWanting: 231
        )

        #expect(atTheFloor.key == PropertyRowLayout.narrowestKey)
        #expect(atTheFloor.value == 231)
        #expect(!atTheFloor.isStacked)
    }

    @Test("puts the value under the name when even the floor is not enough")
    func stacked() {
        let row = division(
            of: PropertyRowLayout.narrowestKey + Spacing.comfortable + 231 - 1,
            forAValueWanting: 231
        )

        #expect(row.isStacked)
        // Both get the whole row: the name reads from the left of it, the
        // value sits at the right of the line under.
        #expect(row.key == PropertyRowLayout.narrowestKey + Spacing.comfortable + 231 - 1)
        #expect(row.value == row.key)
    }

    @Test("a row with next to nothing in it is two lines rather than a negative one")
    func nothing() {
        let row = division(of: 10, forAValueWanting: 0)

        #expect(row.isStacked)
        #expect(row.key == 10)
        #expect(row.value == 10)
    }
}
