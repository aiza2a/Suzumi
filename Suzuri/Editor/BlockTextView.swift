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
        textView.isEditable = isFocused && isEditable
        if (!isFocused || !isEditable), textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        textView.placeholder = placeholder
        textView.font = font
        textView.textColor = textColor
        textView.typingAttributes = typingAttributes
        configureCallbacks(on: textView, coordinator: context.coordinator)

        if textView.text != text, !context.coordinator.isEditing {
            let selectedRange = textView.selectedRange
            textView.text = text
            textView.selectedRange = clampedRange(selectedRange, textLength: textView.text.utf16.count)
        }

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

    private func clampedRange(_ range: NSRange, textLength: Int) -> NSRange {
        let location = max(0, min(range.location, textLength))
        let length = max(0, min(range.length, textLength - location))
        return NSRange(location: location, length: length)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var isEditing = false
        var onSelectionChange: ((_ range: NSRange, _ screenRect: CGRect?) -> Void)?

        init(
            text: Binding<String>,
            onSelectionChange: ((_ range: NSRange, _ screenRect: CGRect?) -> Void)?
        ) {
            _text = text
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            notifySelectionChange(for: textView)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText replacement: String
        ) -> Bool {
            guard let blockTextView = textView as? BlockUITextView else { return true }
            guard blockTextView.isEditable else { return false }
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
                isEditing = true
                let currentText = textView.text as NSString
                textView.text = currentText.replacingCharacters(in: range, with: "")
                textView.selectedRange = NSRange(location: range.location, length: 0)
                text = textView.text
            }
            textView.resignFirstResponder()
            textView.onEnter?(range.location)
            isEditing = false
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            notifySelectionChange(for: textView)
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let blockTextView = textView as? BlockUITextView else { return }
            isEditing = true
            text = textView.text
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

    override func insertText(_ text: String) {
        guard isEditable else { return }
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
        guard let key = presses.first?.key else {
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
            if isOnFirstLogicalLine, let onArrowUp {
                onArrowUp(cursorXPosition())
            } else {
                super.pressesBegan(presses, with: event)
            }
        case .keyboardDownArrow:
            if isOnLastLogicalLine, let onArrowDown {
                onArrowDown(cursorXPosition())
            } else {
                super.pressesBegan(presses, with: event)
            }
        default:
            super.pressesBegan(presses, with: event)
        }
    }

    private var isOnFirstLogicalLine: Bool {
        let location = selectedRange.location
        guard location > 0 else { return true }
        let prefix = (text as NSString).substring(to: min(location, text.utf16.count))
        return !prefix.contains("\n")
    }

    private var isOnLastLogicalLine: Bool {
        let location = selectedRange.location
        guard location < text.utf16.count else { return true }
        let suffix = (text as NSString).substring(from: min(location, text.utf16.count))
        return !suffix.contains("\n")
    }

    private func cursorXPosition() -> CGFloat {
        let caret = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
        return caret.midX
    }
}
