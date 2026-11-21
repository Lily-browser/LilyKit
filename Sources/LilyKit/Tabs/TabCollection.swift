import Foundation

/// Which tab takes over when the active one closes.
public enum AfterClose: String, CaseIterable, Sendable {
    /// The most recently used remaining tab in the space.
    case lastUsed
    /// The tab below it in the space's list (the one above when it was last).
    case below
    /// The tab above it (the one below when it was first).
    case above

    public static let `default` = AfterClose.lastUsed
    public init(stored: String?) { self = stored.flatMap(AfterClose.init(rawValue:)) ?? .default }
}

/// A tab that was closed and can be reopened.
public struct ClosedTab: Equatable, Sendable {
    public var url: URL
    public var pinned: Bool
    public var index: Int
    public var spaceID: UUID
}

/// The platform-neutral state and rules of one window's tabs: spaces, order, selection, splits and
/// recently closed tabs. A plain value type with no web views, timers or callbacks, so the Mac and
/// iOS apps share it and the rules are testable without UI. Apps own the web views and react to
/// what changed by comparing before and after, or from the values the mutating calls return.
///
/// Pinned tabs always sort before unpinned ones. Every space always exists and every tab belongs to one.
public struct TabCollection: Equatable, Sendable {
    public private(set) var spaces: [Space]
    public private(set) var tabs: [TabModel] = []
    public private(set) var activeID: UUID?
    public private(set) var currentSpaceID: UUID
    public private(set) var splits: [SplitGroup] = []
    public private(set) var recentlyClosed: [ClosedTab] = []
    /// Last active tab per space, restored when switching back.
    private var lastActive: [UUID: UUID] = [:]
    public static let maxRecentlyClosed = 25

    public init(spaces: [Space] = Space.defaults) {
        precondition(!spaces.isEmpty, "a TabCollection needs at least one space")
        self.spaces = spaces
        currentSpaceID = spaces[0].id
    }

    // MARK: Reading

    public var currentSpace: Space { spaces.first { $0.id == currentSpaceID } ?? spaces[0] }
    public var visibleTabs: [TabModel] { tabs.filter { $0.spaceID == currentSpaceID } }
    public var active: TabModel? { activeID.flatMap(tab) }
    public func tab(_ id: UUID) -> TabModel? { tabs.first { $0.id == id } }
    public func index(of id: UUID) -> Int? { tabs.firstIndex { $0.id == id } }
    public func tabs(in space: UUID) -> [TabModel] { tabs.filter { $0.spaceID == space } }

    public func splitGroup(containing id: UUID) -> SplitGroup? { splits.first { $0.tabIDs.contains(id) } }
    /// The split the active tab is in, which is the one on screen.
    public var split: SplitGroup? { activeID.flatMap(splitGroup(containing:)) }

    private var pinnedEnd: Int { tabs.lastIndex(where: \.isPinned).map { $0 + 1 } ?? 0 }
    private func mostRecent(in space: UUID) -> UUID? { tabs.filter { $0.spaceID == space }.max { $0.lastActivated < $1.lastActivated }?.id }

    // MARK: Tabs

    /// Adds a tab to the current space. Pinned tabs go after the other pinned ones; with `nextToActive`
    /// an unpinned tab goes right after an unpinned active tab; otherwise at the end.
    @discardableResult
    public mutating func create(url: URL?, title: String = "", activate: Bool = true, pinned: Bool = false, nextToActive: Bool = false,
                                now: Date = Date()) -> TabModel {
        let tab = TabModel(spaceID: currentSpaceID, url: url, title: title, isPinned: pinned, lastActivated: now)
        insert(tab, pinned: pinned, nextToActive: nextToActive)
        if activate || activeID == nil { setActive(tab.id, now: now) }
        return tab
    }

    /// Imported or restored tabs: added to `space`, asleep until first used, without switching to them.
    @discardableResult
    public mutating func createAsleep(url: URL, title: String, pinned: Bool, in space: UUID, now: Date = Date()) -> TabModel {
        let space = spaces.contains { $0.id == space } ? space : spaces[0].id
        let tab = TabModel(spaceID: space, url: url, title: title.isEmpty ? (url.host ?? url.absoluteString) : title,
                           isPinned: pinned, isSleeping: true, lastActivated: now)
        tabs.insert(tab, at: pinned ? pinnedEnd : tabs.count)
        return tab
    }

    private mutating func insert(_ tab: TabModel, pinned: Bool, nextToActive: Bool) {
        let at: Int
        if pinned { at = pinnedEnd }
        else if nextToActive, let active, !active.isPinned, let i = index(of: active.id) { at = i + 1 }
        else { at = tabs.count }
        tabs.insert(tab, at: at)
    }

    /// A copy of a tab (same page and title) right after it, selected. Nil if the tab doesn't exist.
    @discardableResult
    public mutating func duplicate(_ id: UUID, now: Date = Date()) -> TabModel? {
        guard let i = index(of: id) else { return nil }
        let copy = TabModel(spaceID: tabs[i].spaceID, url: tabs[i].url, title: tabs[i].title, isPinned: false, lastActivated: now)
        tabs.insert(copy, at: tabs[i].isPinned ? pinnedEnd : i + 1)
        activate(copy.id, now: now)
        return copy
    }

    /// Updates a tab's page state (called as the page navigates).
    public mutating func update(_ id: UUID, _ change: (inout TabModel) -> Void) {
        guard let i = index(of: id) else { return }
        change(&tabs[i])
    }

    /// Closes a tab and selects the next one per `then`. Returns the removed tab.
    /// With `keepSpaceNonEmpty`, closing a space's last tab leaves a fresh blank one (iOS); otherwise the
    /// space may end up empty (Mac). With `remember: false` (private tabs) it never appears in Reopen Closed Tab.
    @discardableResult
    public mutating func close(_ id: UUID, then: AfterClose = .default, keepSpaceNonEmpty: Bool = false, remember: Bool = true,
                               now: Date = Date()) -> TabModel? {
        guard let index = index(of: id) else { return nil }
        let wasActive = activeID == id
        let mode = wasActive ? then : .lastUsed
        let space = tabs[index].spaceID
        var above: UUID?, below: UUID?
        if wasActive, mode != .lastUsed {
            above = tabs[..<index].last { $0.spaceID == space }?.id
            below = tabs[(index + 1)...].first { $0.spaceID == space }?.id
        }
        leaveSplit(id)
        let tab = tabs.remove(at: index)
        if remember, let url = tab.url, url.scheme != "about" {
            recentlyClosed.append(ClosedTab(url: url, pinned: tab.isPinned, index: index, spaceID: tab.spaceID))
            if recentlyClosed.count > Self.maxRecentlyClosed { recentlyClosed.removeFirst() }
        }
        if keepSpaceNonEmpty, !tabs.contains(where: { $0.spaceID == space }) {
            tabs.append(TabModel(spaceID: space, lastActivated: now))
        }
        if wasActive {
            let next: UUID?
            switch mode {
            case .lastUsed: next = nil
            case .below: next = below ?? above
            case .above: next = above ?? below
            }
            setActive(next ?? mostRecent(in: space) ?? mostRecent(in: currentSpaceID), now: now)
        }
        return tab
    }

    /// Brings back the most recently closed tab where it was. Returns it, or nil when none.
    @discardableResult
    public mutating func reopenClosed(now: Date = Date()) -> TabModel? {
        guard let closed = recentlyClosed.popLast() else { return nil }
        if spaces.contains(where: { $0.id == closed.spaceID }) && closed.spaceID != currentSpaceID { switchSpace(to: closed.spaceID, now: now) }
        let tab = create(url: closed.url, activate: true, pinned: closed.pinned, now: now)
        move(tab.id, to: closed.index)
        return tab
    }

    public mutating func clearRecentlyClosed() { recentlyClosed.removeAll() }

    /// Activating a tab from another space switches to that space.
    public mutating func activate(_ id: UUID, now: Date = Date()) {
        guard let tab = tab(id) else { return }
        if tab.spaceID != currentSpaceID {
            lastActive[currentSpaceID] = activeID
            currentSpaceID = tab.spaceID
        }
        setActive(id, now: now)
    }

    /// ⌘1–⌘8 pick the nth tab of the space, ⌘9 the last one (`number` is 1-based).
    public mutating func activate(number: Int, now: Date = Date()) {
        let visible = visibleTabs
        guard !visible.isEmpty, number >= 1 else { return }
        setActive((number >= 9 ? visible.last! : visible[min(number, visible.count) - 1]).id, now: now)
    }

    public mutating func cycle(by offset: Int, now: Date = Date()) {
        let visible = visibleTabs
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == activeID } ?? 0
        setActive(visible[(current + offset % visible.count + visible.count) % visible.count].id, now: now)
    }

    private mutating func setActive(_ id: UUID?, now: Date) {
        activeID = id
        guard let id, let i = index(of: id) else { return }
        tabs[i].lastActivated = now
        tabs[i].isSleeping = false
        lastActive[tabs[i].spaceID] = id
    }

    public mutating func setPinned(_ id: UUID, _ pinned: Bool) {
        guard let i = index(of: id), tabs[i].isPinned != pinned else { return }
        var tab = tabs.remove(at: i)
        tab.isPinned = pinned
        tabs.insert(tab, at: pinnedEnd)
    }

    /// Moves within the tab's own section (pinned / unpinned); the index is clamped.
    public mutating func move(_ id: UUID, to requested: Int) {
        guard let from = index(of: id) else { return }
        let tab = tabs.remove(at: from)
        let pinnedCount = tabs.filter(\.isPinned).count
        let range = tab.isPinned ? 0...pinnedCount : pinnedCount...tabs.count
        tabs.insert(tab, at: min(max(requested, range.lowerBound), range.upperBound))
    }

    public mutating func closeAll() {
        tabs.removeAll(); splits.removeAll(); activeID = nil
    }

    // MARK: Spaces

    public mutating func switchSpace(to id: UUID, now: Date = Date()) {
        guard id != currentSpaceID, spaces.contains(where: { $0.id == id }) else { return }
        lastActive[currentSpaceID] = activeID
        currentSpaceID = id
        let remembered = lastActive[id].flatMap(tab).flatMap { $0.spaceID == id ? $0.id : nil }
        setActive(remembered ?? mostRecent(in: id), now: now)
    }

    /// Next/previous space, wrapping around.
    public mutating func switchSpace(by offset: Int, now: Date = Date()) {
        guard spaces.count > 1, let i = spaces.firstIndex(where: { $0.id == currentSpaceID }) else { return }
        switchSpace(to: spaces[(i + offset % spaces.count + spaces.count) % spaces.count].id, now: now)
    }

    @discardableResult
    public mutating func addSpace(name: String, symbol: String, colorHex: String, separateLogins: Bool = false, activate: Bool = true,
                                  now: Date = Date()) -> Space {
        let space = Space(name: name.isEmpty ? "Space \(spaces.count + 1)" : String(name.prefix(40)), symbol: symbol, colorHex: colorHex,
                          separateLogins: separateLogins ? true : nil)
        spaces.append(space)
        if activate { switchSpace(to: space.id, now: now) }
        return space
    }

    public mutating func updateSpace(_ space: Space) {
        guard let i = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[i] = space
    }

    /// Deletes a space and its tabs (returned, so the app can tear their web views down); the last space can't be deleted.
    @discardableResult
    public mutating func deleteSpace(_ id: UUID, now: Date = Date()) -> [TabModel] {
        guard spaces.count > 1, let i = spaces.firstIndex(where: { $0.id == id }) else { return [] }
        if id == currentSpaceID { switchSpace(to: spaces[i == 0 ? 1 : i - 1].id, now: now) }
        let doomed = tabs.filter { $0.spaceID == id }
        doomed.forEach { leaveSplit($0.id) }
        tabs.removeAll { $0.spaceID == id }
        spaces.remove(at: i)
        lastActive[id] = nil
        recentlyClosed.removeAll { $0.spaceID == id }
        return doomed
    }

    /// Moves a tab to another space (it leaves its split and, as on iOS, becomes unpinned when `unpin`).
    public mutating func moveTab(_ id: UUID, toSpace space: UUID, unpin: Bool = false, now: Date = Date()) {
        guard let i = index(of: id), tabs[i].spaceID != space, spaces.contains(where: { $0.id == space }) else { return }
        leaveSplit(id)
        tabs[i].spaceID = space
        if unpin { tabs[i].isPinned = false }
        if activeID == id { setActive(mostRecent(in: currentSpaceID), now: now) }
    }

    // MARK: Split view

    private mutating func leaveSplit(_ id: UUID) {
        guard let i = splits.firstIndex(where: { $0.tabIDs.contains(id) }) else { return }
        if let smaller = splits[i].removing(id) { splits[i] = smaller } else { splits.remove(at: i) }
    }

    public mutating func removeFromSplit(_ id: UUID) { leaveSplit(id) }

    /// Ends the split on screen; other splits stay.
    public mutating func exitSplit() {
        guard let activeID else { return }
        splits.removeAll { $0.tabIDs.contains(activeID) }
    }

    public mutating func setScrollLinked(_ linked: Bool) {
        guard let activeID, let i = splits.firstIndex(where: { $0.tabIDs.contains(activeID) }) else { return }
        splits[i].scrollLinked = linked
    }

    /// With the active tab outside a split: starts a new split of it, the requested tabs, then the following
    /// tabs of the space that aren't in another split (wrapping around), opening blank tabs when there aren't
    /// enough. With the active tab in a split: requested tabs join it; without any, the split changes to
    /// `layout`, filling or dropping panes at the end.
    @discardableResult
    public mutating func makeSplit(_ layout: SplitLayout, with requested: [UUID] = [], now: Date = Date()) -> SplitGroup? {
        guard let active else { return nil }
        let requested = requested.filter { $0 != active.id && tab($0) != nil }
        if let i = splits.firstIndex(where: { $0.tabIDs.contains(active.id) }) {
            if !requested.isEmpty {
                for id in requested { addToSplit(id, now: now) }
                activate(active.id, now: now)
                return split
            }
            var ids = splits[i].tabIDs
            ids = Array(ids.prefix(layout.paneCount)) + fill(layout.paneCount - ids.count, after: active, excluding: ids, now: now)
            splits[i].layout = layout
            splits[i].tabIDs = ids
            return splits[i]
        }
        requested.forEach { leaveSplit($0) }
        var ids = Array(([active.id] + requested).prefix(layout.paneCount))
        ids += fill(layout.paneCount - ids.count, after: active, excluding: ids, now: now)
        let group = SplitGroup(layout: layout, tabIDs: ids)
        splits.append(group)
        return group
    }

    private mutating func fill(_ count: Int, after anchor: TabModel, excluding taken: [UUID], now: Date) -> [UUID] {
        guard count > 0 else { return [] }
        let free = tabs.filter { !$0.isPinned && !taken.contains($0.id) && $0.spaceID == currentSpaceID && splitGroup(containing: $0.id) == nil }
        let anchorIndex = index(of: anchor.id) ?? 0
        let start = free.firstIndex { (index(of: $0.id) ?? 0) > anchorIndex } ?? 0
        var ids = (free[start...] + free[..<start]).prefix(count).map(\.id)
        while ids.count < count { ids.append(create(url: nil, activate: false, now: now).id) }
        return ids
    }

    /// Adds a tab to the active tab's split (moving it out of any other split) and shows it.
    public mutating func addToSplit(_ id: UUID, now: Date = Date()) {
        guard let activeID, let i = splits.firstIndex(where: { $0.tabIDs.contains(activeID) }),
              !splits[i].tabIDs.contains(id), splits[i].layout.grown != nil, tab(id) != nil else { return }
        leaveSplit(id)
        guard let target = splits.firstIndex(where: { $0.tabIDs.contains(activeID) }), let grown = splits[target].adding(id) else { return }
        splits[target] = grown
        activate(id, now: now)
    }

    // MARK: Session

    /// What survives a relaunch: web pages only (Mac default), see `session(excluding:keepingBlankTabs:)`.
    public var session: TabSession? { session(excluding: []) }

    /// The saved session without `excluded` tabs (private ones). Only web pages are saved, plus blank tabs when
    /// `keepingBlankTabs` (iOS). Nil when nothing is left to save. A selection that isn't saved falls back to a
    /// saved tab in the current space.
    public func session(excluding excluded: Set<UUID>, keepingBlankTabs: Bool = false) -> TabSession? {
        guard let activeID else { return nil }
        let kept = tabs.filter { tab in
            guard !excluded.contains(tab.id) else { return false }
            guard let url = tab.url else { return keepingBlankTabs }
            return ["http", "https"].contains(url.scheme?.lowercased() ?? "")
        }
        guard !kept.isEmpty else { return nil }
        let selected = kept.contains { $0.id == activeID } ? activeID : (kept.first { $0.spaceID == currentSpaceID } ?? kept[0]).id
        let result = TabSession(spaces: spaces, tabs: kept, activeID: selected, currentSpaceID: currentSpaceID)
        return result.isValid ? result : nil
    }

    /// Replaces the contents with a saved session. With `asleep` (default) pages come back unloaded and load when
    /// first used; the selected tab is always awake. Invalid sessions are ignored and `false` is returned.
    @discardableResult
    public mutating func restore(_ session: TabSession, asleep: Bool = true, now: Date = Date()) -> Bool {
        guard session.isValid else { return false }
        self = TabCollection(spaces: session.spaces)
        currentSpaceID = session.currentSpaceID
        tabs = session.tabs.map { var t = $0; t.splitID = nil; t.isSleeping = asleep && t.url != nil; return t }
        setActive(session.activeID, now: now)
        tabs[index(of: session.activeID)!].lastActivated = session.tabs.first { $0.id == session.activeID }!.lastActivated
        return true
    }
}
