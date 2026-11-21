import Foundation
import Testing
@testable import LilyKit

@Suite struct TabCollectionTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private func url(_ s: String) -> URL { URL(string: "https://\(s)")! }
    private func make() -> TabCollection { TabCollection(spaces: [Space(name: "A", symbol: "circle", colorHex: "#000000"), Space(name: "B", symbol: "circle", colorHex: "#111111")]) }

    @Test func pinnedTabsStaySorted() {
        var c = make()
        let a = c.create(url: url("a.com"), now: t0)
        let b = c.create(url: url("b.com"), now: t0)
        c.setPinned(b.id, true)
        #expect(c.tabs.map(\.id) == [b.id, a.id])
        let p = c.create(url: url("p.com"), pinned: true, now: t0)
        #expect(c.tabs.map(\.id) == [b.id, p.id, a.id])
        c.move(a.id, to: 0) // can't cross into the pinned section
        #expect(c.tabs.map(\.id) == [b.id, p.id, a.id])
    }

    @Test func newTabNextToActive() {
        var c = make()
        let a = c.create(url: url("a.com"), now: t0)
        let b = c.create(url: url("b.com"), now: t0)
        c.activate(a.id, now: t0)
        let n = c.create(url: url("n.com"), nextToActive: true, now: t0)
        #expect(c.tabs.map(\.id) == [a.id, n.id, b.id])
    }

    @Test func closeFollowsAfterCloseMode() {
        for (mode, expectedIndex) in [(AfterClose.below, 2), (.above, 0)] {
            var c = make()
            let ids = (0..<3).map { c.create(url: url("\($0).com"), now: t0).id }
            c.activate(ids[1], now: t0)
            c.close(ids[1], then: mode, now: t0)
            #expect(c.activeID == ids[expectedIndex])
        }
    }

    @Test func closeLastUsedPicksMostRecent() {
        var c = make()
        let a = c.create(url: url("a.com"), now: t0)
        let b = c.create(url: url("b.com"), now: t0.addingTimeInterval(10))
        let n = c.create(url: url("n.com"), now: t0.addingTimeInterval(20))
        c.close(n.id, now: t0.addingTimeInterval(30))
        #expect(c.activeID == b.id)
        _ = a
    }

    @Test func reopenRestoresPositionAndPin() {
        var c = make()
        let a = c.create(url: url("a.com"), now: t0)
        let b = c.create(url: url("b.com"), now: t0)
        _ = c.create(url: url("c.com"), now: t0)
        c.close(b.id, now: t0)
        let back = c.reopenClosed(now: t0)
        #expect(back?.url == url("b.com"))
        #expect(c.index(of: back!.id) == 1)
        #expect(c.tabs.first?.id == a.id)
        #expect(c.reopenClosed(now: t0) == nil)
    }

    @Test func blankTabsAreNotRemembered() {
        var c = make()
        let blank = c.create(url: nil, now: t0)
        c.close(blank.id, now: t0)
        #expect(c.recentlyClosed.isEmpty)
    }

    @Test func keepSpaceNonEmptyLeavesBlankTab() {
        var c = make()
        let only = c.create(url: url("a.com"), now: t0)
        c.close(only.id, keepSpaceNonEmpty: true, now: t0)
        #expect(c.visibleTabs.count == 1)
        #expect(c.active?.url == nil)
    }

    @Test func switchingSpacesRemembersLastActive() {
        var c = make()
        let a1 = c.create(url: url("a1.com"), now: t0)
        _ = c.create(url: url("a2.com"), now: t0.addingTimeInterval(5))
        let b = c.addSpace(name: "", symbol: "star", colorHex: "#222222", activate: false)
        #expect(b.name == "Space 3")
        c.activate(a1.id, now: t0.addingTimeInterval(6))
        let other = c.spaces[1].id
        c.create(url: url("b.com"), now: t0.addingTimeInterval(7)) // goes to space A (current)
        c.switchSpace(to: other, now: t0)
        c.switchSpace(to: c.spaces[0].id, now: t0)
        #expect(c.currentSpaceID == c.spaces[0].id)
        #expect(c.activeID != nil)
    }

    @Test func activatingTabInOtherSpaceSwitchesSpace() {
        var c = make()
        let other = c.spaces[1].id
        c.switchSpace(to: other)
        let t = c.create(url: url("x.com"), now: t0)
        c.switchSpace(to: c.spaces[0].id)
        c.activate(t.id, now: t0)
        #expect(c.currentSpaceID == other)
    }

    @Test func deletingSpaceRemovesItsTabsAndKeepsLastSpace() {
        var c = make()
        let first = c.spaces[0].id
        c.create(url: url("a.com"), now: t0)
        let doomed = c.deleteSpace(first, now: t0)
        #expect(doomed.count == 1)
        #expect(c.spaces.count == 1)
        #expect(c.currentSpaceID == c.spaces[0].id)
        let lastID = c.spaces[0].id; let again = c.deleteSpace(lastID); #expect(again.isEmpty) // the last space stays
    }

    @Test func movingActiveTabAwayPicksAnotherInSpace() {
        var c = make()
        let a = c.create(url: url("a.com"), now: t0)
        let b = c.create(url: url("b.com"), now: t0.addingTimeInterval(1))
        c.moveTab(b.id, toSpace: c.spaces[1].id, now: t0.addingTimeInterval(2))
        #expect(c.activeID == a.id)
    }

    @Test func splitGroupShrinksAndEnds() {
        var c = make()
        let ids = (0..<3).map { c.create(url: url("\($0).com"), activate: false, now: t0).id }
        c.activate(ids[0], now: t0)
        let g = c.makeSplit(.threeColumns, now: t0)
        #expect(g?.tabIDs == ids)
        c.close(ids[2], now: t0)
        #expect(c.split?.layout == .twoColumns)
        c.close(ids[1], now: t0)
        #expect(c.split == nil)
    }

    @Test func splitOpensBlankTabsWhenShort() {
        var c = make()
        let a = c.create(url: url("a.com"), now: t0)
        let g = c.makeSplit(.grid, now: t0)
        #expect(g?.tabIDs.count == 4)
        #expect(g?.tabIDs.first == a.id)
        #expect(c.tabs.count == 4)
    }

    @Test func pinnedTabsAreNeverPulledIntoASplit() {
        var c = make()
        let p = c.create(url: url("p.com"), pinned: true, now: t0)
        let a = c.create(url: url("a.com"), now: t0)
        let g = c.makeSplit(.twoColumns, now: t0)
        #expect(g?.tabIDs.contains(p.id) == false)
        #expect(g?.tabIDs.first == a.id)
    }

    @Test func sessionRoundTripsAndOnlySavesWebPages() throws {
        var c = make()
        c.create(url: url("a.com"), now: t0)
        c.create(url: URL(string: "data:text/html,hi")!, now: t0)
        let blank = c.create(url: nil, now: t0)
        let saved = try #require(c.session)
        #expect(saved.tabs.count == 1)
        #expect(saved.isValid) // the blank, selected tab isn't saved; selection falls back to a saved tab
        _ = blank
        var d = TabCollection()
        let ok = d.restore(saved, now: t0); #expect(ok)
        #expect(d.tabs.count == 1 && !d.tabs[0].isSleeping) // the selected tab loads; others stay asleep
        #expect(d.spaces == c.spaces)
    }

    @Test func invalidSessionIsRejected() {
        var c = make()
        let bad = TabSession(spaces: c.spaces, tabs: [], activeID: UUID(), currentSpaceID: c.spaces[0].id)
        let rejected = c.restore(bad); #expect(!rejected)
        #expect(c.spaces.count == 2)
    }

    @Test func activatingWakesTheTab() {
        var c = make()
        let a = c.createAsleep(url: url("a.com"), title: "", pinned: false, in: c.currentSpaceID, now: t0)
        #expect(a.isSleeping && a.title == "a.com")
        c.activate(a.id, now: t0.addingTimeInterval(9))
        #expect(c.tab(a.id)?.isSleeping == false)
        #expect(c.tab(a.id)?.lastActivated == t0.addingTimeInterval(9))
    }

    @Test func numberedAndCyclingSelection() {
        var c = make()
        let ids = (0..<3).map { c.create(url: url("\($0).com"), now: t0).id }
        c.activate(number: 9, now: t0); #expect(c.activeID == ids[2])
        c.activate(number: 1, now: t0); #expect(c.activeID == ids[0])
        c.cycle(by: -1, now: t0); #expect(c.activeID == ids[2])
    }
}
