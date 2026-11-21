import Foundation
import Observation

/// Bookmarks, as folders and links (today filled by importing from other browsers). Encrypted at
/// rest like history (`SealedFile`), and only http(s) links are kept.
@MainActor @Observable
public final class Bookmarks {
    public struct Node: Codable, Identifiable, Equatable, Sendable {
        public var id = UUID()
        public var title: String
        /// nil for folders.
        public var url: URL?
        public var children: [Node]?

        public init(title: String, url: URL? = nil, children: [Node]? = nil) {
            self.title = title
            self.url = url
            self.children = children
        }

        public var isFolder: Bool { children != nil }

        public static func folder(_ title: String, _ children: [Node]) -> Node { Node(title: title, url: nil, children: children) }
        fileprivate func withID(_ id: UUID) -> Node { var copy = self; copy.id = id; return copy }
        public static func link(_ title: String, _ url: URL) -> Node { Node(title: title, url: url, children: nil) }
    }

    public static let maxLinks = 100_000

    public private(set) var root: [Node] = [] { didSet { index = nil; generation &+= 1 } }
    /// Bumped on every change; see `History.generation`.
    @ObservationIgnored public private(set) var generation = 0
    /// Every link with its lowercased title + address, rebuilt after changes.
    @ObservationIgnored private var index: [(link: Node, text: NSString)]?
    @ObservationIgnored private let file: SealedFile?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    /// `directory: nil` keeps bookmarks in memory only (tests, self-test).
    public init(directory: URL?, keys: KeyStore = KeychainKeyStore()) {
        file = directory.map {
            SealedFile(url: $0.appendingPathComponent("bookmarks.sealed"), keyName: "bookmarks", purpose: "dev.lily.bookmarks.v1", keys: keys)
        }
    }

    public func load() async {
        guard let file else { return }
        do {
            if let data = try await file.read() { root = try JSONDecoder().decode([Node].self, from: data) }
        } catch {
            Log.app.error("Bookmarks could not be decrypted; starting empty")
            file.deleteCorrupt()
        }
    }

    private var linkIndex: [(link: Node, text: NSString)] {
        if let index { return index }
        var out: [(link: Node, text: NSString)] = []
        func walk(_ nodes: [Node]) {
            for node in nodes {
                if let children = node.children { walk(children) } else if let url = node.url { out.append((node, (node.title + "\n" + url.absoluteString).lowercased() as NSString)) }
            }
        }
        walk(root)
        index = out
        return out
    }

    /// Every link, depth first.
    public var links: [Node] { linkIndex.map(\.link) }

    public var linkCount: Int { linkIndex.count }

    /// Links whose title or address contains `query`.
    public func search(_ query: String, limit: Int = 20) -> [Node] {
        let needle = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        var out: [Node] = []
        // Already lowercased, so a literal (byte-wise) search is enough, and several times faster.
        for entry in linkIndex where out.count < limit && entry.text.range(of: needle, options: .literal).location != NSNotFound { out.append(entry.link) }
        return out
    }

    /// Adds a top-level folder, leaving out links already bookmarked (by normalized address) and
    /// anything that isn't http(s). Returns how many links were added.
    @discardableResult
    public func addFolder(_ folder: Node) -> Int {
        var known = Set(links.compactMap { $0.url.map(URLNormalizer.key) })
        let existing = linkCount // counted once, not per link
        var added = 0
        func filter(_ nodes: [Node]) -> [Node] {
            nodes.compactMap { node in
                if let children = node.children {
                    let kept = filter(children)
                    return kept.isEmpty ? nil : .folder(node.title, kept)
                }
                guard let url = node.url, URLNormalizer.isImportable(url), existing + added < Self.maxLinks,
                      known.insert(URLNormalizer.key(url)).inserted else { return nil }
                added += 1
                return .link(String(node.title.prefix(500)), url)
            }
        }
        let kept = filter(folder.children ?? [])
        guard !kept.isEmpty else { return 0 }
        root.append(.folder(folder.title, kept))
        scheduleSave()
        return added
    }

    /// The bookmark for this page (same page by normalized address), if there is one.
    public func link(for url: URL) -> Node? {
        let key = URLNormalizer.key(url)
        return links.first { $0.url.map(URLNormalizer.key) == key }
    }

    public func contains(_ url: URL) -> Bool { link(for: url) != nil }

    /// Bookmarks one page at the top level. A page that is already bookmarked, a non-web address or a full
    /// collection adds nothing. Returns the bookmark that now exists (the old one when it was a duplicate).
    @discardableResult
    public func add(title: String, url: URL) -> Node? {
        guard URLNormalizer.isImportable(url) else { return nil }
        if let existing = link(for: url) { return existing }
        guard linkCount < Self.maxLinks else { return nil }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let node = Node.link(String((name.isEmpty ? (url.host ?? url.absoluteString) : name).prefix(500)), url)
        root.append(node)
        scheduleSave()
        return node
    }

    /// Removes a bookmark or a whole folder by id, wherever it is. Folders left empty stay (they are the user's).
    public func remove(_ id: UUID) {
        func prune(_ nodes: [Node]) -> [Node] {
            nodes.compactMap { node in
                if node.id == id { return nil }
                guard var children = node.children else { return node }
                children = prune(children)
                return .folder(node.title, children).withID(node.id)
            }
        }
        let before = root
        root = prune(root)
        if root != before { scheduleSave() }
    }

    /// Removes the bookmark for this page; true when there was one.
    @discardableResult
    public func remove(url: URL) -> Bool {
        guard let existing = link(for: url) else { return false }
        remove(existing.id)
        return true
    }

    /// Bookmarks the page, or removes its bookmark when it already has one. Returns whether it is bookmarked now.
    @discardableResult
    public func toggle(title: String, url: URL) -> Bool {
        if remove(url: url) { return false }
        return add(title: title, url: url) != nil
    }

    public func removeAll() {
        root.removeAll()
        scheduleSave()
    }

    private func scheduleSave() {
        guard let file else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await self.flush()
        }
    }

    public func flush() async {
        saveTask?.cancel()
        guard let file else { return }
        let snapshot = root
        let ticket = file.reserve() // ordered by when the snapshot was taken, not when it's written
        await Task.detached(priority: .utility) {
            do {
                if snapshot.isEmpty { file.delete(ticket: ticket) } else { try await file.write(try JSONEncoder().encode(snapshot), ticket: ticket) }
            } catch {
                Log.app.error("Saving bookmarks failed")
            }
        }.value
    }
}
