import Foundation

/// In-memory record of local browser events (navigations, selections, videos) per tab, used to
/// ground assistant answers. Bounded, never persisted.
@MainActor
public final class AssistantContextStore {
    public struct Visit: Sendable, Equatable {
        public var url: String
        public var title: String
        public var tabID: UUID?

        public init(url: String, title: String, tabID: UUID? = nil) {
            self.url = url
            self.title = title
            self.tabID = tabID
        }
    }

    public struct TabContext {
        public var events = 0
        public var page: Visit?
        public var selection: String?
        public var videoID: String?

        public init(page: Visit? = nil, selection: String? = nil, videoID: String? = nil) {
            self.page = page
            self.selection = selection
            self.videoID = videoID
        }
    }

    public static let maxHistory = 100
    private var tabs: [UUID: TabContext] = [:]
    private(set) var history: [Visit] = []

    public init() {}

    public func ingest(tabID: UUID, type: String, payload: JSONValue) {
        if type == "tab.closed" {
            tabs[tabID] = nil
            return
        }
        var tab = tabs[tabID] ?? TabContext()
        tab.events += 1
        switch type {
        case "page.didChange":
            guard let url = payload["url"]?.string else { break }
            let title = payload["title"]?.string ?? ""
            tab.page = Visit(url: url, title: title, tabID: tabID)
            tab.selection = nil
            if history.last?.url == url {
                if !title.isEmpty { history[history.count - 1].title = title }
            } else {
                history.append(Visit(url: url, title: title, tabID: tabID))
                if history.count > Self.maxHistory { history.removeFirst(history.count - Self.maxHistory) }
            }
        case "selection.changed":
            tab.selection = payload["text"]?.string?.nilIfEmpty
        case "selection.cleared":
            tab.selection = nil
        case "youtube.videoChanged":
            tab.videoID = payload["videoId"]?.string
        default:
            break
        }
        tabs[tabID] = tab
    }

    /// Clear Browsing Data: forget everything.
    public func reset() {
        tabs.removeAll()
        history.removeAll()
    }

    public func selection(for tabID: UUID?) -> String? { tabID.flatMap { tabs[$0]?.selection } }

    public func recentHistory(limit: Int = 15) -> [Visit] { Array(history.suffix(limit)) }

    public var stats: JSONValue { ["tabs": JSONValue(tabs.count), "history": JSONValue(history.count)] }
}
