import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class DeepSeekPlanReaderTests: XCTestCase {
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    private static let key = "synthetic-test-key"
    private static let table = """
    {"complete":true,"row_count":1,
    "headers":["圈号","卫星ID","卫星名称","地面站","数传开始时间","数传结束时间","数传信息","状态","自定义列"],
    "rows":[{"cells":["201","0BO1","测试星","示例站","2026/11/23 09:06:12","2026/11/23 09:07:18","通道A","TEST","备注"],
    "uncertain":false,"emergency_badge":true,"warnings":["示例警告"]}]}
    """

    func testRequestAndReadingPreserveSourceValues() async throws {
        let response = try Self.body(Self.table)
        let result = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.deepseek.com/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(Self.key)")
            let payload = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
            XCTAssertEqual(payload?["model"] as? String, "deepseek-flash")
            XCTAssertEqual((payload?["response_format"] as? [String: String])?["type"], "json_object")
            let message = (payload?["messages"] as? [[String: Any]])?.first
            let content = message?["content"] as? [[String: Any]]
            let image = content?.first(where: { ($0["type"] as? String) == "image_url" })?["image_url"] as? [String: String]
            XCTAssertEqual(image?["url"], "data:image/jpeg;base64,\(Self.jpeg.base64EncodedString())")
            return (response, Self.http(200))
        }
        let row = try XCTUnwrap(result.rows.first)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(row.satelliteID, "0BO1")
        XCTAssertEqual(row.start, "2026-11-23 09:06:12")
        XCTAssertEqual(row.end, "2026-11-23 09:07:18")
        XCTAssertEqual(row.cells[4], "2026/11/23 09:06:12")
        XCTAssertEqual(row.station, "示例站")
        XCTAssertEqual(row.status, "TEST")
        XCTAssertEqual(row.testStatusDetected, true)
        XCTAssertEqual(row.emergencyBadge, true)
        XCTAssertEqual(row.recognitionIssues, ["原图黄色警告：示例警告"])
        XCTAssertEqual(result.layout?.slots.last?.label, "自定义列")
        XCTAssertEqual(row.cells.last, "备注")
        XCTAssertNil(row.region)
        XCTAssertNil(result.header)
        XCTAssertTrue(result.strips.isEmpty)
    }

    func testIncompleteOrUnsafeRowsRejectEntirePage() async throws {
        for (target, replacement) in [
            ("\"row_count\":1", "\"row_count\":2"),
            ("\"complete\":true", "\"complete\":false"),
            ("\"uncertain\":false", "\"uncertain\":true"),
            ("09:06:12", "09:06"),
            ("09:07:18", "09:01:18"),
            ("2026/11/23 09:06:12", "2026/02/30 09:06:12"),
            ("\"warnings\":[\"示例警告\"]", "\"warnings\":[\"\"]"),
            ("\"备注\"", "\"备注\",\"串列\""),
            ("\"示例站\"", "\"\""),
            ("\"TEST\"", "\"\""),
            ("\"TEST\"", "\"TES\"")
        ] {
            let response = try Self.body(Self.table.replacingOccurrences(of: target, with: replacement))
            do {
                _ = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
                    (response, Self.http(200))
                }
                XCTFail("Unexpectedly accepted \(replacement)")
            } catch let error as DeepSeekPlanReader.Failure {
                XCTAssertEqual(error, .incompleteTable)
            }
        }
    }

    func testAllowsSheetWithoutAnEndColumnButPreservesEmptyTimeAsEmpty() async throws {
        let table = """
        {"complete":true,"row_count":1,
        "headers":["卫星名称","地面站","数传开始时间"],
        "rows":[{"cells":["测试星","示例站","2026-11-23 09:06:12"],"uncertain":false,"emergency_badge":false,"warnings":[]}]}
        """
        let response = try Self.body(table)
        let found = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
            (response, Self.http(200))
        }
        XCTAssertEqual(found.rows.first?.end, "")
        XCTAssertNil(found.rows.first?.recognitionIssues)
        XCTAssertNil(found.rows.first?.emergencyBadge)
    }

    func testTruncatedOrMissingWarningsNeverImport() async throws {
        let missingWarnings = Self.table.replacingOccurrences(of: ",\"warnings\":[\"示例警告\"]", with: "")
        for response in [try Self.body(Self.table, finish: "length"), try Self.body(missingWarnings)] {
            do {
                _ = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
                    (response, Self.http(200))
                }
                XCTFail("Accepted truncated or incomplete provider reply")
            } catch let error as DeepSeekPlanReader.Failure {
                XCTAssertEqual(error, .invalidResponse)
            }
        }
    }

    func testStatusErrorsDoNotExposeProviderBody() async throws {
        let expected: [(Int, DeepSeekPlanReader.Failure)] = [
            (302, .invalidResponse), (401, .unauthorized), (402, .insufficientBalance),
            (429, .rateLimited), (503, .unavailable)
        ]
        for (code, expectedError) in expected {
            do {
                _ = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
                    (Data(Self.key.utf8), Self.http(code))
                }
                XCTFail("Accepted HTTP \(code)")
            } catch let error as DeepSeekPlanReader.Failure {
                XCTAssertEqual(error, expectedError)
                XCTAssertFalse(error.localizedDescription.contains(Self.key))
            }
        }
    }

    func testNoNetworkForMissingKeyOrInvalidJPEG() async throws {
        let invalid: [(Data, String, DeepSeekPlanReader.Failure)] = [
            (Self.jpeg, "\n", .missingKey),
            (Self.jpeg, "one\ntwo", .missingKey),
            (Data(), Self.key, .invalidImage)
        ]
        for (image, key, expected) in invalid {
            do {
                _ = try await DeepSeekPlanReader.read(imageData: image, apiKey: key) { _ in
                    XCTFail("Invalid request was sent")
                    return (Data(), Self.http(200))
                }
                XCTFail("Accepted invalid input")
            } catch let error as DeepSeekPlanReader.Failure {
                XCTAssertEqual(error, expected)
            }
        }
    }

    private static func body(_ content: String, finish: String = "stop") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["choices": [["finish_reason": finish, "message": ["content": content]]]])
    }

    private static func http(_ code: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://api.deepseek.com/chat/completions")!,
                        statusCode: code, httpVersion: nil, headerFields: nil)!
    }
}
