import Testing
import UIKit

@testable import Aujour

@MainActor
@Suite("Pulling the document into the calendar")
struct DatePillPullTests {
    @Test("only a drag that began at the top is offered to the date pill",
          arguments: [CGFloat(0), 140])
    func theDragMustBeginAtTheTop(offset: CGFloat) {
        let editor = OpenEditor(holding: "Words.\n")
        var pulls: [CGSize] = []
        editor.coordinator.swipeDatePill = { pulls.append($0) }
        editor.textView.contentOffset.y = offset
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.contentOffset.y = -60
        editor.textView.panGestureRecognizer.setTranslation(CGPoint(x: 2, y: 160), in: editor.textView)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: true)

        #expect(pulls == (offset == 0 ? [CGSize(width: 2, height: 160)] : []))
    }

    @Test("the top includes the scroll view's adjusted inset")
    func theTopAccountsForInsets() {
        let editor = OpenEditor(holding: "Words.\n")
        var pulls = 0
        editor.coordinator.swipeDatePill = { _ in pulls += 1 }
        editor.textView.contentInset.top = 40
        editor.textView.contentOffset.y = -editor.textView.adjustedContentInset.top
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.panGestureRecognizer.setTranslation(CGPoint(x: 0, y: 160), in: editor.textView)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: false)

        #expect(pulls == 1)
    }

    @Test("an upward scroll from the top is not offered as a pull")
    func scrollingIntoTheDocumentDoesNotPullTheCalendar() {
        let editor = OpenEditor(holding: "Words.\n")
        var pulls = 0
        editor.coordinator.swipeDatePill = { _ in pulls += 1 }
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.panGestureRecognizer.setTranslation(CGPoint(x: 0, y: -160), in: editor.textView)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: false)

        #expect(pulls == 0)
    }
}
