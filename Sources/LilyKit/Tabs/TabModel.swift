import Foundation

/// A workspace with its own tabs, a symbol and a color.
public struct Space: Identifiable, Equatable, Hashable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var symbol: String
    public var colorHex: String
    /// Separate logins: the space's tabs get their own cookies, storage and cache, so one site can be
    /// signed in to with different accounts in different spaces. Optional so sessions saved before it
    /// existed still decode.
    public var separateLogins: Bool?
    public var hasSeparateLogins: Bool { separateLogins ?? false }

    public init(id: UUID = UUID(), name: String, symbol: String, colorHex: String, separateLogins: Bool? = nil) {
        self.id = id; self.name = name; self.symbol = symbol; self.colorHex = colorHex; self.separateLogins = separateLogins
    }

    private enum CodingKeys: String, CodingKey { case id, name, symbol, colorHex, color, separateLogins }

    /// Sessions written by Lily-macos before this type was shared store the color under `color`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        symbol = try c.decode(String.self, forKey: .symbol)
        guard let hex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? c.decodeIfPresent(String.self, forKey: .color) else {
            throw DecodingError.keyNotFound(CodingKeys.colorHex, .init(codingPath: decoder.codingPath, debugDescription: "no colorHex or color"))
        }
        colorHex = hex
        separateLogins = try c.decodeIfPresent(Bool.self, forKey: .separateLogins)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(symbol, forKey: .symbol)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encodeIfPresent(separateLogins, forKey: .separateLogins)
    }

    /// Symbols offered when making or editing a space.
    public static let symbols = ["circle.fill", "house.fill", "briefcase.fill", "book.fill", "gamecontroller.fill", "music.note",
                                 "paintbrush.fill", "graduationcap.fill", "cart.fill", "airplane", "heart.fill", "star.fill"]

    public static let defaults = [
        Space(name: "Personal", symbol: "person.fill", colorHex: "#5E5CE6"),
        Space(name: "Work", symbol: "briefcase.fill", colorHex: "#0A84FF"),
        Space(name: "Play", symbol: "gamecontroller.fill", colorHex: "#34C759"),
    ]
}

/// Platform-neutral, metadata-first tab: enough to list, search, restore and put to sleep. The web view
/// and platform dialogs live in the apps; thousands of these cost a few hundred bytes each.
public struct TabModel: Identifiable, Equatable, Hashable, Sendable, Codable {
    public let id: UUID
    public var spaceID: UUID
    public var url: URL?
    public var title: String
    public var isPinned: Bool
    /// Group id when the tab is a member of a split view.
    public var splitID: UUID?
    public var isSleeping: Bool
    public var lastActivated: Date

    public init(id: UUID = UUID(), spaceID: UUID, url: URL? = nil, title: String = "", isPinned: Bool = false,
                splitID: UUID? = nil, isSleeping: Bool = false, lastActivated: Date = Date()) {
        self.id = id; self.spaceID = spaceID; self.url = url; self.title = title; self.isPinned = isPinned
        self.splitID = splitID; self.isSleeping = isSleeping; self.lastActivated = lastActivated
    }

    private enum CodingKeys: String, CodingKey { case id, spaceID, url, title, isPinned, splitID, isSleeping, lastActivated }

    /// Sessions written before split/sleep state existed still decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        spaceID = try c.decode(UUID.self, forKey: .spaceID)
        url = try c.decodeIfPresent(URL.self, forKey: .url)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        splitID = try c.decodeIfPresent(UUID.self, forKey: .splitID)
        isSleeping = try c.decodeIfPresent(Bool.self, forKey: .isSleeping) ?? false
        lastActivated = try c.decodeIfPresent(Date.self, forKey: .lastActivated) ?? Date()
    }

    /// What lists show: the title, else the host, else "New Tab".
    public var displayTitle: String {
        if !title.isEmpty { return title }
        return url?.host ?? "New Tab"
    }

    /// "example.com/path" without scheme or www, as the address pill shows it.
    public var shortAddress: String {
        guard let url, let host = url.host else { return "" }
        let path = url.path == "/" ? "" : url.path
        return host.replacingOccurrences(of: "www.", with: "", options: .anchored) + path
    }
}

/// When a background tab may be put to sleep. Pure policy; the app owns timers and the web view.
public enum TabSleepPolicy {
    public static let defaultMinutes = 15

    public static func isEligible(_ tab: TabModel, isActive: Bool, isBusy: Bool, now: Date = Date(), idleMinutes: Int = defaultMinutes) -> Bool {
        guard !isActive, !isBusy, !tab.isSleeping, tab.splitID == nil, idleMinutes > 0 else { return false }
        guard let scheme = tab.url?.scheme, scheme == "http" || scheme == "https" else { return false }
        return now.timeIntervalSince(tab.lastActivated) >= TimeInterval(idleMinutes * 60)
    }

    /// The earliest moment any of `tabs` becomes eligible, or nil if none can.
    public static func nextDue(_ tabs: [TabModel], activeID: UUID?, idleMinutes: Int = defaultMinutes) -> Date? {
        guard idleMinutes > 0 else { return nil }
        return tabs.filter { $0.id != activeID && !$0.isSleeping && $0.splitID == nil && ["http", "https"].contains($0.url?.scheme ?? "") }
            .map { $0.lastActivated.addingTimeInterval(TimeInterval(idleMinutes * 60)) }.min()
    }
}

/// What survives a relaunch: spaces, tabs and the selection.
public struct TabSession: Codable, Equatable, Sendable {
    public var spaces: [Space]
    public var tabs: [TabModel]
    public var activeID: UUID
    public var currentSpaceID: UUID

    public init(spaces: [Space], tabs: [TabModel], activeID: UUID, currentSpaceID: UUID) {
        self.spaces = spaces; self.tabs = tabs; self.activeID = activeID; self.currentSpaceID = currentSpaceID
    }

    /// Usable only if every tab belongs to a space, the selection exists and something is selectable.
    public var isValid: Bool {
        guard !spaces.isEmpty, !tabs.isEmpty else { return false }
        let spaceIDs = Set(spaces.map(\.id))
        return spaceIDs.contains(currentSpaceID) && tabs.allSatisfy { spaceIDs.contains($0.spaceID) } && tabs.contains { $0.id == activeID }
    }
}

/// Tab URLs can carry tokens, so the session is stored encrypted (`SealedFile`), never as plaintext.
public struct TabSessionStore: Sendable {
    private let file: SealedFile

    public init(directory: URL, keys: KeyStore) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = SealedFile(url: directory.appendingPathComponent("session.sealed"), keyName: "session", purpose: "tab session", keys: keys)
    }

    public func load() async -> TabSession? {
        let data: Data?
        do { data = try await file.read() } catch {
            // A Keychain failure (locked, unavailable) must not cost the user their session; only a file that fails to open is dropped.
            if !(error is KeychainError) { file.deleteCorrupt() }
            return nil
        }
        guard let data, let session = try? JSONDecoder().decode(TabSession.self, from: data), session.isValid else { return nil }
        return session
    }

    public func save(_ session: TabSession) async {
        guard session.isValid, let data = try? JSONEncoder().encode(session) else { return }
        try? await file.write(data, ticket: file.reserve())
    }

    public func delete() { file.delete() }
}
