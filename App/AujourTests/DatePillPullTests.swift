import SwiftUI
import Testing
import UIKit

@testable import Aujour

@MainActor
@Suite("Pulling the document into the calendar")
struct DatePillPullTests {
    @Test("only a drag that began at the top is offered to the date pill",
          arguments: [CGFloat(0), 140])
    func theDragMustBeginAtTheTop(offset: CGFloat) {
        let editor = measuredEditor()
        var pulls: [CGSize] = []
        editor.coordinator.swipeDatePill = { pulls.append($0) }
        editor.textView.contentOffset.y = offset
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.contentOffset.y = -60
        editor.textView.measuredPan.movement = CGPoint(x: 2, y: 160)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: true)

        #expect(pulls == (offset == 0 ? [CGSize(width: 2, height: 160)] : []))
    }

    @Test("the top includes the scroll view's adjusted inset")
    func theTopAccountsForInsets() {
        let editor = measuredEditor()
        var pulls = 0
        editor.coordinator.swipeDatePill = { _ in pulls += 1 }
        editor.textView.contentInset.top = 40
        editor.textView.contentOffset.y = -editor.textView.adjustedContentInset.top
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: 160)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: false)

        #expect(pulls == 1)
    }

    @Test("an upward scroll from the top is not offered as a pull")
    func scrollingIntoTheDocumentDoesNotPullTheCalendar() {
        let editor = measuredEditor()
        var pulls = 0
        editor.coordinator.swipeDatePill = { _ in pulls += 1 }
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: -160)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: false)

        #expect(pulls == 0)
    }
}

@MainActor
private func measuredEditor() -> (textView: MeasuredScrollView, coordinator: MarkdownEditor.Coordinator) {
    let textView = MeasuredScrollView(frame: CGRect(x: 0, y: 0, width: 350, height: 400))
    textView.contentSize = CGSize(width: 350, height: 1000)
    return (textView, MarkdownEditor.Coordinator(text: .constant("Words.\n")))
}

@MainActor
private final class MeasuredScrollView: UIScrollView {
    let measuredPan = MeasuredPan()

    override var panGestureRecognizer: UIPanGestureRecognizer { measuredPan }
}

@MainActor
private final class MeasuredPan: UIPanGestureRecognizer {
    var movement: CGPoint = .zero

    override func translation(in view: UIView?) -> CGPoint { movement }
}
