import XCTest
@testable import ShiftCore

final class StarPulseTests: XCTestCase {
    private func fixture() -> StarRail.Game {
        let cards = (0..<9).map { StarRail.Card(id:$0,kind:$0/3,x:($0%3)*4,y:($0/3)*4,z:0,rail:$0>=6 ? 0 : nil) }
        let rail = StarRail.Rail(id:0,name:"A",delta:.init(x:16,y:0),extraStops:[.init(x:32,y:0)])
        let configuration = StarJourney.Configuration(runID:UUID(),ability:.pulse,chapter:0)
        return .init(stage:.init(id:201,title:"Pulse fixture",lesson:"",objective:"",tip:"",cards:cards,
            rails:[rail],requiredArrivals:4,plannedMoves:1,targetPeak:3,journey:configuration))
    }
    func testTwoTriplesChargeFreeFarTravelAndUndoRestoresCharge() throws {
        var game = fixture()
        for id in 0..<3 { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.state.pulseCharge,1)
        XCTAssertEqual(game.moveCost(rail:0,to:2,in:game.state),2)
        for id in 3..<6 { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.state.pulseCharge,2)
        let charged = game.state
        var emptyBattery = charged; emptyBattery.energy = 0
        XCTAssertEqual(game.transition(.travel(rail:0,to:2),from:emptyBattery)?.energy,0,"Charged travel works with an empty battery")
        XCTAssertTrue(try XCTUnwrap(game.preview(0,to:2,in:game.state)).canMove)
        XCTAssertEqual(game.state,charged)
        XCTAssertTrue(game.perform(.travel(rail:0,to:2)))
        XCTAssertEqual(game.state.energy,2)
        XCTAssertEqual(game.state.spentEnergy,0)
        XCTAssertEqual(game.state.pulseCharge,0)
        XCTAssertEqual(game.moveCost(rail:0,to:0,in:game.state),1)
        XCTAssertTrue(game.undo()); XCTAssertEqual(game.state,charged)
        XCTAssertTrue(game.perform(.travel(rail:0,to:2)))
        XCTAssertEqual(game.state.pulseCharge,0)
    }
    func testEarlyMoveResetsPartialChargeAndRejectedMoveDoesNotSpendIt() {
        var game = fixture()
        for id in 0..<3 { XCTAssertTrue(game.perform(.pick(id))) }
        let before = game.state
        XCTAssertFalse(game.perform(.travel(rail:0,to:2)))
        XCTAssertEqual(game.state,before)
        XCTAssertTrue(game.perform(.travel(rail:0,to:1)))
        XCTAssertEqual(game.state.pulseCharge,0)
        XCTAssertEqual(game.state.energy,0)
        for id in 3..<6 { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.state.pulseCharge,1)
    }
    func testChargedTravelStillRespectsClosedStarGate() {
        let config = StarJourney.Configuration(runID:UUID(),ability:.pulse,chapter:1,route:.signal)
        let game = StarRail.Game(stage:config.stage)
        var charged = game.state; charged.pulseCharge = 2
        XCTAssertFalse(game.gateOpen(in:charged))
        XCTAssertNil(game.transition(.travel(rail:0,to:2),from:charged))
        XCTAssertTrue(game.rejection(.travel(rail:0,to:2),in:charged)!.contains("星门"))
    }
    func testEveryRealJourneyPrefixRestoresPulseFromActions() throws {
        for route in StarJourney.Route.allCases {
            var save = StarJourney.Save(); save.start(ability:.pulse)
            for chapter in 0...2 {
                var game = try XCTUnwrap(save.active).game
                XCTAssertEqual(game.state.pulseCharge,0,"No charge carried between chapters")
                guard case .solved(let actions,_) = StarRailSolver.solveJourney(game) else {
                    XCTFail("Pulse route has no solution"); return
                }
                for action in actions {
                    XCTAssertTrue(game.perform(action))
                    let data = try JSONEncoder().encode(game.archive)
                    let archive = try JSONDecoder().decode(StarRail.Game.Archive.self,from:data)
                    XCTAssertEqual(StarRail.Game(archive:archive),game)
                }
                XCTAssertEqual(game.status,.won); XCTAssertEqual(game.stars,3)
                XCTAssertTrue(save.keep(game,otherStars:0))
                if chapter < 2 { XCTAssertTrue(save.advance(route:chapter == 0 ? route : nil)) }
            }
        }
    }
}
