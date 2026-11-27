import Foundation
import Testing
@testable import LilyKit

struct AuditHardeningTests {
    @Test func aPublicNameThatStartsLikeAPrivateAddressGetsHTTPS() {
        let resolver = URLResolver()
        #expect(resolver.resolve("10.example.com")?.scheme == "https")
        #expect(resolver.resolve("127.evil.example")?.scheme == "https")
        #expect(resolver.resolve("192.168.example.net/login")?.scheme == "https")
    }

    @Test func privateAddressesAndLocalNamesStayHTTP() {
        let resolver = URLResolver()
        for host in ["localhost:3000", "127.0.0.1", "10.0.0.5", "192.168.1.20/admin", "172.16.4.2", "printer.local"] {
            #expect(resolver.resolve(host)?.scheme == "http", "\(host)")
        }
        #expect(resolver.resolve("172.32.0.1")?.scheme == "https") // outside 172.16.0.0/12
    }

    @Test func anOutOfRangeNumberIsNotAnInteger() {
        #expect(JSONValue.number(42).int == 42)
        #expect(JSONValue.number(3.9).int == 3)
        #expect(JSONValue.number(1e300).int == nil) // Int(1e300) would trap
        #expect(JSONValue.number(.infinity).int == nil)
        #expect(JSONValue.number(.nan).int == nil)
    }
}
