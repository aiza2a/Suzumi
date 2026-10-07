import SwiftUI
import UIKit

private struct BlockRowFramePreferenceKey: PreferenceKey {
    static var defaultValue: [BlockID: CGRect] = [:]

    static func reduce(value: inout [BlockID: CGRect], nextValue: () -> [BlockID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct BlockDragSession {
    let blockID: BlockID
    var originY: CGFloat
    var hasMoved = false
}

/// Scrollable block-list container with focus scrolling, insertion transitions, and multi-select.
@MainActor
struct BlockEditorView: View {
    @Environment(BlockEditorDocument.self) private var document
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read-only pages keep selection chrome visible but disable every mutation path.
    var isEditable: Bool = true
    var isImageActionEnabled: Bool = true
    var uploadingFigureID: BlockID? = nil
    var onImageData: ((Data, BlockID?) -> Void)? = nil
    var onImageError: ((Error, BlockID?) -> Void)? = nil
    var onImagePickerLoadingChanged: ((Bool) -> Void)? = nil
    var onRequestImage: ((BlockID?) -> Void)? = nil
    var header: AnyView? = nil

    @State private var multiSelection = MultiBlockSelection()
    @State private var focusedListItemID: UUID?
    @State private var blockFrames: [BlockID: CGRect] = [:]
    @State private var dragSession: BlockDragSession?
    @State private var isLinkPromptVisible = false
    @State private var linkAddress = ""
    @State private var linkTitle = ""

    private var blockOrder: [BlockID] {
        document.blocks.map(\.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        if let header {
                            header.padding(.bottom, 24)
                        }
                        ForEach(document.blocks) { block in
                            BlockRowView(
                                block: block,
                                isEditable: isEditable,
                                isBlockSelected: multiSelection.selectedBlockIDs.contains(block.id),
                                isMultiSelectionActive: multiSelection.isActive,
                                isBeingDragged: dragSession?.blockID == block.id,
                                isImageActionEnabled: isImageActionEnabled,
                                uploadingFigureID: uploadingFigureID,
                                onTap: { handleTap(on: block.id) },
                                onSelectionChange: { range, _ in
                                    if range.length > 0 {
                                        dragSession = nil
                                    }
                                },
                                focusedListItemID: $focusedListItemID,
                                onImageData: onImageData,
                                onImageError: onImageError,
                                onImagePickerLoadingChanged: onImagePickerLoadingChanged,
                                onRequestImage: onRequestImage,
                                onRowDragBegan: {
                                    beginDragSession(for: block.id)
                                },
                                onRowDragChanged: { startY, locationY in
                                    handleRowDragChanged(
                                        blockID: block.id,
                                        startY: startY,
                                        locationY: locationY
                                    )
                                },
                                onRowDragEnded: { startY, locationY, entersMultiSelection in
                                    handleRowDragEnded(
                                        blockID: block.id,
                                        startY: startY,
                                        locationY: locationY,
                                        entersMultiSelection: entersMultiSelection
                                    )
                                }
                            )
                            .id(block.id)
                            .background {
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: BlockRowFramePreferenceKey.self,
                                        value: [block.id: proxy.frame(in: .global)]
                                    )
                                }
                            }
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .opacity.combined(
                                    with: .scale(scale: 0.96, anchor: .top)
                                ),
                                removal: .opacity.combined(
                                    with: .scale(scale: 0.94, anchor: .top)
                                )
                            ))
                        }
                        if isEditable {
                            Color.clear
                                .frame(height: 120)
                                .contentShape(Rectangle())
                                .onTapGesture { focusDocumentEnd() }
                                .accessibilityLabel("继续写作")
                                .accessibilityAddTraits(.isButton)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 26)
                    .padding(.top, multiSelection.isActive ? 58 : 28)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onPreferenceChange(BlockRowFramePreferenceKey.self) { frames in
                    blockFrames = frames
                }
                .onChange(of: document.focusedBlockID) { _, newID in
                    guard let newID, document.index(of: newID) != nil else { return }
                    withAnimation(reduceMotion ? nil : AppAnimation.fadeSlow) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }

            if isEditable && multiSelection.isActive {
                multiSelectionBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(reduceMotion ? .identity : .move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditable { writingToolbar }
        }
        .alert("插入链接", isPresented: $isLinkPromptVisible) {
            TextField("显示文字", text: $linkTitle)
            TextField("https://…", text: $linkAddress)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            Button("取消", role: .cancel) {}
            Button("插入") {
                guard let url = validLinkURL else { return }
                insert(.link(id: UUID(), text: linkTitle.isEmpty ? url.absoluteString : linkTitle, url: url))
            }
            .disabled(validLinkURL == nil)
        } message: {
            Text("请输入完整的 http 或 https 地址。")
        }
        .animation(reduceMotion ? nil : AppAnimation.listInsert, value: document.blocks.count)
        .animation(reduceMotion ? nil : AppAnimation.listInsert, value: blockOrder)
        .animation(reduceMotion ? nil : AppAnimation.pop, value: multiSelection.isActive)
        .onChange(of: multiSelection.isActive) { _, isActive in
            if isActive {
                dragSession = nil
            }
        }
        .onChange(of: isEditable) { _, editable in
            if !editable {
                dragSession = nil
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            dragSession = nil
        }
        .onDisappear {
            dragSession = nil
        }
    }

    private var validLinkURL: URL? {
        EditorLinkAddress.parse(linkAddress)
    }

    private var writingToolbar: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(BlockType.allCases.filter { $0 != .figure && $0 != .link }) { type in
                    Button { insert(type.makeEmpty) } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
                Button {
                    linkAddress = ""
                    linkTitle = ""
                    isLinkPromptVisible = true
                } label: { Label("链接", systemImage: "link") }
            } label: { toolIcon("plus", label: "插入内容") }

            Menu {
                ForEach(BlockType.turnIntoTypes.filter { $0 != .link }) { type in
                    Button { convertFocusedBlock(to: type) } label: {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
            } label: { toolIcon("textformat", label: "段落样式") }
            .disabled(focusedText == nil)

            if let onRequestImage {
                Button { onRequestImage(nil) } label: {
                    toolIcon("photo", label: "插入图片")
                }
                .disabled(!isImageActionEnabled)
            } else if onImageData != nil {
                PhotoPickerButton(
                    label: "插入图片", systemImage: "photo",
                    isEnabled: isImageActionEnabled,
                    onImageData: { data in onImageData?(data, nil) },
                    onError: { error in onImageError?(error, nil) },
                    onLoadingChanged: onImagePickerLoadingChanged
                )
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
            }
            Spacer(minLength: 4)
            Menu {
                Button { moveFocusedBlock(.up) } label: { Label("段落上移", systemImage: "arrow.up") }
                Button { moveFocusedBlock(.down) } label: { Label("段落下移", systemImage: "arrow.down") }
                Button {
                    if let id = document.focusedBlockID { enterMultiSelection(with: id) }
                } label: { Label("选择多个段落", systemImage: "checkmark.circle") }
                Button(role: .destructive) {
                    guard let id = document.focusedBlockID else { return }
                    let next = document.removeBlock(id: id)
                    document.focusedBlockID = next.map { document.blocks[$0].id }
                    document.pendingCursorOffset = 0
                } label: { Label("删除段落", systemImage: "trash") }
            } label: { toolIcon("ellipsis", label: "段落操作") }
            .disabled(document.focusedBlockID == nil)
            Button {
                document.focusedBlockID = nil
                document.pendingCursorOffset = nil
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            } label: { toolIcon("keyboard.chevron.compact.down", label: "收起键盘") }
        }
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(Color.brand600)
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("写作工具栏")
    }

    private func toolIcon(_ name: String, label: String) -> some View {
        Image(systemName: name)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    private var focusedText: String? {
        guard let id = document.focusedBlockID, let block = document.block(for: id) else { return nil }
        switch block {
        case let .bulletList(_, items), let .numberedList(_, items):
            return items.map(\.text).joined(separator: "\n")
        case .figure, .divider, .link:
            return nil
        default:
            return block.textContent
        }
    }

    private func convertFocusedBlock(to type: BlockType) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        guard let id = document.focusedBlockID, let text = focusedText,
              let block = document.block(for: id) else { return }
        let replacement: Block
        switch (block, type) {
        case let (.bulletList(_, items), .numberedList): replacement = .numberedList(id: id, items: items)
        case let (.numberedList(_, items), .bulletList): replacement = .bulletList(id: id, items: items)
        case (.bulletList, .bulletList), (.numberedList, .numberedList): return
        default: replacement = type.makeBlock(id: id, text: text)
        }
        document.replaceBlock(id: id, with: replacement)
        focusedListItemID = nil
        document.pendingCursorOffset = 0
    }

    private func insert(_ block: Block) {
        if let id = document.focusedBlockID {
            document.insertBlock(block, after: id)
        } else {
            document.insertBlock(block, at: document.blocks.count)
        }
        document.focusedBlockID = block.id
        document.pendingCursorOffset = 0
        focusedListItemID = nil
    }

    private func focusDocumentEnd() {
        if let last = document.blocks.last, case .paragraph = last {
            document.focusedBlockID = last.id
            document.pendingCursorOffset = last.textContent?.utf16.count ?? 0
        } else {
            insert(.emptyParagraph())
        }
    }

    private func moveFocusedBlock(_ direction: BlockEditorDocument.MoveDirection) {
        guard let id = document.focusedBlockID else { return }
        document.moveSelectedBlocks([id], direction: direction)
    }

    private var multiSelectionBar: some View {
        HStack(spacing: 6) {
            selectionButton("复制", systemImage: "doc.on.doc") {
                copySelectedBlocks()
            }
            selectionButton("删除", systemImage: "trash", role: .destructive) {
                deleteSelectedBlocks()
            }
            Divider()
                .frame(height: 20)
            selectionButton("上移", systemImage: "chevron.up") {
                document.moveSelectedBlocks(
                    multiSelection.selectedBlockIDs,
                    direction: .up
                )
            }
            .disabled(!isSelectionContiguous)
            selectionButton("下移", systemImage: "chevron.down") {
                document.moveSelectedBlocks(
                    multiSelection.selectedBlockIDs,
                    direction: .down
                )
            }
            .disabled(!isSelectionContiguous)
            Divider()
                .frame(height: 20)
            Button("完成") {
                multiSelection.clear()
                document.focusedBlockID = nil
                document.pendingCursorOffset = nil
                focusedListItemID = nil
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.brand600)
            .buttonStyle(.plain)
            .keyboardShortcut(.escape)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .appGlass(cornerRadius: 20, brandTint: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("多选操作")
    }

    private func selectionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.brand600)
        .accessibilityLabel(title)
    }

    private var isSelectionContiguous: Bool {
        let selectedIndices = document.blocks.indices.filter {
            multiSelection.selectedBlockIDs.contains(document.blocks[$0].id)
        }
        guard let first = selectedIndices.first,
              let last = selectedIndices.last,
              selectedIndices.count == multiSelection.selectedBlockIDs.count
        else { return false }
        return last - first + 1 == selectedIndices.count
    }

    private func handleTap(on blockID: BlockID) {
        guard isEditable else { return }
        guard multiSelection.isActive else {
            return
        }
        document.focusedBlockID = nil
        document.pendingCursorOffset = nil
        multiSelection.toggle(blockID)
    }

    private func enterMultiSelection(with blockID: BlockID) {
        guard isEditable, dragSession == nil else { return }
        document.focusedBlockID = nil
        document.pendingCursorOffset = nil
        focusedListItemID = nil
        if multiSelection.isActive {
            multiSelection.selectedBlockIDs.insert(blockID)
            multiSelection.anchorID = multiSelection.anchorID ?? blockID
        } else {
            multiSelection.selectedBlockIDs = [blockID]
            multiSelection.anchorID = blockID
        }
    }

    private func handleRowDragChanged(
        blockID: BlockID,
        startY: CGFloat,
        locationY: CGFloat
    ) {
        guard isEditable, !multiSelection.isActive else {
            dragSession = nil
            return
        }
        if dragSession == nil {
            beginDragSession(for: blockID, originY: startY)
        }
        updateDragSession(for: blockID, startY: startY, locationY: locationY)
    }

    private func handleRowDragEnded(
        blockID: BlockID,
        startY: CGFloat?,
        locationY: CGFloat?,
        entersMultiSelection: Bool
    ) {
        if let startY, let locationY {
            updateDragSession(for: blockID, startY: startY, locationY: locationY)
        }
        finishDragSession(
            for: blockID,
            entersMultiSelection: entersMultiSelection
        )
    }

    private func beginDragSession(for blockID: BlockID, originY: CGFloat? = nil) {
        guard isEditable,
              !multiSelection.isActive,
              dragSession == nil,
              document.index(of: blockID) != nil
        else { return }

        document.focusedBlockID = nil
        document.pendingCursorOffset = nil
        focusedListItemID = nil
        dragSession = BlockDragSession(
            blockID: blockID,
            originY: originY ?? blockFrames[blockID]?.midY ?? 0
        )

        let feedback = UIImpactFeedbackGenerator(style: .medium)
        feedback.prepare()
        feedback.impactOccurred()
    }

    private func updateDragSession(
        for blockID: BlockID,
        startY: CGFloat,
        locationY: CGFloat
    ) {
        guard isEditable,
              !multiSelection.isActive,
              var session = dragSession,
              session.blockID == blockID
        else { return }

        if !session.hasMoved {
            session.originY = startY
        }
        session.hasMoved = session.hasMoved || abs(locationY - session.originY) >= 10
        dragSession = session
        guard session.hasMoved else { return }
        moveDraggedBlock(blockID: blockID, locationY: locationY)
    }

    private func finishDragSession(for blockID: BlockID, entersMultiSelection: Bool) {
        guard let session = dragSession, session.blockID == blockID else { return }
        dragSession = nil

        if entersMultiSelection,
           !session.hasMoved,
           isEditable,
           !multiSelection.isActive {
            enterMultiSelection(with: blockID)
        }
    }

    private func moveDraggedBlock(blockID: BlockID, locationY: CGFloat) {
        guard let sourceIndex = document.index(of: blockID),
              document.blocks.allSatisfy({ $0.id == blockID || blockFrames[$0.id] != nil })
        else { return }

        let destination = document.blocks.enumerated().first { _, candidate in
            candidate.id != blockID && locationY < (blockFrames[candidate.id]?.midY ?? .greatestFiniteMagnitude)
        }?.offset ?? document.blocks.count

        guard destination != sourceIndex,
              destination != sourceIndex + 1
        else { return }

        withAnimation(reduceMotion ? nil : AppAnimation.listInsert) {
            document.moveBlock(from: sourceIndex, to: destination)
        }
    }

    private func copySelectedBlocks() {
        let selected = document.blocks.filter {
            multiSelection.selectedBlockIDs.contains($0.id)
        }
        let copiedText = selected.map(plainText(for:)).joined(separator: "\n\n")
        UIPasteboard.general.string = copiedText
    }

    private func deleteSelectedBlocks() {
        guard isEditable else { return }
        let selectedIDs = multiSelection.selectedBlockIDs
        multiSelection.clear()
        focusedListItemID = nil
        document.focusedBlockID = nil
        document.pendingCursorOffset = nil
        guard let fallbackIndex = document.removeBlocks(ids: selectedIDs),
              fallbackIndex < document.blocks.count
        else { return }
        document.focusedBlockID = document.blocks[fallbackIndex].id
        document.pendingCursorOffset = 0
    }

    private func plainText(for block: Block) -> String {
        switch block {
        case let .paragraph(_, text),
             let .heading(_, _, text),
             let .quote(_, text),
             let .code(_, text),
             let .link(_, text, _):
            text
        case let .bulletList(_, items), let .numberedList(_, items):
            items.map(\.text).joined(separator: "\n")
        case .divider:
            "---"
        case let .figure(_, _, caption):
            caption
        }
    }
}
