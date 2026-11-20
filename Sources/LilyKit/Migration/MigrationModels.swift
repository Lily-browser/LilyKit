import Foundation

/// Browsers Lily can import from, and where each keeps its data under `~/Library`.
public enum SourceBrowser: String, CaseIterable, Identifiable, Sendable, Codable {
    case chrome, safari, arc, zen, dia

    public var id: String { rawValue }

    public enum Engine: Sendable { case chromium, safari, firefox }

    public var displayName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .safari: return "Safari"
        case .arc: return "Arc"
        case .zen: return "Zen"
        case .dia: return "Dia"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .safari: return "com.apple.Safari"
        case .arc: return "company.thebrowser.Browser"
        case .zen: return "app.zen-browser.zen"
        case .dia: return "company.thebrowser.dia"
        }
    }

    /// Shown when the app isn't installed and its icon can't be looked up.
    public var symbol: String {
        switch self {
        case .chrome: return "globe"
        case .safari: return "safari"
        case .arc: return "circle.hexagongrid"
        case .zen: return "leaf"
        case .dia: return "sparkle"
        }
    }

    public var engine: Engine {
        switch self {
        case .chrome, .arc, .dia: return .chromium
        case .safari: return .safari
        case .zen: return .firefox // Zen is built on Firefox, not Chromium
        }
    }

    /// The folder the user grants access to: Application Support for most, `~/Library/Safari` for Safari.
    public var root: MigrationRoot { self == .safari ? .safari : .applicationSupport }

    /// The browser's folder, relative to its root.
    public var relativePath: String {
        switch self {
        case .chrome: return "Google/Chrome"
        case .safari: return ""
        case .arc: return "Arc"
        case .zen: return "zen"
        case .dia: return "Dia"
        }
    }

    /// Chromium "User Data" folder inside the browser folder ("" when the browser folder is it).
    public var userDataPath: String {
        switch self {
        case .arc, .dia: return "User Data"
        default: return ""
        }
    }

    public var supportsSpaces: Bool { self == .arc }
}

/// A folder outside the sandbox that the user grants once.
public enum MigrationRoot: String, CaseIterable, Sendable, Codable {
    case applicationSupport, safari

    public var displayPath: String { self == .safari ? "~/Library/Safari" : "~/Library/Application Support" }
    public var relativeToHome: String { self == .safari ? "Library/Safari" : "Library/Application Support" }
}

/// What to bring over from one browser.
public struct MigrationOptions: Equatable, Sendable {
    public var bookmarks = true
    public var history = true
    public var spaces = true
}

public struct ImportedBookmark: Equatable, Sendable {
    public var title: String
    public var url: URL
    /// Folder names from the top ("Bookmarks Bar", "Work").
    public var folders: [String]

    public init(title: String, url: URL, folders: [String]) {
        self.title = title
        self.url = url
        self.folders = folders
    }
}

public struct ImportedVisit: Equatable, Sendable {
    public var url: URL
    public var title: String
    public var visitCount: Int
    public var lastVisit: Date

    public init(url: URL, title: String, visitCount: Int, lastVisit: Date) {
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisit = lastVisit
    }
}

public struct ImportedSpace: Equatable, Sendable {
    public struct Tab: Equatable, Sendable {
        public var title: String
        public var url: URL
        public var pinned: Bool

        public init(title: String, url: URL, pinned: Bool) {
            self.title = title
            self.url = url
            self.pinned = pinned
        }
    }

    public var name: String
    public var tabs: [Tab]

    public init(name: String, tabs: [Tab]) {
        self.name = name
        self.tabs = tabs
    }
}

/// Everything read from one browser.
public struct BrowserData: Equatable, Sendable {
    public var bookmarks: [ImportedBookmark] = []
    public var history: [ImportedVisit] = []
    public var spaces: [ImportedSpace] = []

    public init(bookmarks: [ImportedBookmark] = [], history: [ImportedVisit] = [], spaces: [ImportedSpace] = []) {
        self.bookmarks = bookmarks
        self.history = history
        self.spaces = spaces
    }
}

/// What a scan found, before importing.
public struct BrowserScan: Equatable, Sendable {
    public var bookmarks: Int
    public var history: Int
    public var spaces: Int

    public init(bookmarks: Int, history: Int, spaces: Int) {
        self.bookmarks = bookmarks
        self.history = history
        self.spaces = spaces
    }
}

/// Address handling for imports and de-duplication.
public enum URLNormalizer {
    public static let maxLength = 4_096

    /// Only web pages are imported; `javascript:` bookmarklets, `file:` and browser-internal pages aren't.
    public static func isImportable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host?.isEmpty == false else { return false }
        return url.absoluteString.count <= maxLength
    }

    /// The address to store: scheme and host lowercased, default ports and tracking parameters
    /// removed, and a trailing slash dropped from paths (not from the root).
    public static func clean(_ url: URL) -> URL? {
        guard isImportable(url), var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        if let items = parts.queryItems {
            let kept = items.filter { !LinkTracking.isTracking($0.name) }
            parts.queryItems = kept.isEmpty ? nil : kept
        }
        if parts.path.count > 1, parts.path.hasSuffix("/") { parts.path.removeLast() }
        if parts.path.isEmpty { parts.path = "/" }
        return parts.url
    }

    /// Two addresses with the same key are the same page (fragment ignored).
    public static func key(_ url: URL) -> String {
        guard var parts = URLComponents(url: clean(url) ?? url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.fragment = nil
        return parts.string ?? url.absoluteString
    }
}
