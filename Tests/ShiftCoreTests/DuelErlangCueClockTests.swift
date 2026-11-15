import XCTest
@testable import ShiftCore

final class DuelErlangCueClockTests: XCTestCase {
    typealias Clock = DuelErlangCueClock

    func testThreeAuthoredPositionTypesUseTheirOwnClockOffsets() throws {
        var clock = try Clock(origin: .untrimmed, markers: [
            .init(id: "ordinary", at: .frame(3), presentation: .visualEffect),
            .init(id: "named", at: .intervalStart(3), presentation: .sound),
            .init(id: "start", at: .animationStart, presentation: .cast),
        ])
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [.presentation(id: "start", channel: .cast, sourceSample: 0)])
        XCTAssertEqual(clock.advance(toVisibleSample: 1), [])
        XCTAssertEqual(clock.advance(toVisibleSample: 2), [.presentation(id: "named", channel: .sound, sourceSample: 2)])
        XCTAssertEqual(clock.advance(toVisibleSample: 3), [.presentation(id: "ordinary", channel: .visualEffect, sourceSample: 3)])
    }

    func testKnownCropDoesNotShiftFrameMarkersOrReplaySkippedStart() throws {
        var clock = try Clock(origin: .known(firstSourceSample: 8), markers: [
            .init(id: "old", at: .animationStart, presentation: .cast),
            .init(id: "sound", at: .frame(8), presentation: .sound),
            .init(id: "fx", at: .intervalStart(9), presentation: .visualEffect),
            .init(id: "later", at: .frame(11), presentation: .visualEffect),
        ])
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [
            .presentation(id: "sound", channel: .sound, sourceSample: 8),
            .presentation(id: "fx", channel: .visualEffect, sourceSample: 8),
        ])
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [])
        XCTAssertEqual(clock.advance(toVisibleSample: 8), [.presentation(id: "later", channel: .visualEffect, sourceSample: 11)])
        XCTAssertEqual(clock.advance(toVisibleSample: 3), [])
        XCTAssertEqual(clock.advance(toVisibleSample: 8), [])
    }

    func testUnknownOriginFailsClosedAndHitsStillRequireAuthoritativeEvent() throws {
        var clock = try Clock(origin: .unknown, markers: [
            .init(id: "a", at: .animationStart, presentation: .cast),
            .init(id: "b", at: .intervalStart(5), presentation: .sound),
        ])
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [])
        XCTAssertEqual(clock.advance(toVisibleSample: .max), [])
        XCTAssertEqual(clock.recordGameplayHit(id: "a", atSimulationTick: 17), .gameplayHit(id: "a", simulationTick: 17))
        XCTAssertNil(clock.recordGameplayHit(id: "a", atSimulationTick: 18))
        clock.beginNewPlayback()
        XCTAssertEqual(clock.recordGameplayHit(id: "a", atSimulationTick: 21), .gameplayHit(id: "a", simulationTick: 21))
        XCTAssertEqual(clock.advance(toVisibleSample: 10), [])
    }

    func testPresentationAndHitMayShareIdentityWithoutEitherSuppressingOther() throws {
        var clock = try Clock(origin: .untrimmed, markers: [.init(id: "same", at: .animationStart, presentation: .cast)])
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [.presentation(id: "same", channel: .cast, sourceSample: 0)])
        XCTAssertEqual(clock.recordGameplayHit(id: "same", atSimulationTick: 30), .gameplayHit(id: "same", simulationTick: 30))
        clock.beginNewPlayback()
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [.presentation(id: "same", channel: .cast, sourceSample: 0)])
    }

    func testInvalidOrAmbiguousMarkersAndOverflowAreRejected() throws {
        XCTAssertThrowsError(try Clock(origin: .untrimmed, markers: [.init(id: "0", at: .intervalStart(0), presentation: .sound)]))
        XCTAssertThrowsError(try Clock(origin: .known(firstSourceSample: -1), markers: []))
        let marker = Clock.Marker(id: "same", at: .animationStart, presentation: .cast)
        XCTAssertThrowsError(try Clock(origin: .untrimmed, markers: [marker, marker]))
        var clock = try Clock(origin: .known(firstSourceSample: .max), markers: [.init(id: "last", at: .frame(.max), presentation: .sound)])
        XCTAssertEqual(clock.advance(toVisibleSample: 1), [])
        XCTAssertEqual(clock.advance(toVisibleSample: 0), [.presentation(id: "last", channel: .sound, sourceSample: .max)])
    }
}
