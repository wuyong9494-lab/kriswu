import XCTest
@testable import ShiftCore

final class AIProviderCredentialScopeTests: XCTestCase {
    func testLegacyKeyRemainsWithItsOriginalProviderAndTenant() throws {
        let provider = AIProvider.openAI
        let a = "https://relay.example/tenant-A/v1/"
        let b = "https://relay.example/tenant-B/v1"
        let aID = try provider.personalConnectionID(baseURL: a)
        let bID = try provider.personalConnectionID(baseURL: b)
        let official = try provider.personalConnectionID(baseURL: nil)
        XCTAssertNotEqual(official, aID)
        XCTAssertNotEqual(aID, bID)
        XCTAssertNotEqual(aID, try AIProvider.claude.personalConnectionID(baseURL: a))
        var original = try AIProviderCredentialSet(stored: "offline-old", provider: provider, previousBaseURL: a)
        XCTAssertTrue(original.requiresMigration)
        XCTAssertEqual(original.keys[aID], "offline-old")
        XCTAssertNil(original.keys[bID])
        original.set("offline-new", for: bID)
        // Relaunch before or after updating the selected endpoint.
        for active in [a, b] {
            var restored = try AIProviderCredentialSet(stored: original.encoded(), provider: provider, previousBaseURL: active)
            XCTAssertFalse(restored.requiresMigration)
            XCTAssertEqual(restored.keys[aID], "offline-old")
            XCTAssertEqual(restored.keys[bID], "offline-new")
            XCTAssertNil(restored.keys[official])
            restored.set("", for: bID)
            XCTAssertEqual(restored.keys[aID], "offline-old")
            XCTAssertNil(restored.keys[bID])
        }
    }

    func testCanonicalEndpointAndUnreadableLegacyRecords() throws {
        let provider = AIProvider.openAI
        XCTAssertEqual(try provider.personalConnectionID(baseURL: nil),
                       try provider.personalConnectionID(baseURL: "https://API.OPENAI.COM:443/v1/"))
        XCTAssertNotEqual(try provider.personalConnectionID(baseURL: nil),
                          try provider.personalConnectionID(baseURL: "https://api.openai.com:8443/v1"))
        XCTAssertThrowsError(try AIProviderCredentialSet(stored: "offline-old", provider: provider, previousBaseURL: "broken"))
        XCTAssertThrowsError(try AIProviderCredentialSet(stored: "wumind-provider-keys-v1\nbroken", provider: provider, previousBaseURL: nil))
    }
}
