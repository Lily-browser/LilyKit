import Foundation

/// The ways the content area can be divided between tabs.
public enum SplitLayout: String, CaseIterable, Codable, Sendable {
    case twoColumns, twoRows, threeColumns, threeRows, grid

    public var paneCount: Int {
        switch self {
        case .twoColumns, .twoRows: return 2
        case .threeColumns, .threeRows: return 3
        case .grid: return 4
        }
    }

    /// Layout after one pane closes (nil: the split ends).
    public var shrunk: SplitLayout? {
        switch self {
        case .twoColumns, .twoRows: return nil
        case .threeColumns: return .twoColumns
        case .threeRows: return .twoRows
        case .grid: return .threeColumns
        }
    }

    /// Layout after adding a pane (nil: already four).
    public var grown: SplitLayout? {
        switch self {
        case .twoColumns: return .threeColumns
        case .twoRows: return .threeRows
        case .threeColumns, .threeRows: return .grid
        case .grid: return nil
        }
    }
}

/// Tabs shown together, in pane order.
public struct SplitGroup: Equatable, Sendable {
    public var layout: SplitLayout
    public var tabIDs: [UUID]
    /// Link Scrolling: scrolling one pane scrolls the others to the same place.
    public var scrollLinked: Bool

    public init(layout: SplitLayout, tabIDs: [UUID], scrollLinked: Bool = false) {
        self.layout = layout; self.tabIDs = tabIDs; self.scrollLinked = scrollLinked
    }

    /// Drops a closed tab, shrinking the layout; nil when fewer than two tabs remain.
    public func removing(_ id: UUID) -> SplitGroup? {
        var group = self
        group.tabIDs.removeAll { $0 == id }
        while group.tabIDs.count < group.layout.paneCount {
            guard let smaller = group.layout.shrunk else { return nil }
            group.layout = smaller
        }
        return group
    }

    /// The layout shrunk until it has exactly one pane per tab; nil when that's impossible (fewer
    /// than two tabs, or more tabs than the layout holds).
    public func fitted() -> SplitGroup? {
        var group = self
        while group.tabIDs.count < group.layout.paneCount {
            guard let smaller = group.layout.shrunk else { return nil }
            group.layout = smaller
        }
        return group.tabIDs.count == group.layout.paneCount && group.tabIDs.count >= 2 ? group : nil
    }

    public func adding(_ id: UUID) -> SplitGroup? {
        guard !tabIDs.contains(id), let bigger = layout.grown else { return nil }
        var group = self
        group.layout = bigger
        group.tabIDs.append(id)
        return group
    }
}
