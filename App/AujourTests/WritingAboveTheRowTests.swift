import SwiftUI
import Testing
import UIKit

@testable import Aujour

@MainActor
@Suite("Writing above the formatting row", .serialized)
struct WritingAboveTheRowTests {
    @Test("The active line stays above the row while typing", arguments: [
        "wrapping words ", "\n",
    ])
    func theActiveLineStaysVisible(typing: String) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()

        let day = LaidOutDay(String(repeating: "A day of words.\n", count: 40), width: 350)
        let editor = MarkdownTextView(frame: CGRect(x: 0, y: 0, width: 350, height: 400), textContainer: day.container)
        let coordinator = MarkdownEditor.Coordinator(text: .constant(day.storage.string))
        editor.delegate = coordinator
        editor.baseInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        editor.contentInsetAdjustmentBehavior = .never
        editor.inputAccessoryView = UIView(frame: CGRect(x: 0, y: 0, width: 350, height: 80))
        controller.view.addSubview(editor)
        defer {
            editor.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKey()
        }
        #expect(editor.becomeFirstResponder())
        try await Task.sleep(for: .milliseconds(500))

        let row = try #require(editor.inputAccessoryView)
        #expect(row.window != nil)
        let rowTop = row.convert(row.bounds, to: window).minY
        editor.frame.size.height = rowTop + 60
        editor.selectedRange = NSRange(location: day.storage.length, length: 0)
        coordinator.textSettled(in: editor)
        editor.layoutIfNeeded()
        editor.scrollRangeToVisible(editor.selectedRange)
        try await Task.sleep(for: .milliseconds(100))

        let before = editor.caretRect(for: editor.endOfDocument)
        editor.contentOffset.y = before.maxY - (rowTop - 4)
        for _ in 0..<12 {
            editor.insertText(typing)
            editor.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
            let caret = editor.convert(editor.caretRect(for: editor.endOfDocument), to: window)
            #expect(caret.maxY <= rowTop - 4, "The active line is behind the formatting row: \(caret.maxY) > \(rowTop - 4)")
        }

        editor.contentOffset.y -= 40
        let readingOffset = editor.contentOffset
        editor.setNeedsLayout()
        editor.layoutIfNeeded()
        #expect(editor.contentOffset == readingOffset)
    }
}
