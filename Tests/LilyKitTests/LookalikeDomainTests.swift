import Foundation
import Testing
@testable import LilyKit

@Suite struct LookalikeDomainTests {
    @Test func punycodeRoundTripsKnownVectors() {
        #expect(Punycode.decode("mnchen-3ya") == "münchen")
        #expect(Punycode.decode("pple-43d") == "\u{0430}pple") // Cyrillic а + "pple"
        #expect(Punycode.encode("münchen") == "mnchen-3ya")
        #expect(Punycode.encode("\u{0430}pple") == "pple-43d")
        #expect(Punycode.decode("!!") == nil)
    }

    @Test func flagsMixedScriptAndAllConfusable() {
        let mixed = LookalikeDomain.assess(URL(string: "https://xn--pple-43d.com/login"))
        #expect(mixed?.reason == .mixedScript)
        #expect(mixed?.displayHost == "\u{0430}pple.com")
        #expect(mixed?.asciiHost == "xn--pple-43d.com")
        // Raw Unicode in the host works too.
        #expect(LookalikeDomain.assess(host: "p\u{0430}ypal.com")?.reason == .mixedScript)
        #expect(LookalikeDomain.assess(host: "\u{0430}\u{0440}\u{0440}\u{04CF}\u{0435}.com")?.reason == .allConfusable)
        #expect(LookalikeDomain.assess(host: "g\u{03BF}ogle.com")?.reason == .mixedScript)
    }

    @Test func leavesHonestAddressesAlone() {
        for host in ["apple.com", "online.bank.example", "xn--mnchen-3ya.de", "xn--d1acpjx3f.xn--p1ai", "example.com", "127.0.0.1", "a-b-1.co.uk"] {
            #expect(LookalikeDomain.assess(host: host) == nil, "\(host)")
        }
        #expect(LookalikeDomain.assess(URL(string: "mailto:someone@example.com")) == nil)
        #expect(LookalikeDomain.assess(URL(string: "https://[::1]/")) == nil)
    }

    @Test func flagsMalformedPunycodeAndHiddenCharacters() {
        #expect(LookalikeDomain.assess(host: "xn--!!.com")?.reason == .malformed)
        #expect(LookalikeDomain.assess(host: "bank\u{200B}.com")?.reason == .malformed)
    }
}
