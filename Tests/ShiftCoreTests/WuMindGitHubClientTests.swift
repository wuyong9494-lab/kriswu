import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindGitHubClientTests: XCTestCase {
    func testParseRepoIdentifierHandlesURLsAndRejectsTraversal() {
        XCTAssertEqual(WuMindGitHubClient.parseRepoIdentifier("wuyong9494-lab/kriswu"), "wuyong9494-lab/kriswu")
        XCTAssertEqual(WuMindGitHubClient.parseRepoIdentifier("https://github.com/wuyong9494-lab/kriswu.git"), "wuyong9494-lab/kriswu")
        XCTAssertEqual(WuMindGitHubClient.parseRepoIdentifier("github.com/apple/swift/tree/main/stdlib"), "apple/swift")
        XCTAssertNil(WuMindGitHubClient.parseRepoIdentifier("../secret/repo"))
        XCTAssertNil(WuMindGitHubClient.parseRepoIdentifier("only-owner"))
    }

    func testDetectRepoInTextFindsGitHubURL() {
        XCTAssertEqual(
            WuMindGitHubClient.detectRepoInText("帮我看看 https://github.com/wuyong9494-lab/kriswu 的架构"),
            "wuyong9494-lab/kriswu"
        )
        XCTAssertNil(WuMindGitHubClient.detectRepoInText("普通聊天没有链接"))
    }

    func testFetchRepoContextDecodesMetadataReadmeTreeCommitsAndFile() async throws {
        let readmeB64 = Data("# KrisWu App\nHello GitHub".utf8).base64EncodedString()
        let swiftB64 = Data("struct Hello { let x = 1 }".utf8).base64EncodedString()
        let client = WuMindGitHubClient { request in
            XCTAssertEqual(request.url?.host, "api.github.com")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer ghp_dummy123")
            let path = request.url?.path ?? ""
            let json: String
            if path == "/repos/wuyong9494-lab/kriswu" {
                json = #"{"full_name":"wuyong9494-lab/kriswu","description":"Duty & AI","default_branch":"main","language":"Swift","private":false,"stargazers_count":9}"#
            } else if path == "/repos/wuyong9494-lab/kriswu/readme" {
                json = #"{"content":"\#(readmeB64)","size":24}"#
            } else if path == "/repos/wuyong9494-lab/kriswu/git/trees/main" {
                json = #"{"tree":[{"path":"App/ShiftApp.swift","type":"blob"},{"path":"App","type":"tree"}]}"#
            } else if path == "/repos/wuyong9494-lab/kriswu/commits" {
                json = #"[{"sha":"abcdef1234567890","commit":{"message":"Add WUMIND\ndetails"}}]"#
            } else if path == "/repos/wuyong9494-lab/kriswu/contents/App/ShiftApp.swift" {
                json = #"{"content":"\#(swiftB64)","size":26}"#
            } else {
                XCTFail("Unexpected path \(path)")
                json = "{}"
            }
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        var ctx = try await client.fetchRepoContext(fullName: "https://github.com/wuyong9494-lab/kriswu", token: "Bearer ghp_dummy123")
        XCTAssertEqual(ctx.repo.fullName, "wuyong9494-lab/kriswu")
        XCTAssertTrue(ctx.readmeExcerpt.contains("Hello GitHub"))
        XCTAssertEqual(ctx.filePaths, ["App/ShiftApp.swift"])
        XCTAssertEqual(ctx.recentCommits, ["abcdef1 Add WUMIND"])

        let file = try await client.fetchFileContent(fullName: ctx.repo.fullName, path: "App/ShiftApp.swift", ref: "main", token: "ghp_dummy123")
        ctx.attachedFiles.append(file)
        let prompt = ctx.formattedPromptContext()
        XCTAssertTrue(prompt.contains("wuyong9494-lab/kriswu"))
        XCTAssertTrue(prompt.contains("struct Hello"))
    }
}
