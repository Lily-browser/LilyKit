import Foundation
import Observation

/// Per-website preferences (zoom, dark mode, JavaScript, camera/microphone). Keyed by host;
/// encrypted at rest because the list reveals which sites you use. Values left nil follow the
/// defaults in Settings → Websites.
@MainActor @Observable
public final class SiteSettings {
    public enum DarkMode: String, Codable, CaseIterable, Sendable {
        /// Whatever the site and the system decide.
        case standard
        /// Ask the site for its own dark theme (`prefers-color-scheme: dark`).
        case dark
        /// Dark theme if the site has one, otherwise invert it (images and video stay natural).
        case forced
        /// Always light, even when macOS is in Dark Mode.
        case light

        public var title: String {
            switch self {
            case .standard: return "Default"
            case .dark: return "Dark"
            case .forced: return "Force Dark"
            case .light: return "Light"
            }
        }
    }

    public enum Permission: String, Codable, CaseIterable, Sendable {
        case ask, allow, deny
        public var title: String { rawValue.capitalized }
    }

    public struct Site: Codable, Equatable, Sendable {
        public var zoom: Double?
        public var darkMode: DarkMode?
        public var javaScript: Bool?
        public var camera: Permission?
        public var microphone: Permission?
        /// true: ads and trackers are allowed on this site.
        public var adsAllowed: Bool?

        public init(zoom: Double? = nil, darkMode: DarkMode? = nil, javaScript: Bool? = nil, camera: Permission? = nil, microphone: Permission? = nil, adsAllowed: Bool? = nil) {
            self.zoom = zoom
            self.darkMode = darkMode
            self.javaScript = javaScript
            self.camera = camera
            self.microphone = microphone
            self.adsAllowed = adsAllowed
        }

        public var isEmpty: Bool { self == Site() }
    }

    public private(set) var sites: [String: Site] = [:]
    @ObservationIgnored private let file: SealedFile?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    public init(directory: URL?, keys: KeyStore = KeychainKeyStore()) {
        file = directory.map {
            SealedFile(url: $0.appendingPathComponent("sites.sealed"), keyName: "sites", purpose: "dev.lily.sites.v1", keys: keys)
        }
    }

    public func load() async {
        guard let file else { return }
        do {
            if let data = try await file.read() { sites = try JSONDecoder().decode([String: Site].self, from: data) }
        } catch {
            Log.app.error("Site settings could not be decrypted; starting fresh: \(String(describing: error), privacy: .public)")
            file.deleteCorrupt()
        }
    }

    /// `www.example.com` and `example.com` share settings.
    public nonisolated static func key(for url: URL?) -> String? {
        guard let host = url?.host?.lowercased(), url?.scheme == "https" || url?.scheme == "http" else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// What decisions are stored under: the host, plus ":port" for a non-default port and "http://" for
    /// plain HTTP, so another origin of the same host never inherits a camera, microphone or script
    /// decision. (`www.` still merges with the bare host.)
    public nonisolated static func storageKey(for url: URL?) -> String? {
        guard let host = key(for: url), let url else { return nil }
        var out = url.scheme == "http" ? "http://" + host : host
        if let port = url.port, port != (url.scheme == "http" ? 80 : 443) { out += ":\(port)" }
        return out
    }

    public func site(for url: URL?) -> Site { Self.storageKey(for: url).flatMap { sites[$0] } ?? Site() }

    public func update(_ url: URL?, _ change: (inout Site) -> Void) {
        guard let key = Self.storageKey(for: url) else { return }
        var site = sites[key] ?? Site()
        change(&site)
        sites[key] = site.isEmpty ? nil : site
        scheduleSave()
    }

    public func reset(_ key: String) {
        sites[key] = nil
        scheduleSave()
    }

    public func removeAll() {
        sites.removeAll()
        scheduleSave()
    }

    // MARK: Effective values (site value, else the default from Settings)

    public func zoom(for url: URL?) -> Double {
        site(for: url).zoom ?? Self.defaultZoom
    }

    public func darkMode(for url: URL?) -> DarkMode {
        site(for: url).darkMode ?? Self.defaultDarkMode
    }

    public func allowsJavaScript(for url: URL?) -> Bool {
        site(for: url).javaScript ?? true
    }

    public func adsAllowed(for url: URL?) -> Bool {
        site(for: url).adsAllowed ?? false
    }

    public func permission(_ kind: KeyPath<Site, Permission?>, for url: URL?) -> Permission {
        site(for: url)[keyPath: kind] ?? .ask
    }

    /// The zoom levels ⌘− / ⌘+, the site-settings popover and Settings → Websites → Default zoom
    /// all use, Safari-like.
    public nonisolated static let zoomLevels: [Double] = [0.5, 0.67, 0.75, 0.85, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0]

    /// The next level from `current` in a direction. A zoom between levels (an older step, a
    /// stored site zoom) goes to the nearest level that way; at either end it stays put.
    public nonisolated static func zoomLevel(after current: Double, zoomingIn: Bool) -> Double {
        let tolerance = 0.005
        if zoomingIn { return zoomLevels.first { $0 > current + tolerance } ?? max(current, zoomLevels[zoomLevels.count - 1]) }
        return zoomLevels.last { $0 < current - tolerance } ?? min(current, zoomLevels[0])
    }

    /// True at the smallest or largest level (or beyond it).
    public nonisolated static func isZoomLimit(_ zoom: Double) -> Bool {
        zoom <= zoomLevels[0] + 0.005 || zoom >= zoomLevels[zoomLevels.count - 1] - 0.005
    }

    public static var defaultZoom: Double {
        let stored = UserDefaults.standard.double(forKey: Preferences.Key.defaultZoom)
        return stored > 0 ? stored : 1
    }

    public static var defaultDarkMode: DarkMode {
        UserDefaults.standard.string(forKey: Preferences.Key.defaultDarkMode).flatMap(DarkMode.init(rawValue:)) ?? .standard
    }

    private func scheduleSave() {
        guard let file else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await Self.write(self.sites, to: file)
        }
    }

    /// Writes pending changes now (quit, tests) instead of after the debounce.
    public func flush() async {
        saveTask?.cancel()
        guard let file else { return }
        await Self.write(sites, to: file)
    }

    private static func write(_ snapshot: [String: Site], to file: SealedFile) async {
        let ticket = file.reserve() // ordered by when the snapshot was taken, not when it's written
        await Task.detached(priority: .utility) {
            do {
                if snapshot.isEmpty { file.delete(ticket: ticket) } else { try await file.write(JSONEncoder().encode(snapshot), ticket: ticket) }
            } catch {
                Log.app.error("Site settings save failed: \(String(describing: error), privacy: .public)")
            }
        }.value
    }
}
