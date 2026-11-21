import Foundation
import Testing
@testable import LilyKit

@MainActor
struct BookmarksTests {
    private let page = URL(string: "https://example.com/a")!

    @Test func addsOnePageOnce() {
        let bookmarks = Bookmarks(directory: nil)
        let first = bookmarks.add(title: "  Example ", url: page)
        #expect(first?.title == "Example" && bookmarks.linkCount == 1)
        // Same page by normalized address (tracking parameter, trailing slash, fragment): not added twice.
        let again = bookmarks.add(title: "Other", url: URL(string: "https://EXAMPLE.com/a/?utm_source=x#top")!)
        #expect(again?.id == first?.id && bookmarks.linkCount == 1)
        #expect(bookmarks.contains(page))
    }

    @Test func refusesNonWebAddresses() {
        let bookmarks = Bookmarks(directory: nil)
        for bad in ["javascript:alert(1)", "file:///etc/hosts", "data:text/html,x", "about:blank"] {
            #expect(bookmarks.add(title: "x", url: URL(string: bad)!) == nil, "\(bad)")
        }
        #expect(bookmarks.linkCount == 0)
    }

    @Test func emptyTitleFallsBackToTheHost() {
        let bookmarks = Bookmarks(directory: nil)
        #expect(bookmarks.add(title: "  ", url: page)?.title == "example.com")
    }

    @Test func removesByIdAndByPageEvenInsideFolders() {
        let bookmarks = Bookmarks(directory: nil)
        bookmarks.addFolder(.folder("Imported", [.folder("Work", [.link("A", page), .link("B", URL(string: "https://b.example/")!)])]))
        #expect(bookmarks.linkCount == 2)
        #expect(bookmarks.remove(url: page))
        #expect(!bookmarks.contains(page) && bookmarks.linkCount == 1)
        #expect(!bookmarks.remove(url: page))
        let id = bookmarks.links[0].id
        bookmarks.remove(id)
        #expect(bookmarks.linkCount == 0)
        #expect(bookmarks.root.count == 1) // the folders the user made stay
    }

    @Test func toggleAddsThenRemoves() {
        let bookmarks = Bookmarks(directory: nil)
        #expect(bookmarks.toggle(title: "E", url: page))
        #expect(!bookmarks.toggle(title: "E", url: page))
        #expect(bookmarks.linkCount == 0)
    }
}
