import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindSearchRoutingTests: XCTestCase {
    func testOwnChatSelectsGatewayOnlyWhenNoPersonalSearchKeyAndSessionExists() {
        XCTAssertEqual(WuMindSearchRouting.firstRoute(usesOwnChat: true, hasPersonalKey: true, hasGatewaySession: true), .personal)
        XCTAssertEqual(WuMindSearchRouting.firstRoute(usesOwnChat: true, hasPersonalKey: false, hasGatewaySession: true), .gateway)
        XCTAssertEqual(WuMindSearchRouting.firstRoute(usesOwnChat: true, hasPersonalKey: false, hasGatewaySession: false), .unavailable)
        XCTAssertEqual(WuMindSearchRouting.firstRoute(usesOwnChat: false, hasPersonalKey: true, hasGatewaySession: true), .gateway)
    }

    func testAllFailureNeedsExplicitChoiceEvenWithoutBackupAndPartialEvidenceDoesNot() {
        let fallback = WuMindSearchRouting.decision(hasSearchEvidence: false, route: .personal, gatewayReady: true)
        XCTAssertTrue(fallback.shouldAsk)
        XCTAssertTrue(fallback.offerGateway)
        let failedGateway = WuMindSearchRouting.decision(hasSearchEvidence: false, route: .gateway, gatewayReady: true)
        XCTAssertTrue(failedGateway.shouldAsk)
        XCTAssertFalse(failedGateway.offerGateway)
        let unavailable = WuMindSearchRouting.decision(hasSearchEvidence: false, route: .unavailable, gatewayReady: false)
        XCTAssertTrue(unavailable.shouldAsk)
        XCTAssertFalse(unavailable.offerGateway)
        XCTAssertFalse(WuMindSearchRouting.decision(hasSearchEvidence: true, route: .personal, gatewayReady: true).shouldAsk)
    }

    func testFailedGatewayEnvelopeCannotSupplyEvidenceEvenWithLinks() throws {
        func status(_ flags: String) throws -> String {
            let json = """
            {\(flags)"query":"最新公告","provider":"tavily","costYuan":0,
             "results":[{"title":"公告","url":"https://example.org/report","snippet":"摘要"}]}
            """
            return try JSONDecoder().decode(WuMindWebSearchResponse.self, from: Data(json.utf8)).evidenceStatus
        }
        XCTAssertEqual(try status(#""ok":false,"status":"ok","#), "upstream_error")
        XCTAssertEqual(try status(#""code":"unauthorized","#), "unauthorized")
        XCTAssertEqual(try status(#""status":"no_results","#), "no_results")
        XCTAssertEqual(try status(#""ok":true,"status":"ok","#), "ok")
        XCTAssertEqual(try status(""), "ok")
    }

    func testPersonalFailureDoesNotSubmitToAnotherProvider() async {
        let result = await WuMindAgentTools.directWebSearch(query: "新闻", tavilyKey: "tvly-mock", allowPublicFallback: false) {
            request in
            XCTAssertEqual(request.url?.host, "api.tavily.com")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.summary.contains("Tavily"))
        XCTAssertTrue(result.searchResults.isEmpty)
    }

    func testEmptyOrInvalidBraveResultsAreNotEvidence() async {
        let result = await WuMindAgentTools.directWebSearch(query: "新闻", braveKey: "mock", allowPublicFallback: false) {
            request in
            XCTAssertEqual(request.url?.host, "api.search.brave.com")
            let json = #"{"web":{"results":[{"title":"invalid","url":"javascript:alert(1)"}]}}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.searchResults.isEmpty)
    }

    func testPersonalTavilyReturnsStructuredRealCitationsAsSnippets() async {
        let result = await WuMindAgentTools.directWebSearch(query: "新闻", tavilyKey: "tvly-mock", allowPublicFallback: false) {
            request in
            let json = #"{"results":[{"title":"Report","url":"https://example.com/news","content":"Public snippet"}]}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.searchResults.map(\.url), ["https://example.com/news"])
        XCTAssertEqual(result.searchResults.map(\.isFullTextRead), [false])
    }
}
