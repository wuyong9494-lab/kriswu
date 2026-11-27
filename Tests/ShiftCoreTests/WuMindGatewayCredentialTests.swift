import XCTest
@testable import ShiftCore

final class WuMindGatewayCredentialTests: XCTestCase {
    func testSessionSurvivesReloadOnlyOnItsIssuingGatewayAndAccount() throws {
        let session = try XCTUnwrap(WuMindGatewayCredential(gateway: "https://A.example:443/test/", accountID: "alice", token: "fixture"))
        let restored = try JSONDecoder().decode(WuMindGatewayCredential.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.token(for: "https://a.example/test", accountID: "alice"), "fixture")
        XCTAssertNil(restored.token(for: "https://b.example/test", accountID: "alice"))
        XCTAssertNil(restored.token(for: "https://a.example/prod", accountID: "alice"))
        XCTAssertNil(restored.token(for: "https://a.example/test", accountID: "bob"))
        XCTAssertNil(WuMindGatewayCredential(gateway: "", accountID: "alice", token: "fixture"))
    }
}
