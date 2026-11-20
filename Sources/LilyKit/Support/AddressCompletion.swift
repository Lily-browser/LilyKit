import Foundation

/// Address-bar autocomplete and ranking for the command bar, kept free of UI so it can be tested.
///
/// **Inline completion** (Safari-like, deliberately moderate): typing the start of a site's host
/// ("git") fills in the rest ("github.com"), selected, so the next keystroke replaces it. Once the
/// text has a "/", it completes to a page's path instead. A site or page qualifies only if it was
/// visited at least twice (separate visits; History merges reloads within 30 minutes), is
/// bookmarked, or is open in a tab, so one stray visit never takes over the address bar. Search
/// phrases (anything with a space) are never completed, and neither are engine suggestions.
///
/// **Frecency**: each visit counts more the more recent it is (100 within 4 days, 70 within two
/// weeks, 50 within a month, 30 within three months, 10 after that); a bookmark adds 100 and an
/// open tab 50. Candidates and history suggestions are ranked by it.
enum AddressCompletion {
    /// What the field shows: exactly what was typed, then the completed rest (selected).
    struct Completion: Equatable, Sendable {
        let typed: String
        let text: String
        let url: URL

        /// The completed part, in UTF-16 units from the end of `typed` (for NSTextView's selection).
        var selectedRange: NSRange {
            let start = (typed as NSString).length
            return NSRange(location: start, length: (text as NSString).length - start)
        }
    }

    struct Candidate: Equatable, Sendable {
        /// What the field shows after the typed prefix: host (and path), without scheme or "www.".
        let display: String
        /// `display` lowercased, for matching.
        let key: String
        let url: URL
        let score: Double
        /// Visited twice, bookmarked or open: allowed to complete inline.
        let qualifies: Bool
        /// The page's title, or the site's root page title (empty when unknown).
        let title: String
    }

    /// Built once per command bar (off the main actor) from history, bookmarks and open tabs.
    struct Index: Sendable {
        /// One per site (host without "www."), best first.
        var sites: [Candidate] = []
        /// One per page without a query string, best first.
        var pages: [Candidate] = []
        /// Frecency per exact page address, for ranking history suggestions.
        var pageScores: [URL: Double] = [:]

        static let empty = Index()
    }

    struct Visit: Sendable {
        let url: URL
        let title: String
        let date: Date
    }

    static let bookmarkBonus = 100.0
    static let tabBonus = 50.0

    static func weight(age: TimeInterval) -> Double {
        switch age / 86_400 {
        case ..<4: return 100
        case ..<14: return 70
        case ..<31: return 50
        case ..<90: return 30
        default: return 10
        }
    }

    /// Lowercased host without "www.", or nil for anything but http(s).
    static func site(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// "github.com/pwngoblin/lily" for a page (original case), nil for non-http(s) or pages with a
    /// query string (search results and the like aren't completed to).
    static func pageDisplay(of url: URL) -> String? {
        guard let site = site(of: url), url.query == nil else { return nil }
        let path = url.path(percentEncoded: true)
        return site + (path.isEmpty ? "/" : path)
    }

    static func index(visits: [Visit], bookmarks: [URL], tabs: [URL], now: Date) -> Index {
        struct Tally { var score = 0.0; var count = 0; var pinned = false; var title = ""; var titleDate = Date.distantPast }
        var pages: [URL: Tally] = [:]
        for visit in visits where site(of: visit.url) != nil {
            var tally = pages[visit.url] ?? Tally()
            tally.score += weight(age: now.timeIntervalSince(visit.date))
            tally.count += 1
            if !visit.title.isEmpty, visit.date > tally.titleDate { tally.title = visit.title; tally.titleDate = visit.date }
            pages[visit.url] = tally
        }
        for url in bookmarks where site(of: url) != nil {
            pages[url, default: Tally()].score += bookmarkBonus
            pages[url, default: Tally()].pinned = true
        }
        for url in Set(tabs) where site(of: url) != nil {
            pages[url, default: Tally()].score += tabBonus
            pages[url, default: Tally()].pinned = true
        }

        struct SiteTally { var score = 0.0; var count = 0; var pinned = false; var origins: [URL: Double] = [:]; var title = "" }
        var sites: [String: SiteTally] = [:]
        var pageCandidates: [Candidate] = []
        var pageScores: [URL: Double] = [:]
        pageScores.reserveCapacity(pages.count)
        for (url, tally) in pages {
            pageScores[url] = tally.score
            guard let site = site(of: url), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else { continue }
            var entry = sites[site] ?? SiteTally()
            entry.score += tally.score
            entry.count += tally.count
            entry.pinned = entry.pinned || tally.pinned
            if let origin = URL(string: "\(scheme)://\(host)/") { entry.origins[origin, default: 0] += tally.score }
            let path = url.path(percentEncoded: true)
            if (path.isEmpty || path == "/"), url.query == nil, !tally.title.isEmpty { entry.title = tally.title }
            sites[site] = entry
            if let display = pageDisplay(of: url) {
                pageCandidates.append(Candidate(display: display, key: display.lowercased(), url: url, score: tally.score,
                                                qualifies: tally.count >= 2 || tally.pinned, title: tally.title))
            }
        }
        let siteCandidates = sites.compactMap { site, tally -> Candidate? in
            // The https origin most visits went to (www or not, as visited); http only when the
            // site was never visited over https.
            let secure = tally.origins.filter { $0.key.scheme == "https" }
            guard let origin = (secure.isEmpty ? tally.origins : secure).max(by: { ($0.value, $1.key.absoluteString) < ($1.value, $0.key.absoluteString) })?.key else { return nil }
            return Candidate(display: site, key: site, url: origin, score: tally.score,
                             qualifies: tally.count >= 2 || tally.pinned, title: tally.title)
        }
        return Index(sites: siteCandidates.sorted(by: better), pages: pageCandidates.sorted(by: better), pageScores: pageScores)
    }

    /// Higher score first; then the shorter (more general) address; then alphabetical, so the
    /// order never depends on dictionary order.
    static func better(_ a: Candidate, _ b: Candidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.key.count != b.key.count { return a.key.count < b.key.count }
        return a.key < b.key
    }

    /// Splits off a leading "http(s)://" and "www.", which are kept as typed but not matched.
    static func split(_ typed: String) -> (prefix: String, rest: Substring) {
        var rest = Substring(typed)
        for scheme in ["https://", "http://"] where rest.lowercased().hasPrefix(scheme) {
            rest = rest.dropFirst(scheme.count)
            break
        }
        if rest.lowercased().hasPrefix("www.") { rest = rest.dropFirst(4) }
        return (String(typed.prefix(typed.count - rest.count)), rest)
    }

    /// The inline completion for `typed`, or nil. Host completion until the text has a "/", then
    /// path completion; never for text with whitespace or when nothing is left to add.
    static func complete(_ typed: String, in index: Index) -> Completion? {
        guard !typed.isEmpty, !typed.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let (_, rest) = split(typed)
        guard !rest.isEmpty else { return nil }
        let needle = rest.lowercased()
        // Lowercasing must not change lengths, or the typed prefix and the completed rest won't line up.
        guard needle.count == rest.count else { return nil }
        let candidates = needle.contains("/") ? index.pages : index.sites
        guard let match = candidates.first(where: {
            $0.qualifies && $0.key.count > needle.count && $0.key.count == $0.display.count && $0.key.hasPrefix(needle)
        }) else { return nil }
        // A typed scheme is the one opened ("http://ex" → http://example.com/); otherwise the
        // site's own, https whenever it was ever visited that way.
        var url = match.url
        let prefix = split(typed).prefix.lowercased()
        let scheme = prefix.hasPrefix("https://") ? "https" : prefix.hasPrefix("http://") ? "http" : nil
        if let scheme, url.scheme != scheme, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = scheme
            url = components.url ?? url
        }
        return Completion(typed: typed, text: typed + match.display.dropFirst(needle.count), url: url)
    }

    /// True when `url`'s site starts with what was typed ("you" → youtube.com).
    static func hostStarts(_ url: URL?, with needle: String) -> Bool {
        guard let url, let site = site(of: url) else { return false }
        let rest = split(needle).rest.lowercased()
        return !rest.isEmpty && site.hasPrefix(rest)
    }

    /// Stable re-ranking of matches: sites whose host starts with the query first, then by score.
    static func rank<T>(_ items: [T], url: (T) -> URL?, query: String, score: (URL) -> Double) -> [T] {
        items.enumerated()
            .map { (item: $0.element, index: $0.offset, prefix: hostStarts(url($0.element), with: query),
                    score: url($0.element).map(score) ?? 0) }
            .sorted { a, b in
                if a.prefix != b.prefix { return a.prefix }
                if a.score != b.score { return a.score > b.score }
                return a.index < b.index
            }
            .map(\.item)
    }

    /// Most visited sites for an empty command bar: one row per site, best first.
    static func topSites(_ index: Index, excluding current: URL?, limit: Int) -> [Candidate] {
        let skip = current.flatMap(site(of:))
        return Array(index.sites.lazy.filter { $0.key != skip }.prefix(limit))
    }
}
