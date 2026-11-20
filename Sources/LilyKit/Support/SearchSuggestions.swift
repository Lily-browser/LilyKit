import Foundation

/// Search-engine suggestions for the command bar (Settings → Privacy → Search engine suggestions,
/// on by default). What you type goes to the engine you chose and no one else: Kagi has no public
/// suggestion endpoint, so with Kagi nothing is fetched. Never in private windows, never for
/// addresses, emails, file paths or long text. See docs/PRIVACY.md.
public enum SearchSuggestions {
    public static let maxResponseBytes = 64 * 1024
    public static let maxSuggestions = 5
    public static let maxLength = 200

    /// The engine's OpenSearch suggestion endpoint for `query`, or nil (Kagi).
    public static func endpoint(for engine: Preferences.SearchEngine, query: String) -> URL? {
        let base: String
        var items: [URLQueryItem]
        switch engine {
        case .duckDuckGo:
            base = "https://duckduckgo.com/ac/"
            items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        case .google:
            base = "https://suggestqueries.google.com/complete/search"
            items = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "ie", value: "utf-8"),
                     URLQueryItem(name: "oe", value: "utf-8"), URLQueryItem(name: "q", value: query)]
        case .bing:
            base = "https://api.bing.com/osjson.aspx"
            items = [URLQueryItem(name: "query", value: query)]
        case .ecosia:
            base = "https://ac.ecosia.org/autocomplete"
            items = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "type", value: "list")]
        case .kagi:
            return nil
        }
        guard var components = URLComponents(string: base) else { return nil }
        components.queryItems = items
        // URLComponents leaves "+" alone, which servers read as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url, url.scheme == "https" else { return nil }
        return url
    }

    /// Whether typing `query` may be sent to the engine. Only what reads as a search goes out:
    /// nothing with "://" or "@", no scheme ("mailto:", "localhost:3000"), no file paths, no
    /// tabs or line breaks, and no word that is itself an address, an IP literal, or a long mix of
    /// letters and digits (a token or key).
    public static func shouldFetch(_ query: String, engine: Preferences.SearchEngine, enabled: Bool, isPrivate: Bool,
                            resolver: URLResolver) -> Bool {
        guard enabled, !isPrivate, engine != .kagi else { return false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, q.count <= maxLength else { return false }
        if q.contains("://") || q.contains("@") { return false }
        if q.contains(where: { $0.isNewline || $0 == "\t" }) { return false }
        let hasSpace = q.contains(where: \.isWhitespace)
        if q.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#, options: .regularExpression) != nil, !hasSpace { return false }
        if q.hasPrefix("/") || q.hasPrefix("~") || q.hasPrefix("./") || q.hasPrefix("../") || q.hasPrefix("\\") { return false }
        for token in q.split(whereSeparator: \.isWhitespace).map(String.init) {
            // An address: the resolver opens it rather than searching for it.
            if let url = resolver.resolve(token), url.absoluteString != resolver.searchURL(for: token)?.absoluteString { return false }
            // IPv6 literals ("[::1]", "fe80::1").
            if token.hasPrefix("[") && token.contains(":") { return false }
            if token.filter({ $0 == ":" }).count >= 2, token.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }) { return false }
            if looksLikeSecret(token) { return false }
        }
        return true
    }

    /// 24+ characters mixing letters and digits: an API key, token or ID rather than words.
    public static func looksLikeSecret(_ token: String) -> Bool {
        token.count >= 24 && token.contains(where: \.isLetter) && token.contains(where: \.isNumber)
    }

    /// Decodes an OpenSearch response, `["query", ["s1", "s2", …], …]`, into at most five clean,
    /// distinct suggestions. Nil for anything else (or more than 64 KB).
    public static func decode(_ data: Data) -> [String]? {
        guard data.count <= maxResponseBytes,
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2, json[0] is String, let list = json[1] as? [Any] else { return nil }
        var out: [String] = []
        var seen = Set<String>()
        for item in list {
            guard let text = item as? String, let clean = sanitize(text), seen.insert(clean.lowercased()).inserted else { continue }
            out.append(clean)
            if out.count == maxSuggestions { break }
        }
        return out
    }

    public static let maxScalars = 400
    public static let invisible: Set<UInt32> = [0x115F, 0x1160, 0x3164, 0xFFA0, 0x034F]

    /// Control characters become spaces, invisible characters (bidi overrides, zero-width, Hangul
    /// fillers) are dropped, whitespace is collapsed; nil when empty, longer than 200 characters
    /// or 400 Unicode scalars.
    public static func sanitize(_ text: String) -> String? {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control: scalars.append(" ")
            case .format: continue
            default:
                // Blank-looking letters (Hangul fillers) and the combining grapheme joiner.
                if invisible.contains(scalar.value) { continue }
                scalars.append(scalar)
            }
        }
        let clean = String(scalars).split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        // Characters are capped, and so are scalars, which stops a flood of combining marks.
        return clean.isEmpty || clean.count > maxLength || clean.unicodeScalars.count > maxScalars ? nil : clean
    }
}

/// Fetches suggestions; tests inject their own.
public protocol SearchSuggestionFetching: Sendable {
    func suggestions(for query: String, engine: Preferences.SearchEngine) async throws -> [String]
    /// The command bar closed: drop connections so the next one can't be linked to this one.
    func close()
}

extension SearchSuggestionFetching {
    public func close() {}
}

/// Network fetcher with its own ephemeral session, one per command bar opening: no cookies,
/// cache or credentials, and no connection (keep-alive or TLS session) shared with the next
/// opening, so the engine can't tie suggestions to your searches, logins or each other. Safari's
/// user agent, as for pages. Redirects are refused, and the answer must come from the engine's
/// own host over HTTPS.
public final class SearchSuggestionClient: SearchSuggestionFetching {
    private let session: URLSession

    /// The user agent is the host app's: it matches the one its pages send (Safari's, per platform).
    public static func configuration(userAgent: String) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "application/json, application/x-suggestions+json",
        ]
        return config
    }

    public init(userAgent: String, configuration: URLSessionConfiguration? = nil) {
        session = URLSession(configuration: configuration ?? Self.configuration(userAgent: userAgent))
    }

    public func close() { session.invalidateAndCancel() }

    /// Refuses every redirect; the 3xx response itself then fails the status check.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
        public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    public func suggestions(for query: String, engine: Preferences.SearchEngine) async throws -> [String] {
        guard let url = SearchSuggestions.endpoint(for: engine, query: query), let host = url.host else { return [] }
        var request = URLRequest(url: url)
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request, delegate: NoRedirects())
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              http.url?.scheme == "https", http.url?.host == host,
              http.expectedContentLength <= Int64(SearchSuggestions.maxResponseBytes) else {
            bytes.task.cancel()
            return []
        }
        var data = Data()
        data.reserveCapacity(4_096)
        for try await byte in bytes {
            data.append(byte)
            if data.count > SearchSuggestions.maxResponseBytes {
                bytes.task.cancel()
                return []
            }
        }
        return SearchSuggestions.decode(data) ?? []
    }
}

/// Never fetches (the self-test, so it doesn't reach a search engine).
public struct NoSearchSuggestions: SearchSuggestionFetching {
    public init() {}

    public func suggestions(for query: String, engine: Preferences.SearchEngine) async throws -> [String] { [] }
}
