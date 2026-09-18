import SwiftUI

/// Sheet presented when an empty block receives `/` at its beginning.
@MainActor
struct SlashCommandMenu: View {
    @Binding var isPresented: Bool
    let blockID: BlockID
    let document: BlockEditorDocument
    var onImageData: ((Data, BlockID) -> Void)? = nil
    var onImageError: ((Error, BlockID) -> Void)? = nil
    var onImagePickerLoadingChanged: ((Bool) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var didChooseCommand = false
    @State private var selectedFigureID: BlockID?

    var body: some View {
        NavigationStack {
            List {
                ForEach(BlockType.groupedByCategory, id: \.category) { group in
                    Section(group.category.displayName) {
                        ForEach(group.types, id: \.self) { type in
                            if type == .figure, onImageData != nil {
                                figurePickerRow(type)
                            } else {
                                Button {
                                    choose(type)
                                } label: {
                                    Label {
                                        Text(type.displayName)
                                    } icon: {
                                        Image(systemName: type.icon)
                                            .foregroundStyle(Color.brand600)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("插入块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        cancel()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
        .onDisappear {
            if !didChooseCommand {
                restoreSlash()
            }
        }
    }

    @ViewBuilder
    private func figurePickerRow(_ type: BlockType) -> some View {
        PhotoPickerButton(
            label: type.displayName,
            systemImage: type.icon,
            onImageData: { data in
                let figureID = prepareFigure()
                onImageData?(data, figureID)
                finishChoice()
            },
            onError: { error in
                let figureID = prepareFigure()
                onImageError?(error, figureID)
                finishChoice()
            },
            onLoadingChanged: onImagePickerLoadingChanged,
            onPickerPresented: {
                _ = prepareFigure()
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choose(_ type: BlockType) {
        let replacement = type.makeEmpty
        document.replaceBlock(id: blockID, with: replacement)
        document.focusedBlockID = replacement.id
        document.pendingCursorOffset = 0
        finishChoice()
    }

    private func prepareFigure() -> BlockID {
        if let selectedFigureID,
           let selectedBlock = document.block(for: selectedFigureID),
           case .figure = selectedBlock {
            return selectedFigureID
        }

        let replacement = BlockType.figure.makeEmpty
        if document.index(of: blockID) != nil {
            document.insertBlock(replacement, after: blockID)
            document.removeBlock(id: blockID)
        } else {
            document.blocks.append(replacement)
        }
        document.focusedBlockID = replacement.id
        document.pendingCursorOffset = nil
        selectedFigureID = replacement.id
        return replacement.id
    }

    private func finishChoice() {
        didChooseCommand = true
        isPresented = false
        dismiss()
    }

    private func cancel() {
        restoreSlash()
        isPresented = false
        dismiss()
    }

    private func restoreSlash() {
        guard document.block(for: blockID) != nil else { return }
        document.updateText(blockID: blockID, text: "/")
        document.focusedBlockID = blockID
        document.pendingCursorOffset = 1
    }
}
