import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import ShiftCore

final class WuMindShortDramaEngineTests: XCTestCase {

    // MARK: - Crypto & Kling HS256 JWT

    func testSHA256AndHMACSHA256MatchStandardVectors() {
        // FIPS 180-4 SHA-256("abc")
        let shaHex = WuMindJWTAuth.sha256(Data("abc".utf8)).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(shaHex, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

        // RFC 4231 Test Case 2: key = "Jefe", data = "what do ya want for nothing?"
        let hmacHex = WuMindJWTAuth.hmacSHA256(
            key: Data("Jefe".utf8),
            message: Data("what do ya want for nothing?".utf8)
        ).map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hmacHex, "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    }

    func testKlingHS256JWTStructureAndSignature() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let jwt = try WuMindJWTAuth.makeKlingHS256JWT(
            accessKey: "ak_test_123",
            secretKey: "sk_secret_456",
            issuedAt: fixedDate,
            ttlSeconds: 1800
        )
        let parts = jwt.split(separator: ".")
        XCTAssertEqual(parts.count, 3)

        func decodeB64URL(_ s: Substring) -> Data? {
            var str = String(s).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while str.count % 4 != 0 { str.append("=") }
            return Data(base64Encoded: str)
        }

        let headerJSON = String(data: try XCTUnwrap(decodeB64URL(parts[0])), encoding: .utf8)
        let payloadJSON = String(data: try XCTUnwrap(decodeB64URL(parts[1])), encoding: .utf8)
        XCTAssertEqual(headerJSON, "{\"alg\":\"HS256\",\"typ\":\"JWT\"}")
        XCTAssertEqual(payloadJSON, "{\"iss\":\"ak_test_123\",\"exp\":1700001800,\"nbf\":1699999995}")

        let expectedSig = WuMindJWTAuth.base64URLEncode(
            WuMindJWTAuth.hmacSHA256(
                key: Data("sk_secret_456".utf8),
                message: Data("\(parts[0]).\(parts[1])".utf8)
            )
        )
        XCTAssertEqual(String(parts[2]), expectedSig)
    }

    // MARK: - Official Seedance & Kling Clients (Mocked Transport)

    private static var fakeValidMP4: Data {
        // Minimal valid ISO BMFF ftyp header (16 bytes)
        Data([0x00, 0x00, 0x00, 0x10, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d, 0x00, 0x00, 0x02, 0x00])
    }

    func testVolcengineArkSeedanceSubmitPollAndCDNIsolation() async throws {
        let state = LockedArray<URLRequest>()
        let mp4Bytes = Self.fakeValidMP4

        let client = VolcengineArkSeedanceClient(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 5) { req in
            state.append(req)
            let url = try XCTUnwrap(req.url)
            if url.path == "/api/v3/contents/generations/tasks", req.httpMethod == "POST" {
                let json = #"{"id":"cgt-20261124-001","status":"queued"}"#
                return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if url.path == "/api/v3/contents/generations/tasks/cgt-20261124-001", req.httpMethod == "GET" {
                let json = #"{"id":"cgt-20261124-001","status":"succeeded","content":{"video_url":"https://tos-cdn.volces.example/shot4.mp4"}}"#
                return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if url.host == "tos-cdn.volces.example" {
                return (mp4Bytes, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Unexpected request URL: \(url)")
            throw URLError(.badURL)
        }

        let result = try await client.generate(
            prompt: "暴雨夜监控中心近景推镜",
            aspectRatio: .portrait9x16,
            durationSeconds: 5,
            resolution: .hd720,
            referenceImageBase64: "AAAA",
            config: .init(apiKey: "ark-key-secret", modelID: "ep-2026-seedance")
        )

        XCTAssertEqual(result, mp4Bytes)
        let captured = state.snapshot()
        XCTAssertEqual(captured.count, 3)
        XCTAssertEqual(captured[0].value(forHTTPHeaderField: "Authorization"), "Bearer ark-key-secret")
        let submitBody = String(data: try XCTUnwrap(captured[0].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(submitBody.contains("ep-2026-seedance"))
        XCTAssertTrue(submitBody.contains("data:image/jpeg;base64,AAAA"))
        XCTAssertTrue(submitBody.contains("--ratio 9:16"))
        // CDN download MUST NOT leak Ark API key
        XCTAssertNil(captured[2].value(forHTTPHeaderField: "Authorization"))
    }

    func testKlingOfficialClientRoutesImage2VideoAndIsolatesJWTFromCDN() async throws {
        let state = LockedArray<URLRequest>()
        let mp4Bytes = Self.fakeValidMP4

        let client = KlingOfficialVideoClient(pollIntervalNanoseconds: 1_000_000, maxPollAttempts: 5) { req in
            state.append(req)
            let url = try XCTUnwrap(req.url)
            if url.path == "/v1/videos/image2video", req.httpMethod == "POST" {
                let json = #"{"code":0,"message":"ok","data":{"task_id":"kl-998","task_status":"submitted"}}"#
                return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if url.path == "/v1/videos/image2video/kl-998", req.httpMethod == "GET" {
                let json = #"{"code":0,"message":"ok","data":{"task_id":"kl-998","task_status":"succeed","task_result":{"videos":[{"id":"v1","url":"https://cdn.klingai.example/kl998.mp4","duration":"5"}]}}}"#
                return (Data(json.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            if url.host == "cdn.klingai.example" {
                return (mp4Bytes, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            XCTFail("Unexpected request URL: \(url)")
            throw URLError(.badURL)
        }

        let result = try await client.generate(
            prompt: "走廊监控视角特写，冷蓝雨夜",
            aspectRatio: .portrait9x16,
            durationSeconds: 5,
            referenceImageBase64: "data:image/png;base64,BBBB",
            config: .init(accessKey: "ak_demo", secretKey: "sk_demo", modelName: "kling-v1-6", mode: "pro")
        )

        XCTAssertEqual(result, mp4Bytes)
        let captured = state.snapshot()
        XCTAssertEqual(captured.count, 3)
        let authHeader = try XCTUnwrap(captured[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(authHeader.hasPrefix("Bearer "))
        XCTAssertEqual(authHeader.dropFirst("Bearer ".count).split(separator: ".").count, 3)

        let submitBody = String(data: try XCTUnwrap(captured[0].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(submitBody.contains("\"image\":\"BBBB\""))
        XCTAssertTrue(submitBody.contains("\"aspect_ratio\":\"9:16\""))
        // CDN download MUST NOT leak Kling JWT
        XCTAssertNil(captured[2].value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: - Storyboard, Selective Single-Shot Reshoot & Timeline Math

    func testSelectiveSingleShotReshootPreservesDialogueVoiceOldTakesAndRestOfTimeline() throws {
        var project = WuMindShortDramaEngine.sampleVerticalDrama(defaultEngine: .seedance)
        XCTAssertEqual(project.shots.count, 6)
        XCTAssertEqual(WuMindShortDramaEngine.totalTrimmedDuration(for: project), 36.0)

        let shot4Original = project.shots[3]
        let shot1Before = project.shots[0]
        let shot5Before = project.shots[4]

        // Take 1 on Shot #4
        let take1 = WuMindShotTake(
            takeNumber: 1,
            engine: .seedance,
            modelID: "doubao-seedance-1-0-pro-250528",
            promptUsed: "初版中景",
            revisionNote: "首拍",
            videoFilename: "shot4_take1.mp4",
            durationSeconds: 6.0,
            estimatedCostYuan: 1.44,
            usedReferenceImage: true
        )
        project = WuMindShortDramaEngine.applySingleShotTake(
            project: project,
            shotID: shot4Original.id,
            take: take1
        )
        XCTAssertEqual(project.totalGenerations, 1)
        XCTAssertEqual(project.singleShotReshoots, 0)

        // Selective Reshoot ONLY on Shot #4: "换成近景，台词和声音不变"
        let char4 = project.character(for: project.shots[3])
        let plan = WuMindShortDramaEngine.composeReshootPrompt(
            shot: project.shots[3],
            instruction: "换成近景，台词和声音不变",
            keepDialogueAndVoice: true,
            character: char4,
            project: project
        )
        XCTAssertEqual(plan.updatedFraming, .closeUp)
        XCTAssertEqual(plan.preservedDialogue, shot4Original.dialogue)
        XCTAssertEqual(plan.preservedVoiceLabel, char4?.voicePreset.displayName)
        XCTAssertTrue(plan.finalGenerationPrompt.contains("近景"))

        let take2 = WuMindShotTake(
            takeNumber: 2,
            engine: .kling,
            modelID: "kling-v1-6",
            promptUsed: plan.finalGenerationPrompt,
            revisionNote: "换成近景，台词和声音不变",
            videoFilename: "shot4_take2.mp4",
            durationSeconds: 6.0,
            estimatedCostYuan: 1.80,
            usedReferenceImage: true
        )
        // Cross-engine consistency disclosure MUST warn when switching from Seedance to Kling
        let warning = WuMindShortDramaEngine.crossEngineConsistencyWarning(
            for: project,
            shotID: shot4Original.id,
            targetEngine: .kling
        )
        XCTAssertNotNil(warning)
        XCTAssertTrue(warning?.contains("无法保证") == true)

        project = WuMindShortDramaEngine.applySingleShotTake(
            project: project,
            shotID: shot4Original.id,
            take: take2,
            updatedFraming: plan.updatedFraming,
            updatedVisualPrompt: plan.updatedVisualPrompt,
            updatedDialogue: "不应被覆盖的台词",
            keepDialogueAndVoice: true
        )

        let shot4After = project.shots[3]
        XCTAssertEqual(shot4After.takes.count, 2, "旧版 Take 1 必须保留以便对比")
        XCTAssertEqual(shot4After.activeTake?.id, take2.id)
        XCTAssertEqual(shot4After.cameraFraming, .closeUp)
        XCTAssertEqual(shot4After.dialogue, shot4Original.dialogue, "锁定台词和声音不变时，台词不可改动")
        XCTAssertEqual(shot4After.characterID, shot4Original.characterID)
        XCTAssertEqual(project.shots[0], shot1Before, "其余镜头必须完全不动")
        XCTAssertEqual(project.shots[4], shot5Before, "其余镜头必须完全不动")
        XCTAssertEqual(project.totalGenerations, 2)
        XCTAssertEqual(project.singleShotReshoots, 1)
        XCTAssertEqual(project.estimatedTotalCostYuan, 3.24, accuracy: 0.01)

        // A/B switch back to Take 1 cleanly
        project = WuMindShortDramaEngine.switchActiveTake(project: project, shotID: shot4Original.id, takeID: take1.id)
        XCTAssertEqual(project.shots[3].activeTake?.id, take1.id)
    }

    func testTimelineReorderTrimClampingAndSubtitleCues() {
        var project = WuMindShortDramaEngine.sampleVerticalDrama()
        let firstID = project.shots[0].id
        let secondID = project.shots[1].id

        // Move shot 0 -> index 1
        project = WuMindShortDramaEngine.moveShot(project: project, fromIndex: 0, toIndex: 1)
        XCTAssertEqual(project.shots[0].id, secondID)
        XCTAssertEqual(project.shots[1].id, firstID)

        // Trim shot 0 to [1.0, 4.5] (3.5s) and disable subtitle on shot 1
        project = WuMindShortDramaEngine.updateTrim(project: project, shotID: secondID, trimStart: 1.0, trimEnd: 4.5)
        XCTAssertEqual(project.shots[0].trimmedDuration, 3.5, accuracy: 0.01)

        // Out-of-range trim safely clamps to >= 1.0s
        project = WuMindShortDramaEngine.updateTrim(project: project, shotID: firstID, trimStart: 5.8, trimEnd: 5.9)
        XCTAssertGreaterThanOrEqual(project.shots[1].trimmedDuration, 1.0)

        project.shots[1].subtitleEnabled = false
        let cues = WuMindShortDramaEngine.subtitleCues(for: project)
        XCTAssertEqual(cues.count, 5, "关闭第2镜字幕后仅导出其余5条字幕轨")
        XCTAssertEqual(cues[0].startSeconds, 0.0, accuracy: 0.01)
        XCTAssertEqual(cues[0].endSeconds, 3.5, accuracy: 0.01)
        // Cue after skipped shot starts right after shot 0 + shot 1 trimmed durations
        let expectedCue1Start = project.shots[0].trimmedDuration + project.shots[1].trimmedDuration
        XCTAssertEqual(cues[1].startSeconds, expectedCue1Start, accuracy: 0.05)

        // Global subtitle switch off -> empty cues
        project.globalSubtitlesEnabled = false
        XCTAssertTrue(WuMindShortDramaEngine.subtitleCues(for: project).isEmpty)
    }

    func testStoryboardJSONParsingWithMarkdownFenceAndFallback() {
        let fenced = """
        ```json
        {
          "title": "雾夜来电",
          "characters": [
            { "name": "苏澄", "roleSummary": "急诊医生", "appearanceTag": "白大褂，短发", "voice": "warmFemale" }
          ],
          "shots": [
            { "title": "第1镜", "framing": "近景", "cameraMovement": "缓推", "visualPrompt": "医院走廊冷光", "characterName": "苏澄", "dialogue": "这通电话来自三年前。", "durationSeconds": 5 }
          ]
        }
        ```
        """
        let parsed = WuMindShortDramaEngine.parseStoryboard(
            from: fenced,
            premise: "深夜急诊室接到三年前的求救电话",
            genre: .suspense,
            targetDurationSeconds: 30,
            defaultEngine: .kling
        )
        XCTAssertEqual(parsed.title, "雾夜来电")
        XCTAssertEqual(parsed.characters.count, 1)
        XCTAssertEqual(parsed.characters[0].voicePreset, .warmFemale)
        XCTAssertEqual(parsed.shots.count, 1)
        XCTAssertEqual(parsed.shots[0].cameraFraming, .closeUp)
        XCTAssertEqual(parsed.shots[0].preferredEngine, .kling)

        // Broken output falls back gracefully to a complete multi-shot storyboard
        let fallback = WuMindShortDramaEngine.parseStoryboard(
            from: "not json at all",
            premise: "电梯停电后陌生人拿出我的照片",
            genre: .suspense,
            targetDurationSeconds: 36,
            defaultEngine: .seedance
        )
        XCTAssertEqual(fallback.shots.count, 6)
        XCTAssertEqual(fallback.characters.count, 2)
    }

    func testSora2SixSecondTimelineGeneratesEightSecondsTrimsTo36sAndLabelsRoughCut() throws {
        var project = WuMindShortDramaEngine.sampleVerticalDrama(defaultEngine: .sora2)
        XCTAssertEqual(project.shots.count, 6)
        XCTAssertEqual(WuMindShortDramaEngine.totalTrimmedDuration(for: project), 36.0, accuracy: 0.01)
        XCTAssertEqual(WuMindShortDramaEngine.renderedShotCount(for: project), 0)
        XCTAssertEqual(WuMindShortDramaEngine.exportKind(for: project), .roughCutPreview)
        XCTAssertEqual(WuMindShortDramaEngine.exportKind(for: project).title, "粗剪预览")

        // Shot 1 has 6.0s timeline, Sora 2 only allows [4, 8, 12] -> must plan 8s generation + trim to 6s, NEVER silently swap model
        let shot1 = project.shots[0]
        let plan = WuMindDramaVideoEngine.sora2.generationPlan(
            timelineSeconds: shot1.durationSeconds,
            aspectRatio: .portrait9x16,
            hasReferenceImage: true
        )
        XCTAssertEqual(plan.engine, .sora2)
        XCTAssertEqual(plan.timelineSeconds, 6.0, accuracy: 0.01)
        XCTAssertEqual(plan.generationDurationSeconds, 8)
        XCTAssertTrue(plan.needsTrimToTimeline)
        XCTAssertTrue(plan.requiresUserConfirmation)
        XCTAssertTrue(plan.canSubmit)
        XCTAssertEqual(plan.estimatedCostYuan, 5.76, accuracy: 0.01)
        XCTAssertTrue(plan.durationSummary.contains("生成 8 秒，剪入 6 秒"))
        XCTAssertNotNil(plan.referenceImageWarning, "选定不支持参考图的模型时必须立即提示，且不自动换模型")
        XCTAssertNotNil(plan.confirmationMessage)

        // Applying an 8s generated take to Shot 1 updates progress 0/6 -> 1/6 while keeping timeline strictly at 36.0s
        let take1 = WuMindShotTake(
            takeNumber: 1,
            engine: .sora2,
            modelID: "sora-2",
            promptUsed: shot1.visualPrompt,
            revisionNote: "首版生成",
            videoFilename: "shot1_take1.mp4",
            durationSeconds: Double(plan.generationDurationSeconds),
            estimatedCostYuan: plan.estimatedCostYuan,
            usedReferenceImage: false
        )
        let otherShotsBefore = Array(project.shots.dropFirst())
        project = WuMindShortDramaEngine.applySingleShotTake(project: project, shotID: shot1.id, take: take1)
        XCTAssertEqual(WuMindShortDramaEngine.renderedShotCount(for: project), 1)
        XCTAssertEqual(project.shots[0].durationSeconds, 6.0, accuracy: 0.01)
        XCTAssertEqual(project.shots[0].trimmedDuration, 6.0, accuracy: 0.01)
        XCTAssertEqual(WuMindShortDramaEngine.totalTrimmedDuration(for: project), 36.0, accuracy: 0.01)
        XCTAssertEqual(Array(project.shots.dropFirst()), otherShotsBefore, "其余 5 镜严禁被改动")
        XCTAssertEqual(WuMindShortDramaEngine.exportKind(for: project), .roughCutPreview)

        // Single-shot reshoot replaces ONLY Shot 1 active take while keeping Take 1 for A/B rollback & total duration 36.0s
        let take2 = WuMindShotTake(
            takeNumber: 2,
            engine: .sora2,
            modelID: "sora-2",
            promptUsed: shot1.visualPrompt,
            revisionNote: "换成近景",
            videoFilename: "shot1_take2.mp4",
            durationSeconds: 8.0,
            estimatedCostYuan: 5.76,
            usedReferenceImage: false
        )
        project = WuMindShortDramaEngine.applySingleShotTake(project: project, shotID: shot1.id, take: take2)
        XCTAssertEqual(project.shots[0].takes.count, 2)
        XCTAssertEqual(project.shots[0].activeTake?.id, take2.id)
        XCTAssertEqual(WuMindShortDramaEngine.renderedShotCount(for: project), 1)
        XCTAssertEqual(WuMindShortDramaEngine.totalTrimmedDuration(for: project), 36.0, accuracy: 0.01)
        XCTAssertEqual(Array(project.shots.dropFirst()), otherShotsBefore)

        // Once all 6 shots have generated takes, export kind upgrades from 粗剪预览 to 成片导出
        for shot in project.shots.dropFirst() {
            let t = WuMindShotTake(
                takeNumber: 1,
                engine: .sora2,
                modelID: "sora-2",
                promptUsed: shot.visualPrompt,
                revisionNote: "首版生成",
                videoFilename: "\(shot.id.uuidString).mp4",
                durationSeconds: 8.0,
                estimatedCostYuan: 5.76,
                usedReferenceImage: false
            )
            project = WuMindShortDramaEngine.applySingleShotTake(project: project, shotID: shot.id, take: t)
        }
        XCTAssertEqual(WuMindShortDramaEngine.renderedShotCount(for: project), 6)
        XCTAssertEqual(WuMindShortDramaEngine.exportKind(for: project), .finalMaster)
        XCTAssertEqual(WuMindShortDramaEngine.totalTrimmedDuration(for: project), 36.0, accuracy: 0.01)
    }
}

private final class LockedArray<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Element] = []

    func append(_ element: Element) {
        lock.lock()
        storage.append(element)
        lock.unlock()
    }

    func snapshot() -> [Element] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
