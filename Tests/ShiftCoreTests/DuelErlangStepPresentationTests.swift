import XCTest
@testable import ShiftCore

final class DuelErlangStepPresentationTests: XCTestCase {
    private func ready(_ steps: Int = 7) -> DuelErlangSparring {
        var game = DuelErlangSparring(mode: .teamRaid)
        for _ in 0..<steps { game.step(erlangAction: .walk(1), partnerAction: .walk(-1)) }
        for _ in 0..<30 { game.step() }
        game.step(erlangAction: .meditate)
        for _ in 0..<420 { game.step() }
        game.step(erlangAction: .ascend)
        return game
    }

    func testThreeUniqueCastsAndRisingDamage() {
        var game = ready()
        for (i, expected) in [21, 27, 35].enumerated() {
            game.step(erlangAction: .avatarStep)
            let id = UInt64(i+1)
            XCTAssertEqual(game.stepPresentation.castID, id)
            XCTAssertEqual(game.stepPresentation.stage, i+1)
            var beats = [Int](), hits = [Int]()
            for _ in 0..<14 {
                game.step()
                let v = game.stepPresentation
                if v.groundBeat { beats.append(v.age) }
                if v.contact == .landed { hits.append(v.damage ?? -1) }
            }
            XCTAssertEqual(beats, [7])
            XCTAssertEqual(hits, [expected])
        }
        XCTAssertEqual(game.fighters[1].health, 17)
        XCTAssertGreaterThan(game.avatarStepCooldown, 0)
        game.step(erlangAction: .avatarStep)
        XCTAssertEqual(game.stepPresentation.castID, 3)
        XCTAssertNil(game.stepPresentation.contact)
    }

    func testGroundBeatAndLateContactAreSeparate() {
        var game = ready(0)
        game.step(erlangAction: .avatarStep)
        for _ in 0..<6 { game.step() }
        XCTAssertTrue(game.stepPresentation.groundBeat)
        XCTAssertNil(game.stepPresentation.contact)
        game.step(partnerAction: .walk(-1))
        XCTAssertFalse(game.stepPresentation.groundBeat)
        XCTAssertEqual(game.stepPresentation.contact, .landed)
        XCTAssertEqual(game.stepPresentation.age, 8)
        XCTAssertEqual(game.stepPresentation.contactX, 60)
        game.step()
        XCTAssertNil(game.stepPresentation.contact)
    }

    func testWindowBoundaryIsAppliedBeforeInput() {
        for (delay, expected) in [(31, 2), (32, 1)] {
            var game = ready()
            game.step(erlangAction: .avatarStep)
            for _ in 1..<delay { game.step() }
            game.step(erlangAction: .avatarStep)
            XCTAssertEqual(game.stepPresentation.stage, expected)
            XCTAssertEqual(game.stepPresentation.castID, 2)
        }
    }

    func testGuardAndWhiffNeverInventDamageOrKnockdown() {
        for (approach, guardOn) in [(7, true), (0, false)] {
            var game = ready(approach)
            game.step(erlangAction: .avatarStep, partnerAction: guardOn ? .guardOn : nil)
            for _ in 0..<6 { game.step() }
            XCTAssertTrue(game.stepPresentation.groundBeat)
            XCTAssertEqual(game.stepPresentation.contact, guardOn ? .blocked : nil)
            XCTAssertEqual(game.fighters[1].health, 100)
            XCTAssertEqual(game.fighters[1].knockdown, 0)
            for _ in 0..<9 { game.step() }
            XCTAssertEqual(game.stepPresentation.outcome, guardOn ? .blocked : .missed)
        }
    }

    func testInterruptBeforeGroundAndResetClearAllEdges() {
        var game = ready(10)
        game.step(erlangAction: .avatarStep, partnerAction: .spear)
        for _ in 0..<25 {
            game.step()
            XCTAssertFalse(game.stepPresentation.groundBeat)
            XCTAssertNil(game.stepPresentation.contact)
        }
        XCTAssertEqual(game.stepPresentation.outcome, .cancelled)
        XCTAssertEqual(game.fighters[1].health, 100)
        game.resetRound()
        XCTAssertEqual(game.stepPresentation.outcome, .reset)
        XCTAssertEqual(game.avatarStepWindow, 0)
        game.step(erlangAction: .avatarStep)
        XCTAssertEqual(game.stepPresentation.stage, 1)
        XCTAssertEqual(game.stepPresentation.castID, 2)
    }
}
