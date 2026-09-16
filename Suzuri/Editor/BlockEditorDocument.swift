import Foundation
import Observation

/// The main-actor state hub for the block editor.
@Observable
@MainActor
final class BlockEditorDocument {
    var blocks: [Block]
    var focusedBlockID: BlockID? = nil
    var pendingCursorOffset: Int? = nil

    init(blocks: [Block] = [.emptyParagraph()]) {
        self.blocks = blocks.isEmpty ? [.emptyParagraph()] : blocks
    }

    // MARK: - Lookup

    func index(of blockID: BlockID) -> Int? {
        blocks.firstIndex { $0.id == blockID }
    }

    func block(for blockID: BlockID) -> Block? {
        blocks.first { $0.id == blockID }
    }

    // MARK: - Insert

    func insertBlock(_ block: Block, after blockID: BlockID) {
        guard let index = index(of: blockID) else { return }
        blocks.insert(block, at: index + 1)
    }

    func insertBlock(_ block: Block, at index: Int) {
        blocks.insert(block, at: max(0, min(index, blocks.count)))
    }

    // MARK: - Remove

    @discardableResult
    func removeBlock(id blockID: BlockID) -> Int? {
        guard let index = index(of: blockID) else { return nil }
        blocks.remove(at: index)
        ensureAtLeastOneBlock()
        return min(index, blocks.count - 1)
    }

    @discardableResult
    func removeBlocks(ids blockIDs: Set<BlockID>) -> Int? {
        guard !blockIDs.isEmpty else { return nil }
        let firstIndex = blocks.firstIndex { blockIDs.contains($0.id) } ?? 0
        blocks.removeAll { blockIDs.contains($0.id) }
        ensureAtLeastOneBlock()
        return min(firstIndex, blocks.count - 1)
    }

    // MARK: - Replace

    func replaceBlock(id blockID: BlockID, with newBlock: Block) {
        guard let index = index(of: blockID) else { return }
        blocks[index] = newBlock
    }

    // MARK: - Move

    enum MoveDirection {
        case up
        case down
    }

    func moveBlock(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0,
              source < blocks.count,
              destination >= 0,
              destination <= blocks.count
        else { return }

        let block = blocks.remove(at: source)
        let adjustedDestination = destination > source ? destination - 1 : destination
        blocks.insert(block, at: adjustedDestination)
    }

    /// Moves one contiguous selection by one position, rejecting gapped selections.
    func moveSelectedBlocks(_ blockIDs: Set<BlockID>, direction: MoveDirection) {
        guard !blockIDs.isEmpty else { return }

        let selectedIndices = blocks.indices
            .filter { blockIDs.contains(blocks[$0].id) }
            .sorted()
        guard selectedIndices.count == blockIDs.count,
              let first = selectedIndices.first,
              let last = selectedIndices.last,
              last - first + 1 == selectedIndices.count
        else { return }

        switch direction {
        case .up:
            guard first > 0 else { return }
            let above = blocks.remove(at: first - 1)
            blocks.insert(above, at: last)
        case .down:
            guard last + 1 < blocks.count else { return }
            let below = blocks.remove(at: last + 1)
            blocks.insert(below, at: first)
        }
    }

    // MARK: - Text

    func updateText(blockID: BlockID, text: String) {
        guard let index = index(of: blockID) else { return }
        blocks[index].textContent = text
    }

    // MARK: - Split

    @discardableResult
    func splitBlock(id blockID: BlockID, atOffset offset: Int) -> BlockID? {
        guard let index = index(of: blockID),
              let fullText = blocks[index].textContent
        else { return nil }

        let splitOffset = max(0, min(offset, fullText.count))
        let splitIndex = fullText.index(fullText.startIndex, offsetBy: splitOffset)
        let before = String(fullText[..<splitIndex])
        let after = String(fullText[splitIndex...])

        var current = blocks[index]
        current.textContent = before
        blocks[index] = current

        let newID = UUID()
        blocks.insert(.paragraph(id: newID, text: after), at: index + 1)
        return newID
    }

    // MARK: - Merge

    @discardableResult
    func mergeWithPrevious(id blockID: BlockID) -> (blockID: BlockID, cursorOffset: Int)? {
        guard let index = index(of: blockID), index > 0,
              let currentText = blocks[index].textContent,
              let previousText = blocks[index - 1].textContent
        else { return nil }

        let previousBlockID = blocks[index - 1].id
        let cursorOffset = previousText.count
        var previous = blocks[index - 1]
        previous.textContent = previousText + currentText
        blocks[index - 1] = previous
        blocks.remove(at: index)
        return (previousBlockID, cursorOffset)
    }

    /// Merges the next text block into the current block.
    @discardableResult
    func mergeWithNext(id blockID: BlockID) -> Bool {
        guard let index = index(of: blockID),
              index + 1 < blocks.count,
              let currentText = blocks[index].textContent,
              let nextText = blocks[index + 1].textContent
        else { return false }

        var current = blocks[index]
        current.textContent = currentText + nextText
        blocks[index] = current
        blocks.remove(at: index + 1)
        return true
    }

    // MARK: - List Items

    func addListItem(to blockID: BlockID, after itemID: UUID?) {
        guard let blockIndex = index(of: blockID) else { return }

        switch blocks[blockIndex] {
        case let .bulletList(id, items):
            blocks[blockIndex] = .bulletList(
                id: id,
                items: insertingListItem(into: items, after: itemID)
            )
        case let .numberedList(id, items):
            blocks[blockIndex] = .numberedList(
                id: id,
                items: insertingListItem(into: items, after: itemID)
            )
        default:
            break
        }
    }

    func addListItem(_ blockID: BlockID, after itemID: UUID?) {
        addListItem(to: blockID, after: itemID)
    }

    @discardableResult
    func splitListItem(
        blockID: BlockID,
        itemID: UUID,
        atOffset offset: Int
    ) -> UUID? {
        guard let blockIndex = index(of: blockID) else { return nil }

        switch blocks[blockIndex] {
        case let .bulletList(id, items):
            guard let result = splitListItem(in: items, itemID: itemID, atOffset: offset) else {
                return nil
            }
            blocks[blockIndex] = .bulletList(id: id, items: result.items)
            return result.newItemID
        case let .numberedList(id, items):
            guard let result = splitListItem(in: items, itemID: itemID, atOffset: offset) else {
                return nil
            }
            blocks[blockIndex] = .numberedList(id: id, items: result.items)
            return result.newItemID
        default:
            return nil
        }
    }

    func deleteListItem(in blockID: BlockID, at itemID: UUID) {
        guard let blockIndex = index(of: blockID) else { return }

        switch blocks[blockIndex] {
        case let .bulletList(id, items):
            replaceListAfterDeleting(
                at: blockIndex,
                id: id,
                items: items,
                itemID: itemID,
                isNumbered: false
            )
        case let .numberedList(id, items):
            replaceListAfterDeleting(
                at: blockIndex,
                id: id,
                items: items,
                itemID: itemID,
                isNumbered: true
            )
        default:
            break
        }
    }

    func deleteListItem(in blockID: BlockID, itemID: UUID) {
        deleteListItem(in: blockID, at: itemID)
    }

    // MARK: - Private Helpers

    private func ensureAtLeastOneBlock() {
        if blocks.isEmpty {
            blocks = [.emptyParagraph()]
        }
    }

    private func insertingListItem(
        into items: [ListItem],
        after itemID: UUID?
    ) -> [ListItem] {
        var updated = items
        let newItem = ListItem()
        guard let itemID,
              let itemIndex = updated.firstIndex(where: { $0.id == itemID })
        else {
            updated.append(newItem)
            return updated
        }
        updated.insert(newItem, at: itemIndex + 1)
        return updated
    }

    private func splitListItem(
        in items: [ListItem],
        itemID: UUID,
        atOffset offset: Int
    ) -> (items: [ListItem], newItemID: UUID)? {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else {
            return nil
        }

        let fullText = items[itemIndex].text
        let splitOffset = max(0, min(offset, fullText.count))
        let splitIndex = fullText.index(fullText.startIndex, offsetBy: splitOffset)
        var updated = items
        updated[itemIndex].text = String(fullText[..<splitIndex])
        let newItem = ListItem(text: String(fullText[splitIndex...]))
        updated.insert(newItem, at: itemIndex + 1)
        return (updated, newItem.id)
    }

    private func replaceListAfterDeleting(
        at blockIndex: Int,
        id: BlockID,
        items: [ListItem],
        itemID: UUID,
        isNumbered: Bool
    ) {
        guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else { return }
        var updated = items
        updated.remove(at: itemIndex)
        guard !updated.isEmpty else {
            blocks[blockIndex] = .emptyParagraph()
            return
        }
        blocks[blockIndex] = isNumbered
            ? .numberedList(id: id, items: updated)
            : .bulletList(id: id, items: updated)
    }
}
