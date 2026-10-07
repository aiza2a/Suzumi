import SwiftUI
import UIKit
import XCTest
@testable import Suzuri

@MainActor
final class BlockTextViewTests: XCTestCase {
    func testReadOnlyTextRemainsSelectableWithoutMutationCallbacks() {
        var model = "只读文章"
        let coordinator = BlockTextView.Coordinator(
            text: Binding(get: { model }, set: { model = $0 }), onSelectionChange: nil
        )
        let view = BlockUITextView()
        view.text = model
        view.isEditable = false
        view.isSelectable = true
        var didSplit = false
        view.onEnter = { _ in didSplit = true }
        view.insertText("\n")
        view.deleteBackward()
        XCTAssertEqual(view.text, model)
        XCTAssertTrue(view.isSelectable)
        XCTAssertFalse(didSplit)
        XCTAssertFalse(coordinator.textView(view, shouldChangeTextIn: NSRange(location: 0, length: 0), replacementText: "新增"))
    }

    func testFocusedMergeSynchronizesBeforeNextKeystroke() {
        var model = "第一段"
        let coordinator = BlockTextView.Coordinator(
            text: Binding(get: { model }, set: { model = $0 }), onSelectionChange: nil
        )
        let view = BlockUITextView()
        view.text = model
        view.selectedRange = NSRange(location: model.utf16.count, length: 0)
        coordinator.textViewDidBeginEditing(view)

        model += "第二段"
        coordinator.synchronize(model, into: view)
        XCTAssertEqual(view.text, "第一段第二段")
        XCTAssertEqual(view.selectedRange.location, 3)

        view.text += "续写"
        coordinator.textViewDidChange(view)
        XCTAssertEqual(model, "第一段第二段续写")
    }

    func testModelChangeClampsSelectionAfterShortening() {
        var model = "abcdef"
        let coordinator = BlockTextView.Coordinator(
            text: Binding(get: { model }, set: { model = $0 }), onSelectionChange: nil
        )
        let view = BlockUITextView()
        view.text = model
        view.selectedRange = NSRange(location: 4, length: 2)
        coordinator.synchronize("a", into: view)
        XCTAssertEqual(view.text, "a")
        XCTAssertEqual(view.selectedRange, NSRange(location: 1, length: 0))
    }

    func testCompositionIsNotOverwrittenByUnrelatedViewUpdate() {
        var model = ""
        let coordinator = BlockTextView.Coordinator(
            text: Binding(get: { model }, set: { model = $0 }), onSelectionChange: nil
        )
        let view = BlockUITextView()
        view.delegate = coordinator
        view.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0))
        XCTAssertNotNil(view.markedTextRange)
        coordinator.textViewDidChange(view)
        XCTAssertEqual(model, "")
        coordinator.synchronize(model, into: view)
        XCTAssertEqual(view.text, "zhong")
        view.unmarkText()
        XCTAssertEqual(model, "zhong")
    }

    func testWrappedParagraphUsesVisualLineBoundaries() {
        let view = BlockUITextView(frame: CGRect(x: 0, y: 0, width: 90, height: 600))
        view.font = .systemFont(ofSize: 18)
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.text = String(repeating: "写作", count: 40)
        view.layoutIfNeeded()

        view.selectedRange = NSRange(location: 0, length: 0)
        XCTAssertTrue(view.isOnFirstVisualLine)
        XCTAssertFalse(view.isOnLastVisualLine)

        view.selectedRange = NSRange(location: 30, length: 0)
        XCTAssertFalse(view.isOnFirstVisualLine)
        XCTAssertFalse(view.isOnLastVisualLine)

        view.selectedRange = NSRange(location: view.text.utf16.count, length: 0)
        XCTAssertFalse(view.isOnFirstVisualLine)
        XCTAssertTrue(view.isOnLastVisualLine)
    }
}
