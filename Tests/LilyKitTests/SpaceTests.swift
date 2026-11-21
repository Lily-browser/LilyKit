import Foundation
import Testing
@testable import LilyKit

@Suite struct SpaceTests {
    @Test func macSessionsWithTheOldColorKeyStillDecode() throws {
        let id = UUID()
        let json = ##"{"id":"\##(id)","name":"Work","symbol":"star.fill","color":"#0A84FF","separateLogins":true}"##
        let space = try JSONDecoder().decode(Space.self, from: Data(json.utf8))
        #expect(space.colorHex == "#0A84FF" && space.hasSeparateLogins && space.id == id)
    }

    @Test func spacesWithoutSeparateLoginsDecodeAndRoundTrip() throws {
        let json = ##"{"id":"\##(UUID())","name":"A","symbol":"circle.fill","colorHex":"#000000"}"##
        let space = try JSONDecoder().decode(Space.self, from: Data(json.utf8))
        #expect(!space.hasSeparateLogins)
        #expect(try JSONDecoder().decode(Space.self, from: JSONEncoder().encode(space)) == space)
    }

    @Test func aSpaceWithoutAnyColorIsRejected() {
        let json = ##"{"id":"\##(UUID())","name":"A","symbol":"circle.fill"}"##
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(Space.self, from: Data(json.utf8)) }
    }
}
