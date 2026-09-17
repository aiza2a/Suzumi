import SwiftUI
import UIKit

/// Scrollable block-list container with focus scrolling, insertion transitions, and multi-select.
@MainActor
struct BlockEditorView: View {
    @Environment(BlockEditorDocument.self) private var document
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var multiSelection = MultiBlockSelection()
    @State private var focusedListItemID: UUID?
    @State private var isTextSelectionToolbarVisible = false

    var body: some View {
        ZStack(alignment: .top) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(document.blocks) { block in
                            BlockRowView(
                                block: block,
                                isBlockSelected: multiSelection.selectedBlockIDs.contains(block.id),
                                isMultiSelectionActive: multiSelection.isActive,
                                onTap: { handleTap(on: block.id) },
                                onSelectionChange: { range, _ in
                                    isTextSelectionToolbarVisible = range.length > 0
                                        && !multiSelection.isActive
                                },
                                focusedListItemID: $focusedListItemID
                            )
                            .id(block.id)
                            .transition(reduceMotion ? .identity : .asymmetric(
                                insertion: .opacity.combined(
                                    with: .scale(scale: 0.96, anchor: .top)
                                ),
                                removal: .opacity.combined(
                                    with: .scale(scale: 0.94, anchor: .top)
                                )
                            ))
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.4)
                                    .onEnded { _ in enterMultiSelection(with: block.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, multiSelection.isActive ? 58 : 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: document.focusedBlockID) { _, newID in
                    guard let newID, document.index(of: newID) != nil else { return }
                    withAnimation(reduceMotion ? nil : AppAnimation.fadeSlow) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                }
            }

            if multiSelection.isActive {
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
        .animation(reduceMotion ? nil : AppAnimation.pop, value: multiSelection.isActive)
        .onChange(of: multiSelection.isActive) { _, isActive in
            if isActive {
                isTextSelectionToolbarVisible = false
            }
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
        document.focusedBlockID = nil
        document.pendingCursorOffset = nil
        if multiSelection.isActive {
            multiSelection.selectedBlockIDs.insert(blockID)
            multiSelection.anchorID = multiSelection.anchorID ?? blockID
        } else {
            multiSelection.selectedBlockIDs = [blockID]
            multiSelection.anchorID = blockID
        }
        isTextSelectionToolbarVisible = false
    }

    private func copySelectedBlocks() {
        let selected = document.blocks.filter {
            multiSelection.selectedBlockIDs.contains($0.id)
        }
        let copiedText = selected.map(plainText(for:)).joined(separator: "\n\n")
        UIPasteboard.general.string = copiedText
    }

    private func deleteSelectedBlocks() {
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
