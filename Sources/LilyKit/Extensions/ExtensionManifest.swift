import Foundation

/// An extension's manifest.json (Manifest V2 and V3), decoded leniently: a field with an
/// unexpected shape is treated as absent rather than failing the whole manifest, the way browsers
/// tolerate store packages. Only `name` and `version` are required.
public struct ExtensionManifest: Codable, Sendable, Equatable {
    public struct ContentScript: Codable, Sendable, Equatable {
        public var matches: [String]
        public var excludeMatches: [String]?
        public var js: [String]?
        public var css: [String]?
        public var runAt: String?
        public var allFrames: Bool?

        public enum CodingKeys: String, CodingKey {
            case matches, js, css
            case excludeMatches = "exclude_matches", runAt = "run_at", allFrames = "all_frames"
        }
    }

    public struct Background: Codable, Sendable, Equatable {
        public var serviceWorker: String?
        public var scripts: [String]?
        public var page: String?

        public enum CodingKeys: String, CodingKey { case scripts, page, serviceWorker = "service_worker" }
    }

    public struct Action: Codable, Sendable, Equatable {
        public var defaultPopup: String?
        public var defaultTitle: String?

        public enum CodingKeys: String, CodingKey { case defaultPopup = "default_popup", defaultTitle = "default_title" }
    }

    /// `content_security_policy`: a string in MV2, `{ extension_pages, sandbox }` in MV3.
    public struct SecurityPolicy: Codable, Sendable, Equatable {
        public var extensionPages: String?
        public var sandbox: String?

        public enum CodingKeys: String, CodingKey { case extensionPages = "extension_pages", sandbox }

        public init(extensionPages: String?, sandbox: String?) {
            self.extensionPages = extensionPages
            self.sandbox = sandbox
        }

        public init(from decoder: Decoder) throws {
            if let legacy = try? decoder.singleValueContainer().decode(String.self) {
                self.init(extensionPages: legacy, sandbox: nil)
                return
            }
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.init(extensionPages: try? container.decodeIfPresent(String.self, forKey: .extensionPages),
                      sandbox: try? container.decodeIfPresent(String.self, forKey: .sandbox))
        }
    }

    public struct ExternallyConnectable: Codable, Sendable, Equatable {
        public var matches: [String]?
        public var ids: [String]?
    }

    public var manifestVersion: Int
    public var name: String
    public var version: String
    public var description: String?
    public var defaultLocale: String?
    public var permissions: [String]
    public var optionalPermissions: [String]
    public var hostPermissions: [String]
    public var contentScripts: [ContentScript]
    public var background: Background?
    public var action: Action?
    public var icons: [String: String]
    public var contentSecurityPolicy: SecurityPolicy?
    public var externallyConnectable: ExternallyConnectable?
    public var updateURL: String?

    public enum CodingKeys: String, CodingKey {
        case name, version, description, permissions, background, action, icons
        case manifestVersion = "manifest_version", defaultLocale = "default_locale"
        case optionalPermissions = "optional_permissions", hostPermissions = "host_permissions"
        case contentScripts = "content_scripts", browserAction = "browser_action"
        case contentSecurityPolicy = "content_security_policy", externallyConnectable = "externally_connectable"
        case updateURL = "update_url"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func lenient<T: Decodable>(_ type: T.Type, _ key: CodingKeys) -> T? { (try? c.decodeIfPresent(type, forKey: key)) ?? nil }
        manifestVersion = lenient(Int.self, .manifestVersion) ?? 2
        name = try c.decode(String.self, forKey: .name)
        version = try c.decode(String.self, forKey: .version)
        description = lenient(String.self, .description)
        defaultLocale = lenient(String.self, .defaultLocale)
        // MV2 mixes host patterns into `permissions`; only strings count either way.
        permissions = lenient([LenientString].self, .permissions)?.compactMap(\.value) ?? []
        optionalPermissions = lenient([LenientString].self, .optionalPermissions)?.compactMap(\.value) ?? []
        hostPermissions = lenient([String].self, .hostPermissions) ?? []
        contentScripts = lenient([ContentScript].self, .contentScripts) ?? []
        background = lenient(Background.self, .background)
        action = lenient(Action.self, .action) ?? lenient(Action.self, .browserAction)
        icons = lenient([String: String].self, .icons) ?? [:]
        contentSecurityPolicy = lenient(SecurityPolicy.self, .contentSecurityPolicy)
        externallyConnectable = lenient(ExternallyConnectable.self, .externallyConnectable)
        updateURL = lenient(String.self, .updateURL)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(manifestVersion, forKey: .manifestVersion)
        try c.encode(name, forKey: .name)
        try c.encode(version, forKey: .version)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(defaultLocale, forKey: .defaultLocale)
        try c.encode(permissions, forKey: .permissions)
        try c.encode(optionalPermissions, forKey: .optionalPermissions)
        try c.encode(hostPermissions, forKey: .hostPermissions)
        try c.encode(contentScripts, forKey: .contentScripts)
        try c.encodeIfPresent(background, forKey: .background)
        try c.encodeIfPresent(action, forKey: .action)
        try c.encode(icons, forKey: .icons)
        try c.encodeIfPresent(contentSecurityPolicy, forKey: .contentSecurityPolicy)
        try c.encodeIfPresent(externallyConnectable, forKey: .externallyConnectable)
        try c.encodeIfPresent(updateURL, forKey: .updateURL)
    }

    /// A string array entry that may also be an object (some MV2 manifests); non-strings are dropped.
    private struct LenientString: Decodable {
        public let value: String?
        public init(from decoder: Decoder) throws { value = try? decoder.singleValueContainer().decode(String.self) }
    }

    /// Host patterns from both `host_permissions` (MV3) and `permissions` (MV2).
    public var allHostPatterns: [String] {
        hostPermissions + permissions.filter { $0 == "<all_urls>" || $0.contains("://") }
    }

    // MARK: Reading

    /// Parses the package's manifest (tolerating a UTF-8 BOM) and resolves `__MSG_key__` strings
    /// from its default locale's messages.json.
    public static func parse(_ package: ExtensionPackage) -> ExtensionManifest? {
        guard var data = package.manifest else { return nil }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data.removeFirst(3) }
        guard var manifest = try? JSONDecoder().decode(ExtensionManifest.self, from: data) else { return nil }
        let messages = localeMessages(package, locale: manifest.defaultLocale)
        manifest.name = localized(manifest.name, messages)
        manifest.description = manifest.description.map { localized($0, messages) }
        if let title = manifest.action?.defaultTitle { manifest.action?.defaultTitle = localized(title, messages) }
        return manifest
    }

    public static func localeMessages(_ package: ExtensionPackage, locale: String?) -> [String: String] {
        let candidates = [Locale.current.identifier.replacingOccurrences(of: "-", with: "_"),
                          Locale.current.language.languageCode?.identifier, locale, "en"].compactMap { $0 }
        for candidate in candidates {
            guard let data = package.files["_locales/\(candidate)/messages.json"],
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            return object.reduce(into: [:]) { result, entry in
                if let message = (entry.value as? [String: Any])?["message"] as? String { result[entry.key.lowercased()] = message }
            }
        }
        return [:]
    }

    public static func localized(_ text: String, _ messages: [String: String]) -> String {
        guard text.hasPrefix("__MSG_"), text.hasSuffix("__"), text.count > 8 else { return text }
        let key = String(text.dropFirst(6).dropLast(2)).lowercased()
        return messages[key] ?? text
    }

    /// The best icon file for `size` points, if the manifest declares any.
    public func iconPath(for size: Int) -> String? {
        let sized = icons.compactMap { key, path in Int(key).map { ($0, path) } }.sorted { $0.0 < $1.0 }
        return (sized.first { $0.0 >= size } ?? sized.last)?.1
    }
}

/// A WebExtension match pattern (`<all_urls>`, `*://*.example.com/path*`), for compatibility-mode
/// content scripts.
public struct ExtensionMatchPattern: Sendable, Equatable {
    public let scheme: String
    public let host: String
    public let path: String

    public init?(_ pattern: String) {
        if pattern == "<all_urls>" { scheme = "*"; host = "*"; path = "/*"; return }
        guard let separator = pattern.range(of: "://") else { return nil }
        let scheme = String(pattern[..<separator.lowerBound]).lowercased()
        let rest = pattern[separator.upperBound...]
        guard ["*", "http", "https", "file"].contains(scheme), let slash = rest.firstIndex(of: "/") else { return nil }
        let host = String(rest[..<slash]).lowercased()
        guard host == "*" || !host.dropFirst(host.hasPrefix("*.") ? 2 : 0).contains("*") else { return nil }
        self.scheme = scheme
        self.host = host
        self.path = String(rest[slash...])
    }

    public func matches(_ url: URL) -> Bool {
        guard let urlScheme = url.scheme?.lowercased() else { return false }
        if scheme == "*" { guard urlScheme == "http" || urlScheme == "https" else { return false } } else if scheme != urlScheme { return false }
        let urlHost = url.host?.lowercased() ?? ""
        if host != "*" {
            if host.hasPrefix("*.") {
                let base = String(host.dropFirst(2))
                guard urlHost == base || urlHost.hasSuffix("." + base) else { return false }
            } else if urlHost != host { return false }
        }
        var target = url.path.isEmpty ? "/" : url.path
        if let query = url.query { target += "?" + query }
        return Self.glob(path, target)
    }

    /// `*` matches any run of characters; everything else is literal.
    public static func glob(_ pattern: String, _ text: String) -> Bool {
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return pattern == text }
        guard text.hasPrefix(parts[0]) else { return false }
        var rest = text.dropFirst(parts[0].count)
        for part in parts.dropFirst().dropLast() where !part.isEmpty {
            guard let range = rest.range(of: part) else { return false }
            rest = rest[range.upperBound...]
        }
        return rest.hasSuffix(parts.last!)
    }
}
