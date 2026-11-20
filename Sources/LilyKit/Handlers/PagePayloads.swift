import Foundation

/// Schemas for page → native events. They arrive through our own injections, but those read
/// attacker-controlled DOM, so every field is treated as untrusted: decoded into a fixed shape,
/// length-bounded, and URLs must belong to the frame's security origin (set by WebKit, not the page).
public enum PagePayload {
    public static let maxTitle = 1_000
    public static let maxURL = 4_096
    public static let maxSelection = 20_000
    public static let maxMessage = 500

    public struct DidChange: Decodable {
        public var url: String
        public var title: String?
        public var description: String?
        public var favicon: String?
        public var themeColor: String?

        public init(url: String, title: String? = nil, description: String? = nil, favicon: String? = nil, themeColor: String? = nil) {
            self.url = url
            self.title = title
            self.description = description
            self.favicon = favicon
            self.themeColor = themeColor
        }
    }

    public struct Selection: Decodable {
        public var url: String
        public var text: String
        public var truncated: Bool?

        public init(url: String, text: String, truncated: Bool? = nil) {
            self.url = url
            self.text = text
            self.truncated = truncated
        }
    }

    public struct SelectionCleared: Decodable {
        public var url: String

        public init(url: String) {
            self.url = url
        }
    }

    /// Text typed into a long field (`form-recovery.js`).
    public struct FormSnapshot: Decodable {
        public var url: String
        public var field: String
        public var text: String

        public init(url: String, field: String, text: String) {
            self.url = url
            self.field = field
            self.text = text
        }
    }

    /// Where a linked split pane is scrolled to, as fractions of how far it can scroll.
    public struct ScrollPosition: Decodable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public var clamped: JSONValue {
            let fraction = { (v: Double) in v.isFinite ? min(1, max(0, v)) : 0 }
            return ["x": .number(fraction(x)), "y": .number(fraction(y))]
        }
    }

    public struct FormClear: Decodable {
        public var url: String
        public var field: String

        public init(url: String, field: String) {
            self.url = url
            self.field = field
        }
    }

    /// A request that carries nothing: `null` or `{}`, and nothing else.
    public struct Empty: Decodable {
        private struct AnyKey: CodingKey {
            public var stringValue: String
            public var intValue: Int? { nil }
            public init?(stringValue: String) { self.stringValue = stringValue }
            public init?(intValue: Int) { nil }
        }

        public init(from decoder: Decoder) throws {
            if let single = try? decoder.singleValueContainer(), single.decodeNil() { return }
            guard try decoder.container(keyedBy: AnyKey.self).allKeys.isEmpty else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected no payload"))
            }
        }
    }

    public struct VideoChanged: Decodable {
        public var videoId: String?
        public var url: String

        public init(videoId: String? = nil, url: String) {
            self.videoId = videoId
            self.url = url
        }
    }

    public struct RuntimeError: Decodable {
        public var message: String?
        public var source: String?
        public var line: Int?
        public var column: Int?

        public init(message: String? = nil, source: String? = nil, line: Int? = nil, column: Int? = nil) {
            self.message = message
            self.source = source
            self.line = line
            self.column = column
        }
    }

    /// Validated page metadata, safe to show and to store.
    public struct Metadata: Equatable {
        public var url: URL
        public var title: String?
        public var favicon: URL?
        public var themeColor: String?
        public var description: String?

        public init(url: URL, title: String? = nil, favicon: URL? = nil, themeColor: String? = nil, description: String? = nil) {
            self.url = url
            self.title = title
            self.favicon = favicon
            self.themeColor = themeColor
            self.description = description
        }

        public var json: JSONValue {
            ["url": .string(url.absoluteString), "title": JSONValue(title), "favicon": JSONValue(favicon?.absoluteString),
             "themeColor": JSONValue(themeColor), "description": JSONValue(description)]
        }
    }

    public static func metadata(_ p: DidChange, origin: URL?) throws -> Metadata {
        let url = try sameOrigin(p.url, origin: origin)
        let favicon = p.favicon.flatMap { raw -> URL? in
            guard raw.count <= maxURL, let u = URL(string: raw), u.scheme == "https" || u.scheme == "http" else { return nil }
            return u
        }
        let color = p.themeColor.flatMap { raw -> String? in
            raw.count <= 64 && raw.range(of: #"^[#a-zA-Z0-9(),.%\s-]+$"#, options: .regularExpression) != nil ? raw : nil
        }
        return Metadata(url: url, title: bounded(p.title, maxTitle), favicon: favicon, themeColor: color,
                        description: bounded(p.description, maxTitle))
    }

    public static func selection(_ p: Selection, origin: URL?) throws -> (url: URL, text: String) {
        (try sameOrigin(p.url, origin: origin), String(p.text.prefix(maxSelection)))
    }

    /// YouTube ids are 11 URL-safe characters; accepted only from YouTube's own origin.
    public static func videoID(_ p: VideoChanged, origin: URL?) throws -> String? {
        let url = try sameOrigin(p.url, origin: origin)
        guard let host = url.host?.lowercased(), host == "youtube.com" || host.hasSuffix(".youtube.com") else {
            throw IPCError.invalidParams("Video events are only accepted from YouTube")
        }
        guard let id = p.videoId else { return nil }
        guard id.range(of: #"^[A-Za-z0-9_-]{6,20}$"#, options: .regularExpression) != nil else { throw IPCError.invalidParams("Bad video id") }
        return id
    }

    /// The URL a page reports must match the frame's real origin (scheme, host, port). Without an
    /// origin from WebKit there's nothing to check it against, so it's refused (fail closed).
    public static func sameOrigin(_ raw: String, origin: URL?) throws -> URL {
        guard raw.count <= maxURL, let url = URL(string: raw), let scheme = url.scheme?.lowercased() else {
            throw IPCError.invalidParams("Invalid page URL")
        }
        guard let origin else { throw IPCError("origin_mismatch", "The frame has no origin to check the page URL against") }
        let port = { (u: URL) in u.port ?? (u.scheme == "https" ? 443 : u.scheme == "http" ? 80 : 0) }
        guard scheme == origin.scheme?.lowercased(), url.host?.lowercased() == origin.host?.lowercased(), port(url) == port(origin) else {
            throw IPCError("origin_mismatch", "Page URL does not match the frame's origin")
        }
        return url
    }

    /// A draft's field key and text, within FormDrafts' limits.
    public static func formDraft(field: String, text: String?) throws -> (field: String, text: String) {
        guard !field.isEmpty, field.count <= FormDrafts.maxFieldKey else { throw IPCError.invalidParams("Bad field") }
        let text = text ?? ""
        guard text.count <= FormDrafts.maxCharacters else { throw IPCError.invalidParams("Text too long") }
        return (field, text)
    }

    public static func bounded(_ value: String?, _ max: Int) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(max))
    }
}

extension IPCRouter {
    /// Registers a route whose payload must decode into `T`; anything else is rejected with `invalid_params`.
    public func on<T: Decodable>(_ type: String, from allowed: Set<IPCSource.Kind>, as payload: T.Type,
                                 _ handler: @escaping @MainActor (IPCContext, T) async throws -> JSONValue) {
        on(type, from: allowed) { context, raw in
            let value: T
            do {
                value = try raw.decode(T.self)
            } catch {
                throw IPCError.invalidParams("Invalid \(type) payload")
            }
            return try await handler(context, value)
        }
    }
}

extension IPCSource {
    /// Builds the origin URL WebKit reports for a frame (`WKSecurityOrigin`), never the page's own claim.
    public static func originURL(protocol scheme: String, host: String, port: Int) -> URL? {
        guard !scheme.isEmpty else { return nil }
        var parts = URLComponents()
        parts.scheme = scheme
        parts.host = host
        if port > 0 { parts.port = port }
        return parts.url
    }
}
