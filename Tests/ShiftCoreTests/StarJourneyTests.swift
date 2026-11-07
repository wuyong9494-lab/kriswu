import XCTest
@testable import ShiftCore

final class StarJourneyTests: XCTestCase {
    private let id = UUID(uuidString:"11111111-1111-1111-1111-111111111111")!
    private func game(_ ability:StarJourney.Ability = .navigator, chapter:Int = 0,
                      route:StarJourney.Route = .signal, energy:Int = 0) -> StarRail.Game {
        .init(stage:StarJourney.Configuration(runID:id,ability:ability,chapter:chapter,
            route:chapter == 0 ? nil : route,openingEnergy:energy).stage)
    }
    private func win(_ initial:StarRail.Game, file:StaticString = #filePath, line:UInt = #line) throws -> StarRail.Game {
        guard case .solved(let actions,_) = StarRailSolver.solveJourney(initial) else {
            XCTFail("No three-star route for \(String(describing:initial.stage.journey))",file:file,line:line)
            throw NSError(domain:"JourneyTests",code:1)
        }
        var result = initial
        for action in actions { XCTAssertTrue(result.perform(action),file:file,line:line) }
        XCTAssertEqual(result.status,.won,file:file,line:line); XCTAssertEqual(result.stars,3,file:file,line:line)
        return result
    }
    private func completedSave(_ ability:StarJourney.Ability = .navigator, route:StarJourney.Route = .signal) throws -> StarJourney.Save {
        var save = StarJourney.Save(); save.start(ability:ability)
        for chapter in 0...2 {
            let won = try win(save.active!.game)
            XCTAssertTrue(save.keep(won,otherStars:12))
            if chapter < 2 { XCTAssertTrue(save.advance(route:chapter == 0 ? route : nil)) }
        }
        return save
    }
    private func edited(_ save:StarJourney.Save, _ edit:(inout [String:Any])->Void) throws -> Data {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(save.encoded())) as? [String:Any])
        edit(&json); return try JSONSerialization.data(withJSONObject:json)
    }

    func testAllAbilityRouteChainsCarryExactEnergyAndAwardOnlyTheirBest() throws {
        var all = StarJourney.Save()
        for ability in StarJourney.Ability.allCases { for route in StarJourney.Route.allCases {
            all.start(ability:ability)
            for chapter in 0...2 {
                let run = try XCTUnwrap(all.active), won = try win(run.game)
                XCTAssertEqual(won.stage.capacity,ability.capacity)
                XCTAssertEqual(won.stage.energyLimit,ability.energyLimit)
                XCTAssertTrue(all.keep(won,otherStars:12)); XCTAssertTrue(all.isValid)
                XCTAssertEqual(StarJourney.Save(data:try XCTUnwrap(all.encoded())),all)
                if chapter < 2 {
                    let expected = min(ability.energyLimit,(ability == .navigator ? 0 : won.state.energy) + (chapter == 0 && route == .supply ? 1 : 0))
                    XCTAssertTrue(all.advance(route:chapter == 0 ? route : nil))
                    XCTAssertEqual(all.active!.game.state.energy,expected)
                    XCTAssertTrue(all.isValid)
                }
            }
            XCTAssertTrue(all.active!.finished); XCTAssertEqual(all.active!.score,9)
            XCTAssertEqual(all.active!.rewardStars,route == .signal ? 10 : 9)
        } }
        XCTAssertEqual(all.best.count,8); XCTAssertEqual(all.totalStars,76)
        XCTAssertEqual(StarJourney.Save(data:try XCTUnwrap(all.encoded())),all)
    }

    func testGateRequiresActualTripleAndUndoRestoresTheLock() throws {
        let initial = game(chapter:1,energy:2), won = try win(initial)
        XCTAssertFalse(initial.gateOpen(in:initial.state))
        XCTAssertTrue(initial.preview(0,to:2,in:initial.state)!.reason!.contains("星门"))
        var replay = initial, opened = false
        for action in won.actions {
            let previous = replay.state
            XCTAssertTrue(replay.perform(action))
            if replay.gateOpen(in:replay.state) && !replay.gateOpen(in:previous) {
                XCTAssertEqual(replay.state.matches,previous.matches+1)
                guard case .pick(let card) = action else { return XCTFail("Gate must open through a match") }
                XCTAssertEqual(replay.stage.cards[card].kind,replay.starGate!.kind)
                XCTAssertTrue(replay.undo()); XCTAssertEqual(replay.state,previous)
                XCTAssertFalse(replay.gateOpen(in:replay.state))
                XCTAssertTrue(replay.perform(action)); opened = true; break
            }
        }
        XCTAssertTrue(opened)
        XCTAssertEqual(StarRail.Game(archive:replay.archive),replay)
    }

    func testEscortWinsWithRemainingCardsButNeverAllowsPickingTheCore() throws {
        for route in StarJourney.Route.allCases {
            let initial = game(.capacitor,chapter:1,route:route), core = initial.stage.journey!.coreID!
            let ordinary=initial.stage.cards.filter { !initial.isStarCore($0.id) }
            XCTAssertTrue(Dictionary(grouping:ordinary,by:\.kind).values.allSatisfy { $0.count == 3 })
            XCTAssertFalse(ordinary.contains { $0.kind == initial.stage.cards[core].kind })
            XCTAssertFalse(initial.kindPlans(in:initial.state).contains { $0.kind == initial.stage.cards[core].kind })
            XCTAssertTrue(initial.rejection(.pick(core),in:initial.state)!.contains("星核"))
            XCTAssertFalse(initial.legalActions(in:initial.state).contains(.pick(core)))
            let won = try win(initial)
            XCTAssertGreaterThan(won.state.remaining.nonzeroBitCount,0)
            XCTAssertTrue(won.contains(core,in:won.state)); XCTAssertTrue(won.state.tray.isEmpty)
            XCTAssertEqual(won.state.positions[0],route.destination)
            XCTAssertTrue(won.gateOpen(in:won.state))
            var missingCore = won.state; missingCore.remaining &= ~(UInt64(1) << core)
            XCTAssertFalse(won.objectiveComplete(in:missingCore))
            var wrongStop = won.state; wrongStop.positions[0] = route == .supply ? 2 : 1
            XCTAssertFalse(won.objectiveComplete(in:wrongStop))
        }
    }

    func testLimitedReturnRejectsOverspendAndAllowsExactBudget() throws {
        for ability in StarJourney.Ability.allCases {
            let initial = game(ability,chapter:2), won = try win(initial)
            let budget = initial.stage.journey!.energyBudget!
            XCTAssertLessThanOrEqual(won.state.spentEnergy,budget)
            var checked = 0
            for (index,action) in won.actions.enumerated() {
                let state = won.replayStates[index]
                let rail:Int, destination:Int
                switch action {
                case .pick: continue
                case .shift(let id): rail = id; destination = 1-state.positions[id]
                case .travel(let id,let to): rail = id; destination = to
                }
                let cost = initial.moveCost(rail:rail,to:destination,in:state)
                var exact = state; exact.spentEnergy = budget-cost
                XCTAssertNotNil(initial.transition(action,from:exact))
                var exceeded = exact; exceeded.spentEnergy += 1
                XCTAssertNil(initial.transition(action,from:exceeded))
                XCTAssertTrue(initial.rejection(action,in:exceeded)!.contains("总耗能"))
                checked += 1
            }
            XCTAssertEqual(checked,4)
        }
    }

    func testNavigatorFreeReturnIsOncePerStageAndUndoRestoresIt() throws {
        let initial = game(.navigator,chapter:2), won = try win(initial)
        var replay = initial, returns = 0
        for action in won.actions {
            let before = replay.state
            XCTAssertTrue(replay.perform(action))
            if before.positions != replay.state.positions,
               zip(before.positions,replay.state.positions).contains(where:{ $0 != 0 && $1 == 0 }) {
                returns += 1
                XCTAssertEqual(replay.state.spentEnergy-before.spentEnergy,returns == 1 ? 0 : 1)
                XCTAssertTrue(replay.state.freeReturnUsed)
                XCTAssertEqual(StarRail.Game(archive:replay.archive),replay)
                XCTAssertTrue(replay.undo()); XCTAssertEqual(replay.state,before)
                XCTAssertTrue(replay.perform(action))
            }
        }
        XCTAssertEqual(returns,2)
    }

    func testCapacityStorageAndReturnCostDistinguishAllAbilities() {
        for ability in StarJourney.Ability.allCases {
            var charged = game(ability,chapter:2,energy:ability.energyLimit)
            for id in 0...2 { XCTAssertTrue(charged.perform(.pick(id))) }
            XCTAssertEqual(charged.state.energy,ability.energyLimit)
            XCTAssertEqual(charged.state.overflowEnergy,1)
            XCTAssertEqual(charged.moveCost(rail:0,to:0,in:charged.state),ability == .buffer ? 2 : ability == .navigator ? 0 : 1)
            XCTAssertEqual(charged.stage.capacity,ability == .buffer ? 8 : ability == .navigator ? 7 : 6)
        }
    }

    func testStageRestartKeepsAbilityRouteAndOpeningEnergyButResetsConsumedResources() throws {
        var session = StarRail.Session(game:game(.navigator,chapter:2,route:.supply,energy:1))
        let initial = session.game
        for id in 0...2 { XCTAssertTrue(session.take(id)) }
        session.restart()
        XCTAssertEqual(session.game,initial)
        XCTAssertEqual(session.game.state.energy,1); XCTAssertFalse(session.game.state.freeReturnUsed)
        XCTAssertEqual(StarRail.Game(archive:session.game.archive),session.game)
    }

    func testRunCannotAdvanceBeforeWinSkipChaptersOrChangeItsChosenRoute() throws {
        var run = StarJourney.Run(ability:.buffer)
        XCTAssertFalse(run.advance(route:.supply))
        XCTAssertTrue(run.keep(try win(run.game)))
        XCTAssertFalse(run.advance()); XCTAssertTrue(run.advance(route:.supply))
        XCTAssertFalse(run.advance(route:.signal))
        XCTAssertTrue(run.keep(try win(run.game)))
        XCTAssertFalse(run.advance(route:.signal)); XCTAssertTrue(run.advance())
        XCTAssertEqual(run.route,.supply); XCTAssertEqual(run.chapter,2)
        XCTAssertTrue(run.keep(try win(run.game))); XCTAssertFalse(run.advance())
        XCTAssertTrue(run.isValid)
    }

    func testStaleGameCannotOverwriteNextChapterOrANewRun() throws {
        var save = StarJourney.Save(); save.start(ability:.navigator)
        let first = try win(save.active!.game)
        XCTAssertTrue(save.keep(first)); XCTAssertTrue(save.advance(route:.signal))
        let next = save
        XCTAssertFalse(save.keep(first)); XCTAssertEqual(save,next)
        let obsolete = save.active!.game
        save.start(ability:.navigator); let restarted = save
        XCTAssertFalse(save.keep(obsolete)); XCTAssertFalse(save.keep(first)); XCTAssertEqual(save,restarted)
    }

    func testRepeatedSaveAcknowledgementUndoAndReplayNeverFarmStars() throws {
        var save = try completedSave(), won = save.active!.game
        let reward = try XCTUnwrap(save.pendingReward)
        XCTAssertEqual(reward.earned,10); XCTAssertEqual(reward.totalBefore,12); XCTAssertEqual(reward.totalAfter,22)
        for _ in 0..<3 { XCTAssertTrue(save.keep(won,otherStars:12)); XCTAssertEqual(save.pendingReward,reward) }
        save.acknowledgeReward(UUID()); XCTAssertEqual(save.pendingReward,reward)
        let last = won.actions.last!
        XCTAssertTrue(won.undo()); XCTAssertTrue(save.keep(won,otherStars:12))
        XCTAssertNil(save.pendingReward); XCTAssertEqual(save.totalStars,10); XCTAssertTrue(save.isValid)
        XCTAssertTrue(won.perform(last)); XCTAssertTrue(save.keep(won,otherStars:12))
        XCTAssertNil(save.pendingReward); XCTAssertEqual(save.totalStars,10)
        save.start(ability:.navigator)
        for chapter in 0...2 {
            XCTAssertTrue(save.keep(try win(save.active!.game),otherStars:12))
            if chapter < 2 { XCTAssertTrue(save.advance(route:chapter == 0 ? .signal : nil)) }
        }
        XCTAssertEqual(save.pendingReward?.earned,0); XCTAssertEqual(save.totalStars,10)
        save.acknowledgeReward(save.active!.id)
        XCTAssertTrue(save.keep(save.active!.game,otherStars:12)); XCTAssertNil(save.pendingReward)
        XCTAssertEqual(StarJourney.Save(data:try XCTUnwrap(save.encoded())),save)
    }

    func testCorruptCarryRouteAbilityAndCrossModeArchivesAreRejected() throws {
        var save = StarJourney.Save(); save.start(ability:.navigator)
        XCTAssertTrue(save.keep(try win(save.active!.game))); XCTAssertTrue(save.advance(route:.supply))
        for field in ["openingEnergy","chapter","version","ability","runID"] {
            let data = try edited(save) { json in
                var active = json["active"] as! [String:Any], current = active["current"] as! [String:Any]
                var journey = current["journey"] as! [String:Any]
                journey[field] = field == "ability" ? "buffer" : field == "runID" ? UUID().uuidString : 99
                current["journey"] = journey; active["current"] = current; json["active"] = active
            }
            XCTAssertNil(StarJourney.Save(data:data),field)
        }
        let carryMismatch = try edited(save) { json in
            var active = json["active"] as! [String:Any], current = active["current"] as! [String:Any]
            var journey = current["journey"] as! [String:Any]; journey["openingEnergy"] = 2
            current["journey"] = journey; active["current"] = current; json["active"] = active
        }
        XCTAssertNil(StarJourney.Save(data:carryMismatch),"A legal energy value must still match the previous chapter")
        var main = StarRail.Save(), trials = StarRail.TrialSave(), expeditions = StarRail.ExpeditionSave()
        XCTAssertFalse(main.keep(save.active!.game)); XCTAssertFalse(trials.keep(save.active!.game))
        XCTAssertFalse(expeditions.keep(save.active!.game))
        XCTAssertFalse(save.keep(.init(stage:StarRail.stage(1)!)))
        var archive = save.active!.game.archive; archive.revision = 2
        XCTAssertNil(StarRail.Game(archive:archive))
    }

    func testRewardTamperingAndOversizedSaveAreRejected() throws {
        let save = try completedSave()
        for field in ["earned","totalBefore","totalAfter","score"] {
            XCTAssertNil(StarJourney.Save(data:try edited(save) { json in
                var reward = json["pendingReward"] as! [String:Any]; reward[field] = -1
                json["pendingReward"] = reward
            }),field)
        }
        XCTAssertNil(StarJourney.Save(data:try edited(save) { json in
            var reward = json["pendingReward"] as! [String:Any]
            reward["totalBefore"] = Int.max; reward["totalAfter"] = Int.min
            json["pendingReward"] = reward
        }),"Corrupt extreme counters must be rejected before subtraction can overflow")
        XCTAssertNil(StarJourney.Save(data:Data(repeating:0,count:524_289)))
        XCTAssertNil(StarJourney.Save(data:Data("{}".utf8)))
        XCTAssertEqual(StarJourney.Save(data:try XCTUnwrap(StarJourney.Save().encoded())),StarJourney.Save())
    }

    func testTutorialPrefixHasASolutionForEveryAbilityAndUsesIndependentDismissal() throws {
        for ability in StarJourney.Ability.allCases {
            var started = game(ability)
            XCTAssertEqual(StarRail.LessonStep.current(game:started,previewSeen:false,dismissed:[])?.highlightedCards,[0,1,2])
            for id in 0...2 { XCTAssertTrue(started.perform(.pick(id))) }
            XCTAssertTrue(StarRail.LessonStep.current(game:started,previewSeen:false,dismissed:[])!.asksForPreview)
            XCTAssertNil(StarRail.LessonStep.current(game:started,previewSeen:false,dismissed:[.journeyAbility]))
            XCTAssertNotNil(StarRail.LessonStep.current(game:started,previewSeen:false,dismissed:[.firstOrbit]))
            _ = try win(started)
        }
    }
}
