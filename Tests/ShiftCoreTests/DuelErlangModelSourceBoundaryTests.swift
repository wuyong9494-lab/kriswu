import Foundation
import XCTest
@testable import ShiftCore

final class DuelErlangModelSourceBoundaryTests: XCTestCase {
    private func sourceTracks() throws -> [[String: Any]] {
        guard let path = ProcessInfo.processInfo.environment["ERLANG_MODEL_TRACKS"] else {
            throw XCTSkip("Authenticated private D15 model tracks are not staged")
        }
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any])
        return try XCTUnwrap(object["summonTracks"] as? [[String: Any]])
    }
    private func decode(_ value: [String: Any]) throws -> DuelSummonMotionTrack {
        try JSONDecoder().decode(DuelSummonMotionTrack.self, from: JSONSerialization.data(withJSONObject: value))
    }
    func testActualSevenModelsKeepAnimationEndAndEarlierSwordDeletionSeparate() throws {
        let tracks = try sourceTracks().map(decode)
        XCTAssertEqual(tracks.count, 7)
        for track in tracks { XCTAssertNoThrow(try track.validate()) }
        let sword = try XCTUnwrap(tracks.first { $0.role == "erlangSummon_sword" })
        XCTAssertEqual(sword.root.count, 101)
        XCTAssertEqual(sword.sourceEndEventTick, 92)
        XCTAssertEqual(sword.sourceDeleteEventTick, 70)
        XCTAssertEqual(sword.sourceLastActiveTick, 70, "DeleteModel must end the model before its later AnimationEnd")
        let meditation = try XCTUnwrap(tracks.first { $0.role == "erlangSummon_meditation" })
        XCTAssertEqual(meditation.collisionEdges?.first?.radiusMillimeters, 2250)
        XCTAssertEqual(meditation.sourceLastActiveTick, 52)
        let earth = try XCTUnwrap(tracks.first { $0.role == "erlangSummon_earth" })
        XCTAssertEqual(earth.sourceLastActiveTick, 22)
        XCTAssertTrue((earth.collisionEdges ?? []).contains { edge in
            zip(edge.base, edge.tip).contains { abs($0.0.x - $0.1.x) > 40 }
        }, "The original long capsule must not be shortened to fit the arena")
    }
    func testLargeMeditationCapsuleExceptionRejectsWrongRoleGeometryAndSource() throws {
        let actual = try XCTUnwrap(sourceTracks().first { $0["role"] as? String == "erlangSummon_meditation" })
        for (key, value) in [("role", "erlangSummon_stomp"), ("clip", "different_motion"),
                             ("sourceSHA256", String(repeating: "0", count: 64)),
                             ("boneConfigurationSHA256", String(repeating: "1", count: 64))] {
            var changed = actual; changed[key] = value
            XCTAssertThrowsError(try decode(changed).validate(), "Unrelated geometry must not inherit the 2250 mm exception")
        }
        for radius in [2251, 2249] {
            var changed = actual, edges = try XCTUnwrap(actual["collisionEdges"] as? [[String: Any]])
            edges[0]["radiusMillimeters"] = radius; changed["collisionEdges"] = edges
            XCTAssertThrowsError(try decode(changed).validate())
        }
        var changed = actual, edges = try XCTUnwrap(actual["collisionEdges"] as? [[String: Any]])
        edges[0]["id"] = "Different_Huge_Capsule"; changed["collisionEdges"] = edges
        XCTAssertThrowsError(try decode(changed).validate())
    }
    func testDeleteEventMustStayWithinTheActualExportedTimeline() throws {
        let actual = try XCTUnwrap(sourceTracks().first { $0["role"] as? String == "erlangSummon_sword" })
        for tick in [-1, 101] {
            var changed = actual; changed["sourceDeleteEventTick"] = tick
            XCTAssertThrowsError(try decode(changed).validate())
        }
        var noDelete = actual; noDelete.removeValue(forKey: "sourceDeleteEventTick")
        XCTAssertEqual(try decode(noDelete).sourceLastActiveTick, 92)
    }
}
