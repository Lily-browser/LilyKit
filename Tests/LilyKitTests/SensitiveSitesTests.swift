import Foundation
import Testing
@testable import LilyKit

@MainActor
struct SensitiveSitesTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func aMarkedSiteAndItsSubdomainsAreSensitive() {
        let settings = SiteSettings(directory: nil)
        settings.update(url("https://www.bank.example/")) { $0.sensitive = true }
        #expect(settings.isSensitive(url("https://bank.example/login")))
        #expect(settings.isSensitive(url("https://www.bank.example/")))
        #expect(settings.isSensitive(url("https://online.bank.example/account")))
        #expect(settings.isSensitive(url("http://bank.example:8080/"))) // downgrades and other ports don't escape it
    }

    @Test func aTrailingDotNamesTheSameHost() {
        let settings = SiteSettings(directory: nil)
        settings.update(url("https://bank.example/")) { $0.sensitive = true }
        #expect(settings.isSensitive(url("https://bank.example./")))
        #expect(settings.isSensitive(url("https://online.bank.example./login")))
        #expect(settings.isSensitive(url("https://www.bank.example../")))
        #expect(!settings.isSensitive(url("https://notbank.example./")))
        #expect(SiteSettings.key(for: url("https://bank.example./")) == "bank.example")
        #expect(SiteSettings.storageKey(for: url("http://bank.example.:8080/")) == "http://bank.example:8080")
    }

    @Test func otherSitesAreNot() {
        let settings = SiteSettings(directory: nil)
        settings.update(url("https://bank.example/")) { $0.sensitive = true }
        #expect(!settings.isSensitive(url("https://notbank.example/")))      // a longer name that merely ends the same
        #expect(!settings.isSensitive(url("https://example/")))
        #expect(!settings.isSensitive(url("https://bank.example.evil.test/"))) // the marked name inside another host
        #expect(!settings.isSensitive(nil))
        #expect(!settings.isSensitive(url("file:///etc/hosts")))
    }

    @Test func turningItOffForgetsIt() {
        let settings = SiteSettings(directory: nil)
        settings.update(url("https://bank.example/")) { $0.sensitive = true }
        #expect(settings.isSensitive(url("https://bank.example/")))
        settings.update(url("https://bank.example/")) { $0.sensitive = nil }
        #expect(!settings.isSensitive(url("https://bank.example/")) && settings.sites.isEmpty)
    }

    @Test func settingsSavedBeforeTheFlagStillLoad() throws {
        let json = #"{"old.example":{"zoom":1.25,"adsAllowed":true}}"#
        let sites = try JSONDecoder().decode([String: SiteSettings.Site].self, from: Data(json.utf8))
        #expect(sites["old.example"]?.zoom == 1.25 && sites["old.example"]?.sensitive == nil)
    }
}
