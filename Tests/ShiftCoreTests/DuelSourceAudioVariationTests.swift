import XCTest
@testable import ShiftCore

final class DuelSourceAudioVariationTests: XCTestCase {
    private let category = "triadMarker:common_floorfall_h_hit_head_fall"

    func testAcceptedEventOrdinalsAreStableAcrossRenderCadenceAndOtherCategories() throws {
        let expected = try (0..<96).map { ordinal in
            try XCTUnwrap(DuelSourceAudioVariation.index(category: category, eventOrdinal: UInt64(ordinal), count: 7))
        }
        var replay: [Int] = []
        for ordinal in 0..<96 {
            for redraw in 0..<(ordinal % 5 + 1) {
                XCTAssertEqual(DuelSourceAudioVariation.index(category: category, eventOrdinal: UInt64(ordinal), count: 7), expected[ordinal])
                _ = DuelSourceAudioVariation.index(category: "panguCue:independent", eventOrdinal: UInt64(redraw), count: 3)
            }
            replay.append(try XCTUnwrap(DuelSourceAudioVariation.index(category: category, eventOrdinal: UInt64(ordinal), count: 7)))
        }
        XCTAssertEqual(replay, expected)
        XCTAssertEqual(Set(replay), Set(0..<7))
        XCTAssertNotEqual(Array(replay.prefix(7)), Array(replay.dropFirst(7).prefix(7)), "Alternatives must not repeat as a fixed seven-item playlist")
    }

    func testRepeatedAlternativesRetainArrayPositionWeightsAndCanRepeatConsecutively() throws {
        let authored = ["body_a", "body_b", "body_b"]
        let draws = try (0..<4096).map { ordinal in
            authored[try XCTUnwrap(DuelSourceAudioVariation.index(category: category, eventOrdinal: UInt64(ordinal), count: authored.count))]
        }
        let a = draws.filter { $0 == "body_a" }.count
        let b = draws.filter { $0 == "body_b" }.count
        XCTAssertGreaterThan(a, 1_100); XCTAssertLessThan(a, 1_600)
        XCTAssertGreaterThan(b, 2_496); XCTAssertLessThan(b, 2_996)
        XCTAssertTrue(zip(draws, draws.dropFirst()).contains { $0 == "body_a" && $1 == "body_a" }, "Source Random.Range allows immediate repeats")
    }

    func testResetOrdinalRestartsTheSameStreamAndMaximumOrdinalStaysBounded() throws {
        let first = try XCTUnwrap(DuelSourceAudioVariation.index(category: category, eventOrdinal: 0, count: 7))
        for ordinal in [UInt64.max - 1, UInt64.max, 0] {
            let choice = try XCTUnwrap(DuelSourceAudioVariation.index(category: category, eventOrdinal: ordinal, count: 7))
            XCTAssertTrue((0..<7).contains(choice))
        }
        XCTAssertEqual(DuelSourceAudioVariation.index(category: category, eventOrdinal: 0, count: 7), first)
        XCTAssertEqual(DuelSourceAudioVariation.index(category: category, eventOrdinal: UInt64.max, count: 1), 0)
    }

    func testInvalidSourceGroupsFailWithoutInventingAFallbackVariant() {
        for count in [-1, 0, 33, Int.max] {
            XCTAssertNil(DuelSourceAudioVariation.index(category: category, eventOrdinal: 0, count: count))
        }
        XCTAssertNil(DuelSourceAudioVariation.index(category: "", eventOrdinal: 0, count: 7))
        XCTAssertNil(DuelSourceAudioVariation.index(category: String(repeating: "x", count: 129), eventOrdinal: 0, count: 7))
    }
}
