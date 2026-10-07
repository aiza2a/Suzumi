import SwiftUI
import UIKit

/// A UIKit text view wrapper used by one editable block.
///
/// The editor stores plain text. This view deliberately does not apply inline markup;
/// Markdown markers remain visible and are sent to Telegraph unchanged.
struct BlockTextView: UIViewRepresentable {
    @Binding var text: String
    var font: UIFont = .preferredFont(forTextStyle: .body)
    var textColor: UIColor = .label
    var lineSpacing: CGFloat = 0
    var isFocused: Bool = false
    var isEditable: Bool = true
    var placeholder: String = ""

    var onEnter: ((_ cursorOffset: Int) -> Void)? = nil
    var onEnterWithSelection: ((_ range: NSRange) -> Void)? = nil
    var onBackspaceAtStart: (() -> Void)? = nil
    var onArrowUp: ((_ cursorX: CGFloat) -> Void)? = nil
    var onArrowDown: ((_ cursorX: CGFloat) -> Void)? = nil
    var onTab: (() -> Void)? = nil
    var onBackTab: (() -> Void)? = nil
    var onSlashAtStart: (() -> Void)? = nil
    var onDeleteForwardAtEnd: (() -> Void)? = nil
    var onSelectionChange: ((_ range: NSRange, _ screenRect: CGRect?) -> Void)? = nil
    var pendingCursorOffset: Binding<Int?>? = nil
    var goalColumnX: Binding<CGFloat?>? = nil

    func makeUIView(context: Context) -> BlockUITextView {
        let textView = BlockUITextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.isEditable = isFocused && isEditable
        textView.isSelectable = true
        textView.alwaysBounceVertical = false
        textView.isScrollEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.font = font
        textView.textColor = textColor
        textView.typingAttributes = typingAttributes
        textView.text = text
        textView.placeholder = placeholder
        configureCallbacks(on: textView, coordinator: context.coordinator)
        return textView
    }

    func updateUIView(_ textView: BlockUITextView, context: Context) {
        context.coordinator.updateBinding($text)
        let wasEditable = textView.isEditable
        textView.isEditable = isFocused && isEditable
        if wasEditable, !textView.isEditable, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        textView.placeholder = placeholder
        if textView.markedTextRange == nil {
            textView.font = font
            textView.textColor = textColor
            textView.typingAttributes = typingAttributes
        }
        configureCallbacks(on: textView, coordinator: context.coordinator)

        context.coordinator.synchronize(text, into: textView)
        guard textView.markedTextRange == nil else { return }

        if isFocused && isEditable, let pendingOffset = pendingCursorOffset?.wrappedValue {
            let clampedOffset = max(0, min(pendingOffset, textView.text.utf16.count))
            focus(textView)
            textView.selectedRange = NSRange(location: clampedOffset, length: 0)
            pendingCursorOffset?.wrappedValue = nil
        } else if isFocused && isEditable, !textView.isFirstResponder {
            focus(textView)
        }
    }

    private func focus(_ textView: BlockUITextView) {
        guard textView.isEditable, !textView.isFirstResponder else { return }
        if textView.window == nil {
            DispatchQueue.main.async { [weak textView] in
                guard let textView, textView.isEditable else { return }
                textView.becomeFirstResponderIfNeeded()
            }
        } else {
            textView.becomeFirstResponderIfNeeded()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSelectionChange: onSelectionChange)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: BlockUITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(font.lineHeight, ceil(size.height)))
    }

    private var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        return [
            .font: font,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func configureCallbacks(on textView: BlockUITextView, coordinator: Coordinator) {
        textView.onEnter = onEnter
        textView.onEnterWithSelection = { [weak coordinator, weak textView] range in
            guard let textView else { return }
            coordinator?.handleEnter(range: range, in: textView)
        }
        textView.onBackspaceAtStart = onBackspaceAtStart
        textView.onArrowUp = onArrowUp
        textView.onArrowDown = onArrowDown
        textView.onTab = onTab
        textView.onBackTab = onBackTab
        textView.onSlashAtStart = onSlashAtStart
        textView.onDeleteForwardAtEnd = onDeleteForwardAtEnd
        textView.goalColumnXBinding = goalColumnX
        coordinator.onSelectionChange = onSelectionChange
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var onSelectionChange: ((_ range: NSRange, _ screenRect: CGRect?) -> Void)?

        init(
            text: Binding<String>,
            onSelectionChange: ((_ range: NSRange, _ screenRect: CGRect?) -> Void)?
        ) {
            _text = text
            self.onSelectionChange = onSelectionChange
        }

        /// Focus is not an editing transaction: merges and toolbar changes must reach
        /// the active view too. Marked text is owned by the input method until committed.
        func synchronize(_ modelText: String, into textView: UITextView) {
            guard textView.markedTextRange == nil, textView.text != modelText else { return }
            let selection = textView.selectedRange
            // UIKit's previous text-only undo history does not include a block merge.
            // Keeping it would allow undo to overwrite the newly joined paragraph.
            textView.undoManager?.removeAllActions()
            textView.text = modelText
            let location = min(selection.location, modelText.utf16.count)
            textView.selectedRange = NSRange(
                location: location,
                length: min(selection.length, modelText.utf16.count - location)
            )
            textView.invalidateIntrinsicContentSize()
        }

        func updateBinding(_ binding: Binding<String>) {
            _text = binding
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            notifySelectionChange(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard let blockTextView = textView as? BlockUITextView else { return true }
            guard blockTextView.isEditable else { return false }
            guard textView.markedTextRange == nil else { return true }
            if replacement == "\n", blockTextView.onEnter != nil {
                blockTextView.onEnterWithSelection?(range)
                return false
            }
            if replacement == "/",
               blockTextView.text.isEmpty,
               range.location == 0,
               let onSlashAtStart = blockTextView.onSlashAtStart
            {
                onSlashAtStart()
                return false
            }
            if replacement.isEmpty,
               range.location == 0,
               range.length == 0,
               let onBackspaceAtStart = blockTextView.onBackspaceAtStart
            {
                onBackspaceAtStart()
                return false
            }
            if replacement.isEmpty,
               range.length == 0,
               range.location >= blockTextView.text.utf16.count,
               let onDeleteForwardAtEnd = blockTextView.onDeleteForwardAtEnd
            {
                onDeleteForwardAtEnd()
                return false
            }
            return true
        }

        func handleEnter(range: NSRange, in textView: BlockUITextView) {
            if range.length > 0 {
                let currentText = textView.text as NSString
                textView.text = currentText.replacingCharacters(in: range, with: "")
                textView.selectedRange = NSRange(location: range.location, length: 0)
                text = textView.text
            }
            textView.resignFirstResponder()
            textView.onEnter?(range.location)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            notifySelectionChange(for: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let blockTextView = textView as? BlockUITextView else { return }
            if textView.markedTextRange == nil {
                text = textView.text
            }
            blockTextView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            notifySelectionChange(for: textView)
        }

        private func notifySelectionChange(for textView: UITextView) {
            let range = textView.selectedRange
            let rect = selectionRect(for: range, in: textView)
            onSelectionChange?(range, rect)
        }

        private func selectionRect(for range: NSRange, in textView: UITextView) -> CGRect? {
            guard range.length > 0,
                  let start = textView.position(
                      from: textView.beginningOfDocument,
                      offset: range.location
                  ),
                  let end = textView.position(
                      from: start,
                      offset: range.length
                  ),
                  let textRange = textView.textRange(from: start, to: end)
            else { return nil }
            return textView.convert(textView.firstRect(for: textRange), to: nil)
        }
    }
}

/// UITextView subclass that turns boundary keyboard commands into editor callbacks.
final class BlockUITextView: UITextView {
    var placeholder = "" {
        didSet { setNeedsDisplay() }
    }
    var onEnter: ((_ cursorOffset: Int) -> Void)?
    var onEnterWithSelection: ((_ range: NSRange) -> Void)?
    var onBackspaceAtStart: (() -> Void)?
    var onArrowUp: ((_ cursorX: CGFloat) -> Void)?
    var onArrowDown: ((_ cursorX: CGFloat) -> Void)?
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    var onSlashAtStart: (() -> Void)?
    var onDeleteForwardAtEnd: (() -> Void)?
    var goalColumnXBinding: Binding<CGFloat?>?

    override var canBecomeFirstResponder: Bool { true }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard text.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.placeholderText
        ]
        placeholder.draw(at: CGPoint(x: textContainerInset.left, y: textContainerInset.top), withAttributes: attributes)
    }

    func becomeFirstResponderIfNeeded() {
        guard !isFirstResponder else { return }
        _ = becomeFirstResponder()
    }

    override func unmarkText() {
        let wasComposing = markedTextRange != nil
        super.unmarkText()
        // Some input methods end composition without another didChange callback.
        // Publish the committed text before save, focus transfer, or a toolbar action.
        if wasComposing, markedTextRange == nil {
            delegate?.textViewDidChange?(self)
        }
    }

    override func insertText(_ text: String) {
        guard isEditable else { return }
        guard markedTextRange == nil else {
            super.insertText(text)
            return
        }
        if text == "\n", let onEnter {
            if let onEnterWithSelection {
                onEnterWithSelection(selectedRange)
            } else {
                resignFirstResponder()
                onEnter(selectedRange.location)
            }
            return
        }
        if text == "\t", let onTab {
            onTab()
            return
        }
        if text == "/",
           self.text.isEmpty,
           selectedRange.location == 0,
           let onSlashAtStart
        {
            onSlashAtStart()
            return
        }
        super.insertText(text)
    }

    override func deleteBackward() {
        guard isEditable else { return }
        guard markedTextRange == nil else {
            super.deleteBackward()
            return
        }
        goalColumnXBinding?.wrappedValue = nil
        if selectedRange.length == 0,
           selectedRange.location == 0,
           let onBackspaceAtStart
        {
            onBackspaceAtStart()
            return
        }
        super.deleteBackward()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isEditable else {
            super.pressesBegan(presses, with: event)
            return
        }
        guard markedTextRange == nil, let key = presses.first?.key else {
            super.pressesBegan(presses, with: event)
            return
        }
        switch key.keyCode {
        case .keyboardReturnOrEnter:
            if onEnter != nil {
                if let onEnterWithSelection {
                    onEnterWithSelection(selectedRange)
                } else {
                    resignFirstResponder()
                    onEnter?(selectedRange.location)
                }
            } else {
                super.pressesBegan(presses, with: event)
            }
        case .keyboardTab:
            if key.modifierFlags.contains(.shift), let onBackTab {
                onBackTab()
            } else if !key.modifierFlags.contains(.shift), let onTab {
                onTab()
            } else {
                super.pressesBegan(presses, with: event)
            }
        case .keyboardDeleteOrBackspace:
            let isForwardDelete = key.characters == "\u{F728}"
                || key.charactersIgnoringModifiers == "\u{F728}"
            if isForwardDelete,
               selectedRange.length == 0,
               selectedRange.location >= text.utf16.count,
               let onDeleteForwardAtEnd
            {
                goalColumnXBinding?.wrappedValue = nil
                onDeleteForwardAtEnd()
            } else {
                super.pressesBegan(presses, with: event)
            }
        case .keyboardUpArrow:
            if key.modifierFlags.isEmpty, selectedRange.length == 0,
               isOnFirstVisualLine, let onArrowUp {
                onArrowUp(cursorXPosition())
            } else {
                super.pressesBegan(presses, with: event)
            }
        case .keyboardDownArrow:
            if key.modifierFlags.isEmpty, selectedRange.length == 0,
               isOnLastVisualLine, let onArrowDown {
                onArrowDown(cursorXPosition())
            } else {
                super.pressesBegan(presses, with: event)
            }
        default:
            super.pressesBegan(presses, with: event)
        }
    }

    var isOnFirstVisualLine: Bool {
        layoutIfNeeded()
        let current = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
        let first = caretRect(for: beginningOfDocument)
        return abs(current.minY - first.minY) < 1
    }

    var isOnLastVisualLine: Bool {
        layoutIfNeeded()
        let current = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
        let last = caretRect(for: endOfDocument)
        return abs(current.minY - last.minY) < 1
    }

    private func cursorXPosition() -> CGFloat {
        let caret = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
        return caret.midX
    }
}
