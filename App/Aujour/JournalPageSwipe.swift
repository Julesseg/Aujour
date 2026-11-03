import AujourCore
import SwiftUI
import UIKit

struct JournalPageSwipe: UIGestureRecognizerRepresentable {
    @Binding var swipe: DaySwipe
    let enabled: Bool
    let turn: (Int) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        pan.cancelsTouchesInView = false
        pan.isEnabled = enabled
        return pan
    }

    func updateUIGestureRecognizer(_ pan: UIPanGestureRecognizer, context: Context) {
        pan.isEnabled = enabled
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view)
        switch pan.state {
        case .began, .changed:
            swipe.dragged(across: translation.x, down: translation.y)
        case .ended:
            swipe.dragged(across: translation.x, down: translation.y)
            let landing = swipe.letGo(
                heading: translation.x + pan.velocity(in: pan.view).x * 0.2
            )
            if enabled, landing != .whereItStarted {
                turn(landing.days)
            }
        case .cancelled, .failed:
            swipe.calledOff()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            guard let pan = gesture as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UIControl { return false }
                if let text = current as? UITextView, text.selectedRange.length > 0 { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gesture: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            guard let scroll = other.view as? UIScrollView else { return false }
            return other === scroll.panGestureRecognizer
        }
    }
}
