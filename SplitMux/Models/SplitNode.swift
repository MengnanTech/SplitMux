import Foundation

/// Recursive tree structure for split pane layouts.
/// Each leaf is a tab ID; internal nodes are horizontal or vertical splits.
indirect enum SplitNode: Equatable {
    case tab(UUID)
    case horizontal(SplitNode, SplitNode, ratio: Double) // left | right
    case vertical(SplitNode, SplitNode, ratio: Double)   // top / bottom

    /// All tab IDs in this subtree
    var tabIDs: [UUID] {
        switch self {
        case .tab(let id): return [id]
        case .horizontal(let a, let b, _), .vertical(let a, let b, _):
            return a.tabIDs + b.tabIDs
        }
    }

    /// Replace a leaf tab with a split containing that tab + a new tab
    func insertSplit(at targetID: UUID, newTabID: UUID, direction: SplitDirection) -> SplitNode {
        switch self {
        case .tab(let id) where id == targetID:
            let existing = SplitNode.tab(targetID)
            let new = SplitNode.tab(newTabID)
            switch direction {
            case .right: return .horizontal(existing, new, ratio: 0.5)
            case .left: return .horizontal(new, existing, ratio: 0.5)
            case .down: return .vertical(existing, new, ratio: 0.5)
            case .up: return .vertical(new, existing, ratio: 0.5)
            }

        case .horizontal(let a, let b, let ratio):
            return .horizontal(
                a.insertSplit(at: targetID, newTabID: newTabID, direction: direction),
                b.insertSplit(at: targetID, newTabID: newTabID, direction: direction),
                ratio: ratio
            )

        case .vertical(let a, let b, let ratio):
            return .vertical(
                a.insertSplit(at: targetID, newTabID: newTabID, direction: direction),
                b.insertSplit(at: targetID, newTabID: newTabID, direction: direction),
                ratio: ratio
            )

        default:
            return self
        }
    }

    /// Remove a tab from the tree; collapses parent split if only one child remains
    func removing(tabID: UUID) -> SplitNode? {
        switch self {
        case .tab(let id):
            return id == tabID ? nil : self

        case .horizontal(let a, let b, let ratio):
            let newA = a.removing(tabID: tabID)
            let newB = b.removing(tabID: tabID)
            if let newA, let newB { return .horizontal(newA, newB, ratio: ratio) }
            return newA ?? newB

        case .vertical(let a, let b, let ratio):
            let newA = a.removing(tabID: tabID)
            let newB = b.removing(tabID: tabID)
            if let newA, let newB { return .vertical(newA, newB, ratio: ratio) }
            return newA ?? newB
        }
    }

    /// Find the sibling tab closest to the given tab in the split tree.
    /// Returns the first tab ID from the other branch of the nearest parent split.
    func siblingTabID(of tabID: UUID) -> UUID? {
        switch self {
        case .tab:
            return nil
        case .horizontal(let a, let b, _), .vertical(let a, let b, _):
            // If target is directly in one branch, return the nearest tab from the other
            if a.tabIDs.contains(tabID) {
                if case .tab(let id) = a, id == tabID {
                    return b.tabIDs.first
                }
                return a.siblingTabID(of: tabID)
            }
            if b.tabIDs.contains(tabID) {
                if case .tab(let id) = b, id == tabID {
                    return a.tabIDs.first
                }
                return b.siblingTabID(of: tabID)
            }
            return nil
        }
    }

    /// Update the split ratio at a given path
    func updatingRatio(at path: [SplitPath], newRatio: Double) -> SplitNode {
        guard let first = path.first else {
            switch self {
            case .horizontal(let a, let b, _):
                return .horizontal(a, b, ratio: newRatio)
            case .vertical(let a, let b, _):
                return .vertical(a, b, ratio: newRatio)
            default:
                return self
            }
        }
        switch self {
        case .horizontal(let a, let b, let ratio):
            if first == .first {
                return .horizontal(a.updatingRatio(at: Array(path.dropFirst()), newRatio: newRatio), b, ratio: ratio)
            } else {
                return .horizontal(a, b.updatingRatio(at: Array(path.dropFirst()), newRatio: newRatio), ratio: ratio)
            }
        case .vertical(let a, let b, let ratio):
            if first == .first {
                return .vertical(a.updatingRatio(at: Array(path.dropFirst()), newRatio: newRatio), b, ratio: ratio)
            } else {
                return .vertical(a, b.updatingRatio(at: Array(path.dropFirst()), newRatio: newRatio), ratio: ratio)
            }
        default:
            return self
        }
    }
}

enum SplitDirection: String, CaseIterable {
    case right, left, down, up

    var label: String {
        switch self {
        case .right: return "Split Right"
        case .left: return "Split Left"
        case .down: return "Split Down"
        case .up: return "Split Up"
        }
    }

    var icon: String {
        switch self {
        case .right: return "rectangle.split.2x1"
        case .left: return "rectangle.split.2x1"
        case .down: return "rectangle.split.1x2"
        case .up: return "rectangle.split.1x2"
        }
    }
}

enum SplitPath: Equatable {
    case first
    case second
}
