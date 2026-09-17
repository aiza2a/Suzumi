import Foundation
import Observation

/// Tracks the IDs selected by the block editor's multi-selection mode.
@Observable
@MainActor
final class MultiBlockSelection {
    var selectedBlockIDs: Set<BlockID> = []
    var anchorID: BlockID?

    /// Multi-selection is active as soon as at least one block is selected.
    var isActive: Bool {
        !selectedBlockIDs.isEmpty
    }

    /// Compatibility spelling used by the original Logue implementation.
    var anchorBlockID: BlockID? {
        get { anchorID }
        set { anchorID = newValue }
    }

    func clear() {
        selectedBlockIDs.removeAll()
        anchorID = nil
    }

    func select(_ blockID: BlockID) {
        selectedBlockIDs = [blockID]
        anchorID = blockID
    }

    func toggle(_ blockID: BlockID) {
        if selectedBlockIDs.contains(blockID) {
            selectedBlockIDs.remove(blockID)
            if selectedBlockIDs.isEmpty {
                anchorID = nil
            }
        } else {
            selectedBlockIDs.insert(blockID)
            anchorID = anchorID ?? blockID
        }
    }

    /// Selects every block between two document indices, inclusive.
    func selectRange(from startIndex: Int, to endIndex: Int, in blocks: [Block]) {
        let lowerBound = min(startIndex, endIndex)
        let upperBound = max(startIndex, endIndex)
        guard lowerBound >= 0,
              upperBound < blocks.count
        else { return }

        selectedBlockIDs = Set(blocks[lowerBound ... upperBound].map(\.id))
    }

    /// Selects every block between two IDs, inclusive.
    func selectRange(from startID: BlockID, to endID: BlockID, in blocks: [Block]) {
        guard let startIndex = blocks.firstIndex(where: { $0.id == startID }),
              let endIndex = blocks.firstIndex(where: { $0.id == endID })
        else { return }
        selectRange(from: startIndex, to: endIndex, in: blocks)
    }

    func selectAll(blocks: [Block]) {
        selectedBlockIDs = Set(blocks.map(\.id))
        anchorID = blocks.first?.id
    }
}

/// Name retained for callers that used the reference implementation's type.
typealias MultiBlockSelectionState = MultiBlockSelection
