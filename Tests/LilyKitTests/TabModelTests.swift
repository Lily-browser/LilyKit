import CryptoKit
import Foundation
import Testing
@testable import LilyKit

private struct FixedKeys: KeyStore {
    func key(named name: String) async throws -> SymmetricKey { SymmetricKey(data: Data(repeating: 7, count: 32)) }
    func deleteKey(named name: String) async throws {}
}
private struct FailingKeys: KeyStore {
    func key(named name: String) async throws -> SymmetricKey { throw KeychainError(status: -25308, operation: "read") }
    func deleteKey(named name: String) async throws {}
}

@Suite struct TabModelTests {
    let space = Space(name: "A", symbol: "star", colorHex: "#000000")

    func session() -> TabSession {
        let tab = TabModel(spaceID: space.id, url: URL(string: "https://www.example.com/a?token=secret"), title: "Hi")
        return TabSession(spaces: [space], tabs: [tab], activeID: tab.id, currentSpaceID: space.id)
    }

    @Test func titles() {
        #expect(TabModel(spaceID: space.id).displayTitle == "New Tab")
        let t = TabModel(spaceID: space.id, url: URL(string: "https://www.example.com/x"))
        #expect(t.displayTitle == "www.example.com")
        #expect(t.shortAddress == "example.com/x")
    }

    @Test func oldTabsDecode() throws {
        let json = #"{"id":"\#(UUID())","spaceID":"\#(space.id)","title":"t"}"#
        let tab = try JSONDecoder().decode(TabModel.self, from: Data(json.utf8))
        #expect(!tab.isPinned && tab.splitID == nil && !tab.isSleeping)
    }

    @Test func validity() {
        var s = session()
        #expect(s.isValid)
        s.activeID = UUID()
        #expect(!s.isValid)
    }

    @Test func sleepPolicy() {
        let now = Date()
        var tab = TabModel(spaceID: space.id, url: URL(string: "https://a.com"), lastActivated: now.addingTimeInterval(-20 * 60))
        #expect(TabSleepPolicy.isEligible(tab, isActive: false, isBusy: false, now: now))
        #expect(!TabSleepPolicy.isEligible(tab, isActive: true, isBusy: false, now: now))
        #expect(!TabSleepPolicy.isEligible(tab, isActive: false, isBusy: true, now: now))
        tab.splitID = UUID()
        #expect(!TabSleepPolicy.isEligible(tab, isActive: false, isBusy: false, now: now))
        tab.splitID = nil; tab.url = URL(string: "file:///x")
        #expect(!TabSleepPolicy.isEligible(tab, isActive: false, isBusy: false, now: now))
    }

    @Test func memoryPressureIgnoresIdleTimeButNotVisibility() {
        let now = Date()
        func eligible(active: Bool = false, threshold: TimeInterval? = 900, force: Bool) -> Bool {
            TabSleepPolicy.isEligible(lastActivated: now, now: now, threshold: threshold, isActive: active, inSplit: false,
                                      isSleeping: false, scheme: "https", force: force)
        }
        #expect(!eligible(force: false))
        #expect(eligible(force: true) && eligible(threshold: nil, force: true))
        #expect(!eligible(active: true, force: true))
        #expect(!eligible(threshold: nil, force: false)) // "Never"
    }

    @Test func sealedRoundTripIsNotPlaintext() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TabSessionStore(directory: dir, keys: FixedKeys())
        let s = session()
        await store.save(s)
        #expect(await store.load() == s)
        let raw = try Data(contentsOf: dir.appendingPathComponent("session.sealed"))
        #expect(raw.range(of: Data("secret".utf8)) == nil)
    }

    @Test func keychainFailureKeepsFile() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        await TabSessionStore(directory: dir, keys: FixedKeys()).save(session())
        #expect(await TabSessionStore(directory: dir, keys: FailingKeys()).load() == nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("session.sealed").path))
    }
}
