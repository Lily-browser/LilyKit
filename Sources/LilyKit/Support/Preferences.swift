import Foundation

/// User settings stored in UserDefaults. Keys are shared with the SwiftUI settings window
/// (`@AppStorage`) and `AssistantConfiguration`, so changing one here changes both.
public enum Preferences {
    public enum Key {
        public static let searchEngine = "SearchEngine"
        public static let homepage = "Homepage"
        public static let ollamaHost = "OllamaHost"
        /// Deleted Spaces whose own data store WebKit hasn't removed yet (identifiers only), retried at launch.
        public static let pendingSpaceStoreRemovals = "PendingSpaceStoreRemovals"
        public static let agentModel = "AgentModel"
        /// Comma-separated base64 SHA-256 SPKI pins for a remote (HTTPS) Ollama.
        public static let ollamaPins = "OllamaPinnedKeys"
        /// Days of browsing history to keep; 0 keeps everything.
        public static let historyRetentionDays = "HistoryRetentionDays"
        public static let defaultZoom = "DefaultPageZoom"
        public static let defaultDarkMode = "DefaultWebsiteAppearance"
        public static let httpsFirst = "HTTPSFirst"
        public static let restoreSession = "RestoreTabsOnLaunch"
        public static let newTabsNextToCurrent = "OpenNewTabsNextToCurrent"
        public static let clearHistoryOnQuit = "ClearHistoryOnQuit"
        public static let clearWebsiteDataOnQuit = "ClearWebsiteDataOnQuit"
        public static let adBlock = "BlockAdsAndTrackers"
        public static let haptics = "HapticFeedback"
        /// Minutes before an unused background tab sleeps; 0 means never.
        public static let sleepTabsAfter = "SleepTabsAfterMinutes"
        /// Fraudulent-site warnings; on by default (Preferences.warnsAboutFraudulentSites).
        public static let fraudulentSiteWarnings = "FraudulentSiteWarnings"
        /// Links from other apps open in Little Lily (on by default, as in Arc) or as tabs.
        public static let linksOpenInLittleLily = "LinksOpenInLittleLily"
        /// Handoff of the active page to your other devices; off by default (it shares the page's
        /// address and title through your Apple account).
        public static let handoff = "HandoffEnabled"
        /// Link tracking protection (LinkTracking); on by default.
        public static let removeLinkTracking = "RemoveLinkTracking"
        /// Web Inspector, Inspect Element and the Develop menu (WebInspector); off by default.
        public static let webDeveloperFeatures = "WebDeveloperFeatures"
        /// Minutes before a split pane you aren't using is paused (PaneFreezer); 0 = never.
        public static let pauseIdlePanesAfter = "PauseIdleSplitPanesAfterMinutes"
        /// Replaced by `filterLists`; read once to carry the old EasyList switch over.
        public static let easyList = "UseEasyList"
        /// Ids of the downloadable filter lists that are turned on (see `FilterLists`).
        public static let filterLists = "FilterLists"
        public static let filterListsUpdated = "FilterListsUpdated"
        /// Content-rule list identifiers compiled from the filter lists, and which lists they came from.
        public static let filterListsCompiled = "FilterListsCompiled"
        public static let filterListsCompiledFrom = "FilterListsCompiledFrom"
        /// Search-engine suggestions while typing in the command bar; on by default (SearchSuggestions).
        public static let searchSuggestions = "SearchEngineSuggestions"
        /// How many engine suggestion rows the command bar shows (0–5, 5 by default).
        public static let searchSuggestionRows = "SearchEngineSuggestionRows"
        /// What ⌘T opens (NewTabAction): the command bar by default.
        public static let newTabAction = "NewTabAction"
        /// Which tab is shown after closing the active one (TabStore.AfterClose): last used by default.
        public static let afterClosingTab = "AfterClosingTab"
        /// ⌘-click / middle-click opens links in the background (default; ⇧ flips it).
        public static let linksOpenInBackground = "LinksOpenInBackground"
        /// Ask before ⌘Q quits with several windows or many tabs; off by default.
        public static let confirmBeforeQuitting = "ConfirmBeforeQuitting"
        /// Two-finger swipes on the sidebar switch spaces; on by default.
        public static let swipeBetweenSpaces = "SwipeBetweenSpaces"
    }

    public enum SearchEngine: String, CaseIterable, Identifiable, Sendable {
        case google, duckDuckGo, bing, kagi, ecosia

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .google: return "Google"
            case .duckDuckGo: return "DuckDuckGo"
            case .bing: return "Bing"
            case .kagi: return "Kagi"
            case .ecosia: return "Ecosia"
            }
        }

        public var template: String {
            switch self {
            case .google: return "https://www.google.com/search?q=%s"
            case .duckDuckGo: return "https://duckduckgo.com/?q=%s"
            case .bing: return "https://www.bing.com/search?q=%s"
            case .kagi: return "https://kagi.com/search?q=%s"
            case .ecosia: return "https://www.ecosia.org/search?q=%s"
            }
        }
    }

    public static let defaultHomepage = "https://www.youtube.com"

    /// Bool preferences that default to on when never set.
    public static func flag(_ key: String, default value: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    public static var httpsFirstEnabled: Bool { flag(Key.httpsFirst, default: true) }
    public static var restoresSession: Bool { flag(Key.restoreSession, default: true) }
    public static var opensTabsNextToCurrent: Bool { flag(Key.newTabsNextToCurrent, default: true) }

    /// DuckDuckGo by default: it doesn't build a profile of your searches. Changing the engine in
    /// Settings → General is kept; only an unset choice uses the default.
    public static let defaultSearchEngine = SearchEngine.duckDuckGo

    public static var searchEngine: SearchEngine {
        UserDefaults.standard.string(forKey: Key.searchEngine).flatMap(SearchEngine.init(rawValue:)) ?? defaultSearchEngine
    }

    /// Fraudulent-site warnings (WebKit's Safe Browsing, relayed by Apple). On by default.
    public static var warnsAboutFraudulentSites: Bool { flag(Key.fraudulentSiteWarnings, default: true) }

    /// Sends what you type in the command bar to your search engine for suggestions (not in
    /// private windows, never with Kagi). On by default.
    public static var searchSuggestionsEnabled: Bool { flag(Key.searchSuggestions, default: true) }

    /// Engine suggestion rows in the command bar, 0–5. 0 shows none (and sends nothing), but the
    /// switch above is what turns suggestions off.
    public static var searchSuggestionRows: Int {
        let stored = UserDefaults.standard.object(forKey: Key.searchSuggestionRows) as? Int ?? SearchSuggestions.maxSuggestions
        return min(SearchSuggestions.maxSuggestions, max(0, stored))
    }

    public static var linksOpenInBackground: Bool { flag(Key.linksOpenInBackground, default: true) }
    public static var swipesBetweenSpaces: Bool { flag(Key.swipeBetweenSpaces, default: true) }
    public static var confirmsBeforeQuitting: Bool { flag(Key.confirmBeforeQuitting, default: false) }

    /// Address-bar resolver using the user's search engine.
    public static var urlResolver: URLResolver { URLResolver(searchTemplate: searchEngine.template) }

    public static var homepage: URL? {
        let raw = UserDefaults.standard.string(forKey: Key.homepage) ?? defaultHomepage
        return raw.isEmpty ? nil : urlResolver.resolve(raw)
    }
}

public enum AppInfo {
    /// `CFBundleShortVersionString` of the packaged app, or "dev" for `swift run` builds.
    public static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Running from a .app bundle. Packaged builds ignore developer overrides (environment
    /// variables, PATH, repository lookup) so nothing outside the signed bundle can change
    /// which scripts the app injects or which executables it runs.
    public static var isPackaged: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    public static let helpURL = URL(string: "https://github.com/pwngoblin/Lily#readme")!
}
