import XCTest
@testable import ShiftCore

final class WuMindGatewayConfigurationTests: XCTestCase {
    private enum WriteError: Error { case failed }

    func testEmptyOrDashboardDraftNeverWrites() {
        for draft in ["  ", "https://...workers.dev", "http://gw.example.com", "https://dash.cloudflare.com/a",
                      "https://user:pass@gw.example.com", "https://gw.example.com?token=invalid"] {
            XCTAssertThrowsError(try WuMindGatewayConfiguration.persistAddress(draft) { _ in
                XCTFail("Invalid draft must never overwrite the saved address")
            })
        }
    }

    func testManagedAddressComesFromThisBuildOnFreshInstallAndUpgrade() {
        let release = "https://gateway.example.com/service"
        let test = "https://gateway-test.example.com"
        XCTAssertEqual(WuMindGatewayConfiguration.resolvedAddress(saved: nil, bundled: release), release)
        XCTAssertEqual(WuMindGatewayConfiguration.resolvedAddress(saved: release + "/", bundled: release), release)
        XCTAssertEqual(WuMindGatewayConfiguration.resolvedAddress(saved: test, bundled: release), release)
        XCTAssertEqual(WuMindGatewayConfiguration.resolvedAddress(saved: release, bundled: test), test)
        for missing in [nil, "", "https://gateway.example.com/admin/edit"] as [String?] {
            XCTAssertNil(WuMindGatewayConfiguration.resolvedAddress(saved: test, bundled: missing))
        }
    }

    func testExplicitSaveReturnsOnlyAfterNormalizedAddressIsWritten() throws {
        let base = "https://gateway.example.com/proxy"
        var calls: [String] = []
        let saved = try WuMindGatewayConfiguration.persistAddress(" HTTPS://GATEWAY.example.com:443/proxy/  ") { calls.append($0) }
        XCTAssertEqual(calls, [base])
        XCTAssertEqual(saved, base)
        XCTAssertThrowsError(try WuMindGatewayConfiguration.persistAddress(base) { _ in throw WriteError.failed })
    }

    func testCredentialsAreScopedToExactNormalizedGateway() throws {
        let production = try WuMindGatewayConfiguration.administratorCredentialID(for: "https://gw.example.com/api")
        XCTAssertEqual(production, try WuMindGatewayConfiguration.administratorCredentialID(for: "https://GW.example.com:443/api/"))
        for other in ["https://test.example.com/api", "https://gw.example.com/test", "https://gw.example.com:8443/api"] {
            XCTAssertNotEqual(production, try WuMindGatewayConfiguration.administratorCredentialID(for: other))
        }
    }

    func testFailedMigrationRetainsLegacySourceAndDoesNotMarkIncompletePrivateData() {
        var events: [String] = []
        XCTAssertThrowsError(try WuMindGatewayConfiguration.finalizeLegacyMigration(
            writePrivateData: { events.append("private"); throw WriteError.failed },
            writeSettings: { events.append("settings") },
            removeLegacy: { events.append("delete") }
        ))
        XCTAssertEqual(events, ["private"])
        events.removeAll()
        XCTAssertThrowsError(try WuMindGatewayConfiguration.finalizeLegacyMigration(
            writePrivateData: { events.append("private") },
            writeSettings: { events.append("settings"); throw WriteError.failed },
            removeLegacy: { events.append("delete") }
        ))
        XCTAssertEqual(events, ["private", "settings"])
    }

    func testSuccessfulMigrationDeletesLegacyLast() throws {
        var events: [String] = []
        try WuMindGatewayConfiguration.finalizeLegacyMigration(
            writePrivateData: { events.append("private") },
            writeSettings: { events.append("settings") },
            removeLegacy: { events.append("delete") }
        )
        XCTAssertEqual(events, ["private", "settings", "delete"])
    }
}
