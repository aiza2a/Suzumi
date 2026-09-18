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
    var uploadingFigureID: BlockID? = nil
    var onImageData: ((Data, BlockID?) -> Void)? = nil
    var onImageError: ((Error, BlockID?) -> Void)? = nil
    var onImagePickerLoadingChanged: ((Bool) -> Void)? = nil

    @State private var multiSelection = MultiBlockSelection()
    @State private var focusedListItemID: UUID?
    @State private var isTextSelectionToolbarVisible = false
    @State private var blockFrames: [BlockID: CGRect] = [:]
    @State private var dragSession: BlockDragSession?

    private var blockOrder: [BlockID] {
        document.blocks.map(\.id)
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(document.blocks) { block in
                            BlockRowView(
                                block: block,
                                isEditable: isEditable,
                                isBlockSelected: multiSelection.selectedBlockIDs.contains(block.id),
                                isMultiSelectionActive: multiSelection.isActive,
                                isBeingDragged: dragSession?.blockID == block.id,
                                uploadingFigureID: uploadingFigureID,
                                onTap: { handleTap(on: block.id) },
                                onSelectionChange: { range, _ in
                                    isTextSelectionToolbarVisible = range.length > 0
                                        && !multiSelection.isActive
                                },
                                focusedListItemID: $focusedListItemID,
                                onImageData: onImageData,
                                onImageError: onImageError,
                                onImagePickerLoadingChanged: onImagePickerLoadingChanged,
                                onHandleDragChanged: { startY, locationY in
                                    handleHandleDragChanged(
                                        blockID: block.id,
                                        startY: startY,
                                        locationY: locationY
                                    )
                                },
                                onHandleDragEnded: { startY, locationY in
                                    handleHandleDragEnded(
                                        blockID: block.id,
                                        startY: startY,
                                        locationY: locationY
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
                            .simultaneousGesture(reorderGesture(for: block.id))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, multiSelection.isActive ? 58 : 16)
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
            } else if isTextSelectionToolbarVisible {
                SelectionToolbar(
                    isVisible: true,
                    onDismiss: { isTextSelectionToolbarVisible = false }
                )
                .padding(.top, 8)
                .transition(reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.94, anchor: .bottom)))
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : AppAnimation.listInsert, value: document.blocks.count)
        .animation(reduceMotion ? nil : AppAnimation.listInsert, value: blockOrder)
        .animation(reduceMotion ? nil : AppAnimation.pop, value: multiSelection.isActive)
        .onChange(of: multiSelection.isActive) { _, isActive in
            if isActive {
                dragSession = nil
                isTextSelectionToolbarVisible = false
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

    private var multiSelectionBar: some View {
        HStack(spacing: 14) {
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
                .frame(width: 24, height: 24)
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
            isTextSelectionToolbarVisible = false
            return
        }
        document.focusedBlockID = nil
        document.pendingCursorOffset = nil
        multiSelection.toggle(blockID)
        if !multiSelection.isActive {
            isTextSelectionToolbarVisible = false
        }
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
        isTextSelectionToolbarVisible = false
    }

    private func reorderGesture(for blockID: BlockID) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 8, coordinateSpace: .global))
            .onChanged { value in
                guard isEditable else {
                    dragSession = nil
                    return
                }
                guard !multiSelection.isActive else {
                    dragSession = nil
                    return
                }

                switch value {
                case .first(true):
                    beginDragSession(for: blockID)
                case .first(false):
                    finishDragSession(for: blockID, entersMultiSelection: false)
                case let .second(_, drag):
                    if dragSession == nil {
                        beginDragSession(for: blockID, originY: drag.startLocation.y)
                    }
                    updateDragSession(
                        for: blockID,
                        startY: drag.startLocation.y,
                        locationY: drag.location.y
                    )
                }
            }
            .onEnded { value in
                switch value {
                case .first(true):
                    finishDragSession(for: blockID, entersMultiSelection: true)
                case .first(false):
                    finishDragSession(for: blockID, entersMultiSelection: false)
                case let .second(_, drag):
                    updateDragSession(
                        for: blockID,
                        startY: drag.startLocation.y,
                        locationY: drag.location.y
                    )
                    finishDragSession(for: blockID, entersMultiSelection: true)
                }
            }
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

    private func handleHandleDragChanged(
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

    private func handleHandleDragEnded(
        blockID: BlockID,
        startY: CGFloat,
        locationY: CGFloat
    ) {
        updateDragSession(for: blockID, startY: startY, locationY: locationY)
        finishDragSession(for: blockID, entersMultiSelection: false)
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
