import AVFoundation
import XCTest
@testable import ShiftReminder

@MainActor
private final class ScriptedLiveConnection: AILiveConnection {
    private var incoming: [URLSessionWebSocketTask.Message] = []
    private var waiting: CheckedContinuation<URLSessionWebSocketTask.Message, Error>?
    var writes: [[String: Any]] = []
    var closed = false
    var disconnected = false
    var rejectGreeting = false

    func read() async throws -> URLSessionWebSocketTask.Message {
        if disconnected { throw URLError(.networkConnectionLost) }
        if !incoming.isEmpty { return incoming.removeFirst() }
        guard !closed else { throw CancellationError() }
        return try await withCheckedThrowingContinuation { waiting = $0 }
    }
    func deliver(_ object: [String: Any]) throws {
        let packet = URLSessionWebSocketTask.Message.data(try JSONSerialization.data(withJSONObject: object))
        if let receiver = waiting {
            waiting = nil
            receiver.resume(returning: packet)
        } else { incoming.append(packet) }
    }
    func write(_ data: Data) async throws {
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        writes.append(message)
        if rejectGreeting, message["type"] as? String == "response.create" { throw URLError(.networkConnectionLost) }
    }
    func close() {
        closed = true
        waiting?.resume(throwing: CancellationError())
        waiting = nil
    }
    func disconnect() {
        disconnected = true
        waiting?.resume(throwing: URLError(.networkConnectionLost))
        waiting = nil
    }
    func acknowledge() throws {
        try deliver(["type":"session.created"])
        let update = try XCTUnwrap(JSONSerialization.jsonObject(with: AILiveProtocol.sessionUpdate()) as? [String: Any])
        try deliver(["type":"session.updated", "session":try XCTUnwrap(update["session"])])
    }
    func audio(item: String) throws {
        try deliver(["type":"response.output_audio.delta", "item_id":item, "content_index":0,
                     "delta":Data(repeating: 3, count: 4_800).base64EncodedString()])
    }
}

@MainActor
private final class ScriptedLiveAudio: AILiveAudioIO {
    var activeOutputRouteDescription = "离线输出 A"
    var isReconfiguring = false
    var hasPendingPlayback = false
    var onPlaybackStarted: (@MainActor () -> Void)?
    var onPlaybackDrained: (@MainActor () -> Void)?
    var recorder: (@Sendable (Data) -> Void)?
    var playCount = 0
    var recoveries = 0
    var canRecover = true
    func start(onCapture: @escaping @Sendable (Data) -> Void) throws { recorder = onCapture }
    func play(_ pcm16: Data) throws { playCount += 1; hasPendingPlayback = true; onPlaybackStarted?() }
    func playedMilliseconds() -> Int { 25 }
    func resetPlayback() { hasPendingPlayback = false }
    func ownsEngine(_ candidate: Any?) -> Bool { true }
    func reconfigureForRouteChange() async -> Bool {
        recoveries += 1
        activeOutputRouteDescription = "离线输出 B"
        return canRecover
    }
    func stop() { recorder = nil; hasPendingPlayback = false }
}

@MainActor
final class WuMindLiveAcceptanceTests: XCTestCase {
    private func until(_ description: String, _ predicate: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTFail(description, file: file, line: line)
    }

    func testThreeBargeInsAndRouteRecoveryDoNotRedialOrRepeatGreeting() async throws {
        let ws = ScriptedLiveConnection(), audio = ScriptedLiveAudio()
        var opens = 0
        let call = AILiveCallController(audio: audio, permission: { true }) { _, _ in opens += 1; return ws }
        call.setForeground(true)
        call.beginOwnAPI(model: AILiveProtocol.models[0], apiKey: "fixture", customBaseURL: "https://offline.invalid")
        try ws.acknowledge()
        try await until("No greeting after session.updated") { ws.writes.contains { $0["type"] as? String == "response.create" } }
        for round in 1...3 {
            let item = "audio-\(round)"
            try ws.audio(item: item)
            try await until("Round \(round) never reached playback") { audio.playCount == round && call.callPhase == .speaking }
            try ws.deliver(["type":"input_audio_buffer.speech_started"])
            try await until("Round \(round) never truncated") { ws.writes.contains { $0["item_id"] as? String == item && $0["audio_end_ms"] as? Int == 25 } }
            XCTAssertFalse(audio.hasPendingPlayback)
            try ws.audio(item: item)
            audio.recorder?(Data([0, 0]))
            try ws.deliver(["type":"input_audio_buffer.speech_stopped"])
            try await until("Mic input was never uploaded") { ws.writes.filter { $0["type"] as? String == "input_audio_buffer.append" }.count == round }
            XCTAssertEqual(audio.playCount, round)
        }
        call.handleAudioRouteRecovery()
        try await until("Route change never settled") { call.telemetry.outputRoute == "离线输出 B" }
        XCTAssertEqual(audio.recoveries, 1)
        XCTAssertEqual(opens, 1)
        XCTAssertEqual(ws.writes.filter { $0["type"] as? String == "response.create" }.count, 1)
        XCTAssertNotNil(call.telemetry.firstPlaybackMS)
        call.hangUp()
        XCTAssertTrue(ws.closed)
        XCTAssertNil(audio.recorder)
        XCTAssertFalse(call.active)
    }

    func testSilentHandshakeAndGreetingWriteFailureReleaseCapture() async throws {
        for reject in [false, true] {
            let ws = ScriptedLiveConnection(), audio = ScriptedLiveAudio()
            ws.rejectGreeting = reject
            let call = AILiveCallController(audio: audio, permission: { true }, replyTimeout: 50_000_000) { _, _ in ws }
            call.setForeground(true)
            call.beginOwnAPI(model: AILiveProtocol.models[0], apiKey: "fixture", customBaseURL: "https://offline.invalid")
            try ws.acknowledge()
            try await until("Silent call left open") { call.callPhase == .disconnected }
            XCTAssertTrue(call.status.contains(reject ? "问候请求发送失败" : "等待语音回复超时"))
            XCTAssertTrue(ws.closed)
            XCTAssertNil(audio.recorder)
            XCTAssertEqual(ws.writes.filter { $0["type"] as? String == "response.create" }.count, 1)
        }
    }

    func testDeniedPermissionAndFailedRouteExit() async throws {
        let audio = ScriptedLiveAudio(), ws = ScriptedLiveConnection()
        let denied = AILiveCallController(audio: audio, permission: { false }) { _, _ in XCTFail("Opened socket without permission"); return ws }
        denied.setForeground(true)
        denied.beginOwnAPI(model: AILiveProtocol.models[0], apiKey: "fixture", customBaseURL: "https://offline.invalid")
        try await until("Permission failure missing") { denied.needsMicrophoneSettings }
        XCTAssertFalse(denied.active)
        XCTAssertNil(audio.recorder)

        audio.canRecover = false
        let connected = AILiveCallController(audio: audio, permission: { true }) { _, _ in ws }
        connected.setForeground(true)
        connected.beginOwnAPI(model: AILiveProtocol.models[0], apiKey: "fixture", customBaseURL: "https://offline.invalid")
        try ws.acknowledge()
        try await until("Handshake incomplete") { connected.connected }
        connected.handleAudioRouteRecovery()
        try await until("Recovery failure left call open") { connected.callPhase == .disconnected }
        XCTAssertTrue(connected.status.contains("音频设备"))
        XCTAssertTrue(ws.closed)
        XCTAssertNil(audio.recorder)
    }

    func testDisconnectRequiresManualRedialAndLateEventsCannotCloseNewCall() async throws {
        let first = ScriptedLiveConnection(), next = ScriptedLiveConnection(), audio = ScriptedLiveAudio()
        var opens = 0
        let call = AILiveCallController(audio: audio, permission: { true }) { _, _ in
            opens += 1
            return opens == 1 ? first : next
        }
        call.setForeground(true)
        call.beginOwnAPI(model: AILiveProtocol.models[0], apiKey: "fixture", customBaseURL: "https://offline.invalid")
        try first.acknowledge()
        try await until("Initial handshake incomplete") { call.connected && first.writes.count == 2 }
        first.disconnect()
        try await until("Disconnect not surfaced") { call.callPhase == .disconnected }
        XCTAssertNil(audio.recorder)
        XCTAssertEqual(opens, 1)

        call.beginOwnAPI(model: AILiveProtocol.models[0], apiKey: "fixture", customBaseURL: "https://offline.invalid")
        try next.acknowledge()
        try await until("Manual reconnect failed") { call.connected && next.writes.count == 2 }
        call.toggleMute()
        audio.recorder?(Data([0, 0]))
        call.toggleMute()
        audio.recorder?(Data([1, 2]))
        try await until("Unmuted mic not sent") { next.writes.contains { $0["type"] as? String == "input_audio_buffer.append" } }
        XCTAssertEqual(next.writes.compactMap { $0["audio"] as? String }, [Data([1, 2]).base64EncodedString()])
        call.hangUp()
        XCTAssertEqual(opens, 2)
        XCTAssertTrue(first.closed && next.closed)
        XCTAssertNil(audio.recorder)
    }

    func testHardwareFormatSamplesConvertToNonSilentWirePCM() throws {
        let source = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let wire = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: false))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 960))
        buffer.frameLength = 960
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<960 { samples[i] = Float(sin(Double(i) * 0.06) * 0.5) }
        let received = expectation(description: "AVAudioConverter emitted PCM16")
        let converter = try LiveCaptureConverter(from: source, to: wire) { bytes in
            XCTAssertGreaterThan(bytes.count, 600)
            XCTAssertLessThanOrEqual(bytes.count, 960)
            XCTAssertTrue(bytes.count.isMultiple(of: 2))
            XCTAssertTrue(bytes.contains { $0 != 0 })
            received.fulfill()
        }
        converter.consume(buffer)
        wait(for: [received], timeout: 1)
    }
}
