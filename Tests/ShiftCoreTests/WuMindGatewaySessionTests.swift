import XCTest
@testable import ShiftCore

final class WuMindGatewaySessionTests: XCTestCase {
    func testSessionSurvivesReloadOnlyOnItsIssuingGatewayAndAccount() throws {
        let session = try XCTUnwrap(WuMindGatewaySession(gateway: "https://A.example:443/test/", accountID: "alice", token: "fixture"))
        let restored = try JSONDecoder().decode(WuMindGatewaySession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(restored.token(for: "https://a.example/test", accountID: "alice"), "fixture")
        XCTAssertNil(restored.token(for: "https://b.example/test", accountID: "alice"))
        XCTAssertNil(restored.token(for: "https://a.example/prod", accountID: "alice"))
        XCTAssertNil(restored.token(for: "https://a.example/test", accountID: "bob"))
        XCTAssertNil(WuMindGatewaySession(gateway: "", accountID: "alice", token: "fixture"))
    }
}
