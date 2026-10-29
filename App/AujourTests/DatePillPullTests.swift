import SwiftUI
import Testing
import UIKit

@testable import Aujour

@MainActor
@Suite("Pulling the document into the calendar")
struct DatePillPullTests {
    @Test("a calendar pull keeps the document fixed during dragging and deceleration")
    func aCalendarPullPinsTheDocument() {
        let editor = measuredEditor()
        editor.coordinator.swipeDatePill = { _ in true }
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: 100)
        editor.textView.contentOffset.y = -50

        editor.coordinator.scrollViewDidScroll(editor.textView)
        #expect(editor.textView.contentOffset.y == 0)

        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: true)
        editor.textView.contentOffset.y = -20
        editor.coordinator.scrollViewDidScroll(editor.textView)
        #expect(editor.textView.contentOffset.y == 0)
    }

    @Test("a calendar pull keeps the adjusted top and stops inertial scrolling")
    func aCalendarPullHasNoScrollDestination() {
        let editor = measuredEditor()
        editor.coordinator.swipeDatePill = { _ in true }
        editor.textView.contentInset.top = 40
        editor.textView.contentOffset.y = -40
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: 160)
        editor.textView.contentOffset.y = -90
        editor.coordinator.scrollViewDidScroll(editor.textView)
        #expect(editor.textView.contentOffset.y == -40)

        var destination = CGPoint(x: 0, y: -180)
        editor.coordinator.scrollViewWillEndDragging(
            editor.textView, withVelocity: CGPoint(x: 0, y: -1), targetContentOffset: &destination
        )
        #expect(destination == CGPoint(x: 0, y: -40))
    }

    @Test("releasing a pull offers it only once across both delegate callbacks")
    func aPullIsOfferedOnce() {
        let editor = measuredEditor()
        var pulls = 0
        editor.coordinator.swipeDatePill = { _ in pulls += 1; return false }
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: 60)
        var destination = CGPoint(x: 0, y: -100)
        editor.coordinator.scrollViewWillEndDragging(
            editor.textView, withVelocity: .zero, targetContentOffset: &destination
        )
        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: false)
        #expect(pulls == 1)
        #expect(destination == .zero)
    }

    @Test("ordinary scrolling is not pinned", arguments: [false, true])
    func ordinaryScrollingStillMoves(calendarAvailable: Bool) {
        let editor = measuredEditor()
        if calendarAvailable { editor.coordinator.swipeDatePill = { _ in true } }
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: calendarAvailable ? -100 : 100)
        editor.textView.contentOffset.y = calendarAvailable ? 100 : -50
        editor.coordinator.scrollViewDidScroll(editor.textView)
        #expect(editor.textView.contentOffset.y == (calendarAvailable ? 100 : -50))
    }

    @Test("a pull beginning inside the document scrolls even when it reaches the top")
    func scrollingBackToTheTopDoesNotPin() {
        let editor = measuredEditor()
        editor.coordinator.swipeDatePill = { _ in true }
        editor.textView.contentOffset.y = 140
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: 300)
        editor.textView.contentOffset.y = -20
        editor.coordinator.scrollViewDidScroll(editor.textView)
        #expect(editor.textView.contentOffset.y == -20)
    }

    @Test("a new upward drag releases the document after a calendar pull")
    func anotherDragCanScrollNormally() {
        let editor = measuredEditor()
        editor.coordinator.swipeDatePill = { _ in true }
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: 100)
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.coordinator.scrollViewDidEndDragging(editor.textView, willDecelerate: true)
        editor.textView.measuredPan.movement = CGPoint(x: 0, y: -100)
        editor.coordinator.scrollViewWillBeginDragging(editor.textView)
        editor.textView.contentOffset.y = 100
        editor.coordinator.scrollViewDidScroll(editor.textView)
        #expect(editor.textView.contentOffset.y == 100)
    }

    @Test("only a drag that began at the top is offered to the date pill",
          arguments: [CGFloat(0), 140])
    func theDragMustBeginAtTheTop(offset: CGFloat) {
        let editor = measuredEditor()
        var pulls: [CGSize] = []
        editor.coordinator.swipeDatePill = { pulls.append($0); return true }
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
        editor.coordinator.swipeDatePill = { _ in pulls += 1; return true }
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
        editor.coordinator.swipeDatePill = { _ in pulls += 1; return true }
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
