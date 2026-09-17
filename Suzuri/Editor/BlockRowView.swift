import SwiftUI
import UIKit

/// Renders one document block, its focus chrome, and the block gutter controls.
@MainActor
struct BlockRowView: View {
    let block: Block
    @Environment(BlockEditorDocument.self) private var document

    var isBlockSelected = false
    var isMultiSelectionActive = false
    var onTap: (() -> Void)?
    var onSelectionChange: ((_ range: NSRange, _ screenRect: CGRect?) -> Void)?
    var focusedListItemID: Binding<UUID?>? = nil

    @State private var showSlashCommand = false
    @State private var localFocusedListItemID: UUID?
    @State private var dragOffset: CGFloat = 0

    private var isFocused: Bool {
        document.focusedBlockID == block.id
    }

    private static let gutterWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if !block.isListBlock {
                gutter
            }
            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu { blockContextMenu }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(selectionBackground)
        .overlay(focusOverlay)
        .shadow(
            color: Color.brand600.opacity(isFocused ? 0.12 : 0),
            radius: isFocused ? 10 : 0,
            y: isFocused ? 4 : 0
        )
        .animation(AppAnimation.blockFocus, value: isFocused)
        .animation(AppAnimation.blockFocus, value: isBlockSelected)
        .onTapGesture {
            if !isMultiSelectionActive, !block.isListBlock {
                focusRow()
            }
            onTap?()
        }
        .sheet(isPresented: $showSlashCommand) {
            SlashCommandMenu(
                isPresented: $showSlashCommand,
                blockID: block.id,
                document: document
            )
        }
    }

    private var selectionBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.brand200.opacity(isBlockSelected ? 0.12 : 0))
            .allowsHitTesting(false)
    }

    private var focusOverlay: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(
                Color.brand600.opacity(isFocused ? 0.55 : 0),
                lineWidth: 1.2
            )
            .allowsHitTesting(false)
    }

    private var gutter: some View {
        HStack(spacing: 2) {
            addBlockMenu
            dragHandle
        }
        .frame(width: Self.gutterWidth, alignment: .trailing)
        .padding(.trailing, 4)
        .opacity(isFocused ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .allowsHitTesting(isFocused)
        .accessibilityHidden(!isFocused)
    }

    private var addBlockMenu: some View {
        Menu {
            ForEach(BlockType.groupedByCategory, id: \.category) { group in
                Section(group.category.rawValue) {
                    ForEach(group.types, id: \.self) { type in
                        Button {
                            insertBlock(of: type)
                        } label: {
                            Label(type.displayName, systemImage: type.icon)
                        }
                    }
                }
            }
        } label: {
            gutterIcon(systemName: "plus", label: "Add block")
        }
        .accessibilityLabel("Add block")
    }

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .offset(y: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragOffset = value.translation.height
                    }
                    .onEnded { value in
                        dragOffset = 0
                        moveAfterDrag(value.translation.height)
                    }
            )
            .accessibilityLabel("Reorder block")
    }

    private func gutterIcon(systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 22)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block {
        case let .paragraph(id, _):
            textBlock(id: id, placeholder: "开始写作…")

        case let .heading(id, level, text):
            headingBlock(id: id, level: level, text: text)

        case let .bulletList(id, items):
            listBlock(id: id, items: items, numbered: false)

        case let .numberedList(id, items):
            listBlock(id: id, items: items, numbered: true)

        case let .quote(id, _):
            quoteBlock(id: id)

        case let .code(id, _):
            codeBlock(id: id)

        case .divider:
            Divider()
                .padding(.vertical, 12)
                .frame(minHeight: 32)
                .accessibilityLabel("Divider")

        case let .figure(id, imageURL, caption):
            figureBlock(id: id, imageURL: imageURL, caption: caption)

        case let .link(id, _, url):
            linkBlock(id: id, url: url)
        }
    }

    private func textBlock(id: BlockID, placeholder: String) -> some View {
        textEditor(
            id: id,
            font: .preferredFont(forTextStyle: .body),
            placeholder: placeholder,
            onEnter: { splitBlock(id: id, utf16Offset: $0) },
            onBackspaceAtStart: { mergePreviousBlock(id: id) },
            onArrowUp: { moveToPreviousBlock(from: id) },
            onArrowDown: { moveToNextBlock(from: id) },
            onSlashAtStart: { showSlashCommand = true },
            onDeleteForwardAtEnd: { mergeNextBlock(id: id) }
        )
        .frame(minHeight: 28)
    }

    private func headingBlock(id: BlockID, level: Int, text: String) -> some View {
        textEditor(
            id: id,
            font: headingFont(for: level),
            placeholder: "标题",
            onEnter: { offset in
                if document.block(for: id)?.isEmpty ?? true {
                    document.replaceBlock(id: id, with: .paragraph(id: id, text: ""))
                    focusBlock(id: id, cursorAtEnd: false)
                } else {
                    splitBlock(id: id, utf16Offset: offset)
                }
            },
            onBackspaceAtStart: {
                if document.block(for: id)?.isEmpty ?? true {
                    document.replaceBlock(id: id, with: .paragraph(id: id, text: ""))
                    focusBlock(id: id, cursorAtEnd: false)
                } else {
                    mergePreviousBlock(id: id)
                }
            },
            onArrowUp: { moveToPreviousBlock(from: id) },
            onArrowDown: { moveToNextBlock(from: id) },
            onDeleteForwardAtEnd: { mergeNextBlock(id: id) }
        )
        .font(.system(size: level <= 1 ? 28 : 23, weight: .bold))
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Heading level \(level): \(text)")
        .frame(minHeight: level <= 1 ? 38 : 32)
    }

    private func quoteBlock(id: BlockID) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.brand600.opacity(0.75))
                .frame(width: 4)

            textEditor(
                id: id,
                font: .preferredFont(forTextStyle: .body),
                textColor: .secondaryLabel,
                placeholder: "引用",
                onEnter: { splitBlock(id: id, utf16Offset: $0) },
                onBackspaceAtStart: { mergePreviousBlock(id: id) },
                onArrowUp: { moveToPreviousBlock(from: id) },
                onArrowDown: { moveToNextBlock(from: id) },
                onDeleteForwardAtEnd: { mergeNextBlock(id: id) }
            )
            .frame(minHeight: 28)
        }
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .background(Color.brand50.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func codeBlock(id: BlockID) -> some View {
        textEditor(
            id: id,
            font: .monospacedSystemFont(ofSize: 15, weight: .regular),
            placeholder: "代码",
            onArrowUp: { moveToPreviousBlock(from: id) },
            onArrowDown: { moveToNextBlock(from: id) },
            onDeleteForwardAtEnd: { mergeNextBlock(id: id) }
        )
        .padding(12)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    private func linkBlock(id: BlockID, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            textEditor(
                id: id,
                font: .preferredFont(forTextStyle: .body),
                placeholder: "链接文字",
                onEnter: { splitBlock(id: id, utf16Offset: $0) },
                onBackspaceAtStart: { mergePreviousBlock(id: id) },
                onArrowUp: { moveToPreviousBlock(from: id) },
                onArrowDown: { moveToNextBlock(from: id) },
                onDeleteForwardAtEnd: { mergeNextBlock(id: id) }
            )
            Text(url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func listBlock(id: BlockID, items: [ListItem], numbered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                listItem(
                    blockID: id,
                    item: item,
                    marker: numbered ? "\(index + 1)." : "•",
                    items: items,
                    numbered: numbered
                )
            }
        }
        .padding(.leading, 4)
    }

    private func listItem(
        blockID: BlockID,
        item: ListItem,
        marker: String,
        items: [ListItem],
        numbered: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(marker)
                .font(.system(size: 17, weight: numbered ? .regular : .bold))
                .foregroundStyle(.secondary)
                .frame(minWidth: numbered ? 24 : 14, alignment: .trailing)
                .frame(minHeight: 28)

            textEditor(
                id: blockID,
                text: listItemBinding(blockID: blockID, itemID: item.id),
                font: .preferredFont(forTextStyle: .body),
                isFocused: isFocused
                    && activeListItemID(for: block) == item.id,
                placeholder: "列表项",
                onEnter: { offset in
                    splitListItem(
                        blockID: blockID,
                        itemID: item.id,
                        utf16Offset: offset
                    )
                },
                onBackspaceAtStart: {
                    deleteOrMergeListItem(
                        blockID: blockID,
                        item: item,
                        items: items
                    )
                },
                onArrowUp: {
                    moveWithinList(
                        blockID: blockID,
                        itemID: item.id,
                        direction: .up,
                        items: items
                    )
                },
                onArrowDown: {
                    moveWithinList(
                        blockID: blockID,
                        itemID: item.id,
                        direction: .down,
                        items: items
                    )
                },
                // TODO: V2 list item indent via Tab
                onTab: nil,
                onBackTab: nil,
                onSlashAtStart: nil,
                onDeleteForwardAtEnd: {
                    mergeNextListItem(
                        blockID: blockID,
                        itemID: item.id,
                        items: items
                    )
                }
            )
            .frame(minHeight: 28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isMultiSelectionActive else { return }
            let isChangingFocus = document.focusedBlockID != blockID
                || activeListItemID(for: block) != item.id
            document.focusedBlockID = blockID
            setFocusedListItemID(item.id)
            document.pendingCursorOffset = isChangingFocus ? item.text.utf16.count : nil
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(item.text.isEmpty ? "Empty list item" : item.text)
    }

    private func figureBlock(id: BlockID, imageURL: URL?, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            figurePlaceholder("图片加载失败")
                        default:
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 150)
                        }
                    }
                } else {
                    figurePlaceholder("等待图片")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            TextField("图片说明（可选）", text: captionBinding(for: id))
                .textFieldStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .padding(.vertical, 4)
    }

    private func figurePlaceholder(_ title: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func textEditor(
        id: BlockID,
        font: UIFont,
        textColor: UIColor = .label,
        placeholder: String,
        onEnter: ((Int) -> Void)? = nil,
        onBackspaceAtStart: (() -> Void)? = nil,
        onArrowUp: ((CGFloat) -> Void)? = nil,
        onArrowDown: ((CGFloat) -> Void)? = nil,
        onSlashAtStart: (() -> Void)? = nil,
        onDeleteForwardAtEnd: (() -> Void)? = nil
    ) -> some View {
        BlockTextView(
            text: textBinding(for: id),
            font: font,
            textColor: textColor,
            lineSpacing: 3,
            isFocused: isFocused,
            placeholder: placeholder,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
            onArrowUp: onArrowUp,
            onArrowDown: onArrowDown,
            onSlashAtStart: onSlashAtStart,
            onDeleteForwardAtEnd: onDeleteForwardAtEnd,
            onSelectionChange: onSelectionChange,
            pendingCursorOffset: documentCursorBinding(),
            goalColumnX: nil
        )
        .id(id)
    }

    private func textEditor(
        id: BlockID,
        text: Binding<String>,
        font: UIFont,
        isFocused: Bool,
        placeholder: String,
        onEnter: ((Int) -> Void)? = nil,
        onBackspaceAtStart: (() -> Void)? = nil,
        onArrowUp: ((CGFloat) -> Void)? = nil,
        onArrowDown: ((CGFloat) -> Void)? = nil,
        onTab: (() -> Void)? = nil,
        onBackTab: (() -> Void)? = nil,
        onSlashAtStart: (() -> Void)? = nil,
        onDeleteForwardAtEnd: (() -> Void)? = nil
    ) -> some View {
        BlockTextView(
            text: text,
            font: font,
            lineSpacing: 3,
            isFocused: isFocused,
            placeholder: placeholder,
            onEnter: onEnter,
            onBackspaceAtStart: onBackspaceAtStart,
            onArrowUp: onArrowUp,
            onArrowDown: onArrowDown,
            onTab: onTab,
            onBackTab: onBackTab,
            onSlashAtStart: onSlashAtStart,
            onDeleteForwardAtEnd: onDeleteForwardAtEnd,
            onSelectionChange: onSelectionChange,
            pendingCursorOffset: documentCursorBinding(),
            goalColumnX: nil
        )
    }

    private func textBinding(for id: BlockID) -> Binding<String> {
        Binding(
            get: { document.block(for: id)?.textContent ?? "" },
            set: { document.updateText(blockID: id, text: $0) }
        )
    }

    private func listItemBinding(blockID: BlockID, itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                guard let item = listItems(for: blockID)?.first(where: { $0.id == itemID }) else {
                    return ""
                }
                return item.text
            },
            set: { updateListItem(blockID: blockID, itemID: itemID, text: $0) }
        )
    }

    private func captionBinding(for blockID: BlockID) -> Binding<String> {
        Binding(
            get: {
                guard let current = document.block(for: blockID),
                      case let .figure(_, _, caption) = current
                else { return "" }
                return caption
            },
            set: { newCaption in
                guard let current = document.block(for: blockID),
                      case let .figure(id, imageURL, _) = current
                else { return }
                document.replaceBlock(
                    id: blockID,
                    with: .figure(id: id, imageURL: imageURL, caption: newCaption)
                )
            }
        )
    }

    private func documentCursorBinding() -> Binding<Int?> {
        Binding(
            get: { document.pendingCursorOffset },
            set: { document.pendingCursorOffset = $0 }
        )
    }

    private var focusedListItemValue: UUID? {
        focusedListItemID?.wrappedValue ?? localFocusedListItemID
    }

    private func setFocusedListItemID(_ value: UUID?) {
        if let focusedListItemID {
            focusedListItemID.wrappedValue = value
        } else {
            localFocusedListItemID = value
        }
    }

    private func activeListItemID(for block: Block) -> UUID? {
        let itemIDs: [UUID]
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            itemIDs = items.map(\.id)
        default:
            return nil
        }
        guard let candidate = focusedListItemValue, itemIDs.contains(candidate) else {
            return itemIDs.first
        }
        return candidate
    }

    private func listItems(for blockID: BlockID) -> [ListItem]? {
        guard let current = document.block(for: blockID) else { return nil }
        switch current {
        case let .bulletList(_, items), let .numberedList(_, items):
            return items
        default:
            return nil
        }
    }

    private func updateListItem(blockID: BlockID, itemID: UUID, text: String) {
        guard let current = document.block(for: blockID) else { return }
        switch current {
        case let .bulletList(id, items):
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            var updated = items
            updated[index].text = text
            document.replaceBlock(id: blockID, with: .bulletList(id: id, items: updated))
        case let .numberedList(id, items):
            guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
            var updated = items
            updated[index].text = text
            document.replaceBlock(id: blockID, with: .numberedList(id: id, items: updated))
        default:
            break
        }
    }

    private func splitListItem(blockID: BlockID, itemID: UUID, utf16Offset: Int) {
        guard let item = listItems(for: blockID)?.first(where: { $0.id == itemID }) else { return }
        let offset = characterOffset(fromUTF16: utf16Offset, in: item.text)
        guard let newItemID = document.splitListItem(
            blockID: blockID,
            itemID: itemID,
            atOffset: offset
        ) else { return }
        document.focusedBlockID = blockID
        setFocusedListItemID(newItemID)
        document.pendingCursorOffset = 0
    }

    private func deleteOrMergeListItem(
        blockID: BlockID,
        item: ListItem,
        items: [ListItem]
    ) {
        guard let itemIndex = items.firstIndex(where: { $0.id == item.id }) else { return }
        if itemIndex > 0 {
            let previous = items[itemIndex - 1]
            updateListItem(blockID: blockID, itemID: previous.id, text: previous.text + item.text)
            document.deleteListItem(in: blockID, at: item.id)
            setFocusedListItemID(previous.id)
            document.pendingCursorOffset = previous.text.utf16.count
        } else if item.text.isEmpty, items.count > 1 {
            document.deleteListItem(in: blockID, at: item.id)
            setFocusedListItemID(items[1].id)
            document.pendingCursorOffset = 0
        } else if item.text.isEmpty {
            removeCurrentBlockAndFocusPrevious(id: blockID)
        }
    }

    private func mergeNextListItem(blockID: BlockID, itemID: UUID, items: [ListItem]) {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }),
              itemIndex + 1 < items.count
        else { return }
        let next = items[itemIndex + 1]
        let current = items[itemIndex]
        updateListItem(blockID: blockID, itemID: itemID, text: current.text + next.text)
        document.deleteListItem(in: blockID, at: next.id)
        document.pendingCursorOffset = current.text.utf16.count
    }

    private func moveWithinList(
        blockID: BlockID,
        itemID: UUID,
        direction: BlockEditorDocument.MoveDirection,
        items: [ListItem]
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        switch direction {
        case .up:
            guard index > 0 else {
                moveToPreviousBlock(from: blockID)
                return
            }
            setFocusedListItemID(items[index - 1].id)
            document.pendingCursorOffset = items[index - 1].text.utf16.count
        case .down:
            guard index + 1 < items.count else {
                moveToNextBlock(from: blockID)
                return
            }
            setFocusedListItemID(items[index + 1].id)
            document.pendingCursorOffset = 0
        }
        document.focusedBlockID = blockID
    }

    private var blockContextMenu: some View {
        Group {
            Menu("Turn into") {
                ForEach(BlockType.turnIntoTypes, id: \.self) { type in
                    Button {
                        turnInto(type)
                    } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            }
            Button {
                duplicateBlock()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) {
                removeCurrentBlockAndFocusPrevious(id: block.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func insertBlock(of type: BlockType) {
        let newBlock = type.makeEmpty
        document.insertBlock(newBlock, after: block.id)
        focusBlock(id: newBlock.id, cursorAtEnd: false)
    }

    private func turnInto(_ type: BlockType) {
        document.replaceBlock(id: block.id, with: turnedBlock(type))
        focusBlock(id: block.id, cursorAtEnd: false)
    }

    private func turnedBlock(_ type: BlockType) -> Block {
        switch block {
        case let .bulletList(id, items):
            return turnedList(items: items, id: id, type: type)
        case let .numberedList(id, items):
            return turnedList(items: items, id: id, type: type)
        default:
            return type.makeBlock(id: block.id, text: block.textContent ?? "")
        }
    }

    private func turnedList(
        items: [ListItem],
        id: BlockID,
        type: BlockType
    ) -> Block {
        switch type {
        case .bulletList:
            return .bulletList(id: id, items: items)
        case .numberedList:
            return .numberedList(id: id, items: items)
        default:
            let text = items.map(\.text).joined(separator: "\n")
            return type.makeBlock(id: id, text: text)
        }
    }

    private func duplicateBlock() {
        let duplicate = copyOfBlock(block)
        document.insertBlock(duplicate, after: block.id)
        focusBlock(id: duplicate.id, cursorAtEnd: true)
    }

    private func copyOfBlock(_ block: Block) -> Block {
        switch block {
        case let .paragraph(_, text):
            .paragraph(id: UUID(), text: text)
        case let .heading(_, level, text):
            .heading(id: UUID(), level: level, text: text)
        case let .bulletList(_, items):
            .bulletList(id: UUID(), items: items.map { ListItem(text: $0.text) })
        case let .numberedList(_, items):
            .numberedList(id: UUID(), items: items.map { ListItem(text: $0.text) })
        case let .quote(_, text):
            .quote(id: UUID(), text: text)
        case let .code(_, text):
            .code(id: UUID(), text: text)
        case .divider:
            .divider(id: UUID())
        case let .figure(_, imageURL, caption):
            .figure(id: UUID(), imageURL: imageURL, caption: caption)
        case let .link(_, text, url):
            .link(id: UUID(), text: text, url: url)
        }
    }

    private func moveAfterDrag(_ translation: CGFloat) {
        guard abs(translation) > 24,
              let index = document.index(of: block.id)
        else { return }
        let direction = translation > 0 ? 1 : -1
        guard direction < 0 || index + 1 < document.blocks.count else { return }
        guard direction > 0 || index > 0 else { return }
        let destination = direction > 0 ? index + 2 : index - 1
        document.moveBlock(from: index, to: destination)
    }

    private func focusRow() {
        let isChangingFocus = document.focusedBlockID != block.id
        if block.isListBlock {
            setFocusedListItemID(firstListItemID(in: block))
            document.focusedBlockID = block.id
            document.pendingCursorOffset = isChangingFocus
                ? firstListItemText(in: block).utf16.count
                : nil
        } else {
            if !isChangingFocus {
                document.pendingCursorOffset = nil
                return
            }
            focusBlock(id: block.id, cursorAtEnd: true)
        }
    }

    private func focusBlock(id: BlockID, cursorAtEnd: Bool) {
        setFocusedListItemID(nil)
        document.focusedBlockID = id
        guard cursorAtEnd else {
            document.pendingCursorOffset = 0
            return
        }
        guard let target = document.block(for: id) else {
            document.pendingCursorOffset = 0
            return
        }
        document.pendingCursorOffset = target.textContent?.utf16.count ?? 0
    }

    private func splitBlock(id: BlockID, utf16Offset: Int) {
        guard let text = document.block(for: id)?.textContent else { return }
        let characterOffset = characterOffset(fromUTF16: utf16Offset, in: text)
        guard let newID = document.splitBlock(id: id, atOffset: characterOffset) else { return }
        setFocusedListItemID(nil)
        document.focusedBlockID = newID
        document.pendingCursorOffset = 0
    }

    private func mergePreviousBlock(id: BlockID) {
        guard let index = document.index(of: id), index > 0,
              let previousText = document.blocks[index - 1].textContent
        else { return }
        let cursorOffset = previousText.utf16.count
        guard let result = document.mergeWithPrevious(id: id) else { return }
        document.focusedBlockID = result.blockID
        document.pendingCursorOffset = cursorOffset
    }

    private func mergeNextBlock(id: BlockID) {
        guard document.mergeWithNext(id: id) else { return }
        document.focusedBlockID = id
    }

    private func moveToPreviousBlock(from id: BlockID) {
        guard let index = document.index(of: id), index > 0 else { return }
        let previous = document.blocks[index - 1]
        document.focusedBlockID = previous.id
        document.pendingCursorOffset = previous.textContent?.utf16.count ?? 0
        if previous.isListBlock {
            setFocusedListItemID(lastListItemID(in: previous))
        } else {
            setFocusedListItemID(nil)
        }
    }

    private func moveToNextBlock(from id: BlockID) {
        guard let index = document.index(of: id), index + 1 < document.blocks.count else { return }
        let next = document.blocks[index + 1]
        document.focusedBlockID = next.id
        document.pendingCursorOffset = 0
        if next.isListBlock {
            setFocusedListItemID(firstListItemID(in: next))
        } else {
            setFocusedListItemID(nil)
        }
    }

    private func removeCurrentBlockAndFocusPrevious(id: BlockID) {
        guard let removedIndex = document.removeBlock(id: id) else { return }
        guard removedIndex < document.blocks.count else { return }
        let target = document.blocks[removedIndex]
        setFocusedListItemID(nil)
        document.focusedBlockID = target.id
        document.pendingCursorOffset = target.textContent?.utf16.count ?? 0
    }

    private func firstListItemID(in block: Block) -> UUID? {
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            items.first?.id
        default:
            nil
        }
    }

    private func firstListItemText(in block: Block) -> String {
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            items.first?.text ?? ""
        default:
            ""
        }
    }

    private func lastListItemID(in block: Block) -> UUID? {
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            items.last?.id
        default:
            nil
        }
    }

    private func characterOffset(fromUTF16 offset: Int, in text: String) -> Int {
        let clamped = max(0, min(offset, text.utf16.count))
        let utf16Index = text.utf16.index(text.utf16.startIndex, offsetBy: clamped)
        let prefix = String(decoding: text.utf16[..<utf16Index], as: UTF16.self)
        return prefix.count
    }

    private func headingFont(for level: Int) -> UIFont {
        let size: CGFloat = level <= 1 ? 28 : 23
        return .systemFont(ofSize: size, weight: .bold)
    }
}
