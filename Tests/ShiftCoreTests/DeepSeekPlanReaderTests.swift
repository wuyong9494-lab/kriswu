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
            XCTAssertEqual(image?["detail"], "high")
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

    func testResilientParsingHandlesFencedJSONNumericCellsAndFlagsUncertainRowsForReview() async throws {
        // Real-world DeepSeek V4.1-Flash output: fenced markdown, numeric cell, omitted optional fields,
        // blank 是否应急, missing seconds, slight row_count drift, uncertain row -> imports WITH yellow review flags!
        let fenced = """
        ```json
        {
          "complete": false,
          "row_count": 3,
          "headers": ["圈号", "卫星名称", "地面站", "数传开始时间", "数传结束时间", "是否应急", "状态"],
          "rows": [
            {"cells": [201, "高分一号", "喀什-1", "2026-11-24T09:06", "2026-11-24 09:16:00", "", "待执行"], "uncertain": true},
            {"cells": ["202", "高分二号", "密云-2", "11-24 10:12:30", "11-24 10:22:30", null, "已确认"]}
          ]
        }
        ```
        """
        let response = try Self.body(fenced)
        let reading = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
            (response, Self.http(200))
        }
        XCTAssertEqual(reading.rows.count, 2)
        XCTAssertEqual(reading.rows[0].orbit, "201")
        XCTAssertEqual(reading.rows[0].station, "喀什-1")
        XCTAssertEqual(reading.rows[0].start, "2026-11-24 09:06:00")
        XCTAssertNotNil(reading.rows[0].recognitionIssues, "Uncertain / incomplete / missing-seconds rows must carry yellow review warnings")
        XCTAssertTrue(reading.rows[0].recognitionIssues?.contains(where: { $0.contains("不完整") }) == true)
        XCTAssertTrue(reading.rows[0].recognitionIssues?.contains(where: { $0.contains("存疑") }) == true)
        XCTAssertEqual(reading.rows[1].start, "2026-11-24 10:12:30")
        XCTAssertEqual(reading.rows[1].end, "2026-11-24 10:22:30")
    }

    func testUnusableOrEmptyTablesStillReject() async throws {
        let badTables = [
            // Invalid calendar date leaves zero valid rows
            Self.table.replacingOccurrences(of: "2026/11/23 09:06:12", with: "2026/02/30 09:06:12"),
            // Missing required station leaves zero valid rows
            Self.table.replacingOccurrences(of: "\"示例站\"", with: "\"\""),
            // Missing required headers
            #"{"headers":["列1","列2"],"rows":[]}"#,
            // Empty rows
            #"{"headers":["卫星名称","地面站","数传开始时间"],"rows":[]}"#
        ]
        for json in badTables {
            let response = try Self.body(json)
            do {
                _ = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
                    (response, Self.http(200))
                }
                XCTFail("Unexpectedly accepted unusable table: \(json)")
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

    func testTruncatedReplyNeverImports() async throws {
        for response in [try Self.body(Self.table, finish: "length"), try Self.body("not json at all")] {
            do {
                _ = try await DeepSeekPlanReader.read(imageData: Self.jpeg, apiKey: Self.key) { _ in
                    (response, Self.http(200))
                }
                XCTFail("Accepted truncated or non-JSON provider reply")
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
