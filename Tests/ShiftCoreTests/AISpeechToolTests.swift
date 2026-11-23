import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class AISpeechToolTests: XCTestCase {
    private static let fakeWAV = Data([
        82, 73, 70, 70, 38, 0, 0, 0, 87, 65, 86, 69,
        102, 109, 116, 32, 16, 0, 0, 0, 1, 0, 1, 0,
        192, 93, 0, 0, 128, 187, 0, 0, 2, 0, 16, 0,
        100, 97, 116, 97, 2, 0, 0, 0, 0, 0
    ])

    func testSynthesisUsesGrokWAVContract() async throws {
        let service = AISpeechTool(transport: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.x.ai/v1/tts")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-xai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "audio/wav")
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
            XCTAssertEqual(body["text"] as? String, "值班测试")
            XCTAssertEqual(body["voice_id"] as? String, "ara")
            XCTAssertEqual(body["language"] as? String, "auto")
            let format = try XCTUnwrap(body["output_format"] as? [String: Any])
            XCTAssertEqual(format["codec"] as? String, "wav")
            return (Self.fakeWAV, try Self.ok(for: request))
        })
        let audio = try await service.synthesize(" \n值班测试  ", voice: .ara, apiKey: "mock-xai")
        XCTAssertEqual(audio, Self.fakeWAV)
    }

    func testTranscriptionPostsMultipartWithGenericFileName() async throws {
        let service = AISpeechTool(transport: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock-ai")
            XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-transcribe"))
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"recording.m4a\""))
            XCTAssertTrue(body.contains("Content-Type: audio/mp4\r\n\r\nmock-audio"))
            return (Data(#"{"text":" 值班测试 "}"#.utf8), try Self.ok(for: request))
        })
        let transcript = try await service.transcribe(Data("mock-audio".utf8), format: .m4a, apiKey: "mock-ai")
        XCTAssertEqual(transcript, "值班测试")
    }

    func testInvalidInputsNeverReachTransport() async {
        let service = AISpeechTool(transport: { _ in
            XCTFail("Unexpected network call")
            throw URLError(.badURL)
        })
        do {
            _ = try await service.synthesize(String(repeating: "👩‍🔬", count: 3000), apiKey: "mock")
            XCTFail("UTF-8 size limit not enforced")
        } catch AISpeechTool.Problem.missingText {} catch { XCTFail("Unexpected error") }
        do {
            _ = try await service.transcribe(Data(), format: .wav, apiKey: "mock")
            XCTFail("Empty recordings must be rejected")
        } catch AISpeechTool.Problem.invalidSize {} catch { XCTFail("Unexpected error") }
    }

    func testFakeHTTP200AndTruncatedWaveAreRejected() async {
        for bad in [Data(#"{"message":"mock-error"}"#.utf8), Data(Self.fakeWAV.dropLast())] {
            let service = AISpeechTool(transport: { request in (bad, try Self.ok(for: request)) })
            do {
                _ = try await service.synthesize("test", apiKey: "mock")
                XCTFail("Malformed WAV accepted")
            } catch AISpeechTool.Problem.invalidReply {} catch { XCTFail("Unexpected error") }
        }
    }

    private static func ok(for request: URLRequest) throws -> HTTPURLResponse {
        try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
    }
}
