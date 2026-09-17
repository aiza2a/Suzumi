import SwiftUI

/// Sheet presented when an empty block receives `/` at its beginning.
struct SlashCommandMenu: View {
    @Binding var isPresented: Bool
    let blockID: BlockID
    let document: BlockEditorDocument

    @Environment(\.dismiss) private var dismiss
    @State private var didChooseCommand = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(BlockType.groupedByCategory, id: \.category) { group in
                    Section(group.category.rawValue) {
                        ForEach(group.types, id: \.self) { type in
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

    private func choose(_ type: BlockType) {
        let replacement = type.makeEmpty
        document.replaceBlock(id: blockID, with: replacement)
        document.focusedBlockID = replacement.id
        document.pendingCursorOffset = 0
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
