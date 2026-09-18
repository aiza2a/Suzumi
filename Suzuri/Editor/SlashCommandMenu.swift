import SwiftUI

/// Sheet presented when an empty block receives `/` at its beginning.
@MainActor
struct SlashCommandMenu: View {
    @Binding var isPresented: Bool
    let blockID: BlockID
    let document: BlockEditorDocument
    var isImageActionEnabled = true
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
            guard !didChooseCommand else { return }
            if selectedFigureID != nil {
                finalizeFigureChoice(dismissMenu: false)
            } else {
                restoreSlash()
            }
        }
    }

    @ViewBuilder
    private func figurePickerRow(_ type: BlockType) -> some View {
        PhotoPickerButton(
            label: type.displayName,
            systemImage: type.icon,
            isEnabled: isImageActionEnabled,
            onImageData: { data in
                guard let figureID = figureIDForCallback() else { return }
                onImageData?(data, figureID)
                finalizeFigureChoice(dismissMenu: true)
            },
            onError: { error in
                guard let figureID = figureIDForCallback() else { return }
                onImageError?(error, figureID)
                finalizeFigureChoice(dismissMenu: true)
            },
            onLoadingChanged: { isLoading in
                onImagePickerLoadingChanged?(isLoading)
            },
            onPickerPresented: {
                guard isImageActionEnabled else { return }
                _ = prepareFigure()
            }
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func choose(_ type: BlockType) {
        discardPreparedFigure()
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

        let figure = BlockType.figure.makeEmpty
        if document.index(of: blockID) != nil {
            // Keep the slash presenter alive until the picker has completed.
            document.insertBlock(figure, after: blockID)
        } else {
            document.blocks.append(figure)
        }
        document.focusedBlockID = figure.id
        document.pendingCursorOffset = nil
        selectedFigureID = figure.id
        return figure.id
    }

    private func figureIDForCallback() -> BlockID? {
        if let selectedFigureID {
            return selectedFigureID
        }
        guard isImageActionEnabled else { return nil }
        return prepareFigure()
    }

    private func discardPreparedFigure() {
        guard let selectedFigureID else { return }
        document.removeBlock(id: selectedFigureID)
        self.selectedFigureID = nil
    }

    private func finalizeFigureChoice(dismissMenu: Bool) {
        guard selectedFigureID != nil else { return }
        if document.block(for: blockID) != nil {
            document.removeBlock(id: blockID)
        }
        didChooseCommand = true
        if dismissMenu {
            isPresented = false
            dismiss()
        }
    }

    private func finishChoice() {
        didChooseCommand = true
        isPresented = false
        dismiss()
    }

    private func cancel() {
        if selectedFigureID != nil {
            finalizeFigureChoice(dismissMenu: true)
        } else {
            restoreSlash()
            finishChoice()
        }
    }

    private func restoreSlash() {
        guard document.block(for: blockID) != nil else { return }
        document.updateText(blockID: blockID, text: "/")
        document.focusedBlockID = blockID
        document.pendingCursorOffset = 1
    }
}
