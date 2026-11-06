import XCTest
@testable import ShiftCore

final class StarRailExpansionTests: XCTestCase {
    private func expedition(_ id: Int = 1) -> StarRail.Game { .init(stage: StarRail.Expedition(id: id)!.stage) }
    private func solved(_ original: StarRail.Game, rail: Int = 0, branch: Int? = nil,
                        file: StaticString = #filePath, line: UInt = #line) throws -> StarRail.Game {
        guard case .solved(let actions, _) = StarRailSolver.solve(original, nodeLimit: 5_000,
            maxShifts: original.stage.plannedMoves, maxPeak: original.stage.targetPeak,
            firstDeparture: branch, firstDepartureRail: rail) else {
            XCTFail("No three-star route for \(original.stage.id), rail \(rail), branch \(String(describing: branch))", file: file, line: line)
            throw NSError(domain: "StarRailTests", code: 1)
        }
        var game = original
        for action in actions { XCTAssertTrue(game.perform(action), file: file, line: line) }
        return game
    }

    func testPublishedXP1PairingAndGeometryFingerprintStaysFrozen() {
        let expected: [UInt64] = [
            14155741003057281358, 10802505521461915461, 3096785132057125470, 5310269600966750449,
            7358516495574629528, 16821808188699244637, 6126110787016909749, 11346654391691805724,
            11724695760068900499, 2872350467625787147, 11985667538221169476, 6716098035786138477,
            13938990929384551488, 2018164576020820287, 5782356297420586978, 17684261712134646419,
            4004768615103313006, 4769937175139269355, 9586219921500964889, 3598841470677288483,
            2204008442092391650, 5431469116160979647, 3865227608358252172, 8510977749093879145,
            704508641503451525, 10312055615100072504, 15337130660676553843, 13767097201419005942,
            4094943525502513827, 14756104232081444513, 129418495953127619, 1840637139780118760,
            2449237229533031257, 16968304333462234910, 15322404279301319647, 16147165058853466926
        ]
        let actual = StarRail.Expedition.all.map { route -> UInt64 in
            let stage = route.stage
            let cards = stage.cards.map { "\($0.kind),\($0.x),\($0.y),\($0.z),\($0.rail ?? -1)" }.joined(separator:";")
            let rails = stage.rails.map { $0.stops.map { "\($0.x),\($0.y)" }.joined(separator:";") }.joined(separator:"|")
            let text = "\(stage.id)|\(stage.revision)|\(stage.requiredArrivals)|\(stage.plannedMoves)|\(stage.targetPeak)|\(cards)|\(rails)"
            return text.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        }
        XCTAssertEqual(actual,expected,"XP1 codes must keep exactly the same board; new catalogs need a new version")
    }

    func testEveryForkEndpointHasAThreeStarReplayWithConservedCardsAndNoCollisions() throws {
        var paths = 0
        for route in StarRail.Expedition.all {
            for rail in route.stage.rails where rail.stopCount == 3 {
                for branch in 1...2 {
                    let game = try solved(expedition(route.id), rail: rail.id, branch: branch)
                    XCTAssertEqual(game.status, .won); XCTAssertEqual(game.stars, 3)
                    XCTAssertEqual(game.actions.first { if case .travel(let id, let to) = $0 { return id == rail.id && to > 0 }; return false }, .travel(rail: rail.id, to: branch))
                    for state in game.replayStates {
                        XCTAssertEqual(state.remaining.nonzeroBitCount + state.tray.count + state.matches*3, game.stage.cards.count)
                        XCTAssertTrue((0...2).contains(state.energy))
                        let board = game.board(in: state)
                        for a in board { for b in board where a.id < b.id && a.z == b.z { XCTAssertFalse(game.overlaps(a,b,in:state)) } }
                    }
                    XCTAssertEqual(StarRail.Game(archive: game.archive), game)
                    paths += 1
                }
            }
        }
        XCTAssertEqual(paths, 84)
    }

    func testSixDistinctStructuresAndThirtySixDifferentPairingPartitionsAreBounded() {
        var geometry = Set<String>(), partitions = Set<String>()
        for route in StarRail.Expedition.all {
            let game = expedition(route.id), stage = game.stage
            geometry.insert(stage.cards.map { "\($0.x),\($0.y),\($0.z),\($0.rail ?? -1)" }.joined(separator: ";"))
            // Canonical group IDs catch mere renaming of card symbols.
            var labels: [Int:Int] = [:]
            let partition = stage.cards.map { card -> String in
                if labels[card.kind] == nil { labels[card.kind] = labels.count }
                return String(labels[card.kind]!)
            }.joined(separator: ",")
            partitions.insert("\(route.template):\(partition)")
            XCTAssertTrue(Dictionary(grouping: stage.cards, by: \.kind).values.allSatisfy { $0.count == 3 })
            XCTAssertEqual(stage.cards.prefix(3).map(\.kind), [0,0,0])
            let poses = stage.rails.reduce(1) { $0 * $1.stopCount }
            var keys = Set<Int>()
            for pose in 0..<poses {
                var state = game.state, stride = 1
                for rail in stage.rails { state.positions[rail.id] = (pose/stride)%rail.stopCount; stride *= rail.stopCount }
                keys.insert(stage.poseIndex(state.positions))
                for card in stage.cards {
                    let p = game.point(card,in:state)
                    XCTAssertGreaterThanOrEqual(p.x,0); XCTAssertGreaterThanOrEqual(p.y,0)
                    XCTAssertLessThanOrEqual(p.x+4,stage.width); XCTAssertLessThanOrEqual(p.y+4,stage.height)
                }
            }
            XCTAssertEqual(keys.count, poses)
        }
        XCTAssertEqual(geometry.count,6); XCTAssertEqual(partitions.count,36)
        XCTAssertEqual(StarRail.catalogRevision,2)
        XCTAssertEqual(StarRail.stages.map(\.id),Array(1...6))
    }

    func testFarBranchCostsTwoAndRequiresReturnBeforeSwitchingBranches() throws {
        let game = expedition()
        var charged = game.state; charged.energy = 1
        XCTAssertNotNil(game.transition(.travel(rail:0,to:1),from:charged))
        XCTAssertNil(game.transition(.travel(rail:0,to:2),from:charged))
        XCTAssertNil(game.transition(.shift(0),from:charged))
        charged.energy = 2
        let preview = try XCTUnwrap(game.preview(0,to:2,in:charged))
        let far = try XCTUnwrap(game.transition(.travel(rail:0,to:2),from:charged))
        XCTAssertEqual(preview.proposed,far); XCTAssertTrue(preview.canMove)
        XCTAssertEqual(far.energy,0); XCTAssertEqual(far.spentEnergy,2)
        XCTAssertEqual(far.arrivals,game.stage.arrivalBit(rail:0,stop:2))
        var recharged = far; recharged.energy = 2
        XCTAssertNil(game.transition(.travel(rail:0,to:1),from:recharged))
        let home = try XCTUnwrap(game.transition(.travel(rail:0,to:0),from:recharged))
        XCTAssertEqual(home.energy,1); XCTAssertEqual(home.spentEnergy,3)
        XCTAssertEqual(home.positions,[0]); XCTAssertEqual(home.arrivals & game.stage.requiredArrivals,game.stage.requiredArrivals)
    }

    func testRoutePreviewShowsDistinctCoverageAndRejectsInvalidDestinations() throws {
        let game = expedition()
        var charged = game.state; charged.energy = 2
        let near = try XCTUnwrap(game.preview(0,to:1,in:charged)), far = try XCTUnwrap(game.preview(0,to:2,in:charged))
        XCTAssertNotEqual(near.covered,far.covered)
        for stop in [-1,0,3,Int.max] { XCTAssertNil(game.preview(0,to:stop,in:charged)); XCTAssertNil(game.transition(.travel(rail:0,to:stop),from:charged)) }
        XCTAssertNil(game.transition(.travel(rail:99,to:1),from:charged))
        XCTAssertNil(game.preview(99,to:1,in:charged))
        XCTAssertEqual(game.actions,[]); XCTAssertEqual(game.state.energy,0)
    }

    func testMixedArrivalBitsAndCollisionRulesProtectBothForks() {
        let game = expedition(31)
        XCTAssertEqual(game.stage.requiredArrivals,9)
        XCTAssertEqual(game.stage.goalMask(rail:0),1); XCTAssertEqual(game.stage.goalMask(rail:1),8)
        var state = game.state; state.energy = 2
        XCTAssertNil(game.transition(.travel(rail:1,to:1),from:state), "B near initially collides with A")
        let far = game.transition(.travel(rail:1,to:2),from:state)
        XCTAssertNotNil(far)
        XCTAssertEqual(far?.arrivals,32)
    }

    func testRapidPicksDoNotWaitForAnimationButRailMoveStillLocksInput() throws {
        var session = StarRail.Session(game: expedition())
        for id in 0...2 { XCTAssertTrue(session.take(id)); XCTAssertNil(session.pending) }
        XCTAssertEqual(session.game.state.matches,1); XCTAssertEqual(session.game.state.energy,1)
        XCTAssertFalse(session.take(2)); XCTAssertEqual(session.game.actions.count,3)
        let token = try XCTUnwrap(session.submit(.travel(rail:0,to:1)))
        XCTAssertFalse(session.take(3)); XCTAssertFalse(session.undo())
        session.finish(UUID()); XCTAssertFalse(session.canInteract)
        session.finish(token); XCTAssertTrue(session.canInteract)
        session.setActive(false); XCTAssertFalse(session.take(3))
        session.setActive(true); session.restart(); session.finish(token)
        XCTAssertEqual(session.game.stage.expeditionID,1); XCTAssertTrue(session.game.actions.isEmpty)
    }

    func testReplayRestoreReturnsExactStateAndCountsEveryRewoundStep() throws {
        let won = try solved(expedition())
        var session = StarRail.Session(game: won)
        XCTAssertFalse(session.rewind(to: -1)); XCTAssertFalse(session.rewind(to: won.actions.count))
        let index = won.actions.count/2
        XCTAssertTrue(session.rewind(to:index))
        XCTAssertEqual(session.game.state,won.replayStates[index])
        XCTAssertEqual(session.game.actions,Array(won.actions.prefix(index)))
        XCTAssertEqual(session.game.rewinds,won.actions.count-index)
        XCTAssertEqual(StarRail.Game(archive:session.game.archive),session.game)
        for action in won.actions.dropFirst(index) { XCTAssertTrue(session.game.rejection(action,in:session.game.state) == nil); if case .pick(let id)=action { XCTAssertTrue(session.take(id)) } else { let token=try XCTUnwrap(session.submit(action)); session.finish(token) } }
        XCTAssertEqual(session.game.status,.won); XCTAssertEqual(session.game.state,won.state)
    }

    func testReviewMomentsIdentifyObservedPressureAndPointBeforeTheAction() {
        let stage = StarRail.Stage(id:99,title:"review",lesson:"",objective:"",tip:"",
            cards:(0..<7).map { .init(id:$0,kind:$0,x:$0*4,y:0,z:0,rail:nil) },rails:[],requiredArrivals:0,plannedMoves:0,targetPeak:5)
        var game = StarRail.Game(stage:stage)
        for id in 0..<7 { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertEqual(game.reviewMoments.map(\.id),[6,7])
        XCTAssertEqual(game.reviewMoments.map(\.restoreIndex),[5,6])
        XCTAssertEqual(game.replayStates[game.reviewMoments.last!.restoreIndex].tray.count,6)
        XCTAssertTrue(game.reviewMoments.allSatisfy { $0.title == "槽位接近上限" })
        XCTAssertTrue(game.reviewMoments.last!.detail.contains("收集槽已满，本局结束"))
        XCTAssertEqual(game.actionDescription(at:0),"取走卫星")
        XCTAssertEqual(game.actionDescription(at:-1),"初始棋盘")
    }

    func testTutorialRespondsToActualMatchPreviewMoveAndCompletion() throws {
        var game = StarRail.Game(stage:StarRail.stage(1)!)
        func step(_ seen:Bool=false) -> StarRail.LessonStep? { StarRail.LessonStep.current(game:game,previewSeen:seen,dismissed:[]) }
        XCTAssertEqual(step()?.highlightedCards,[0,1,2]); XCTAssertFalse(step()!.asksForPreview)
        for id in 0...2 { XCTAssertTrue(game.perform(.pick(id))) }
        XCTAssertTrue(step()!.asksForPreview); XCTAssertNotEqual(step()?.instruction,step(true)?.instruction)
        XCTAssertTrue(game.perform(.shift(0))); XCTAssertTrue(step()!.title.hasPrefix("3 / 3"))
        XCTAssertNil(StarRail.LessonStep.current(game:game,previewSeen:true,dismissed:[.firstOrbit]))
        game = try solved(StarRail.Game(stage:StarRail.stage(1)!))
        XCTAssertNil(step())
        var branch = expedition()
        XCTAssertNotNil(StarRail.LessonStep.current(game:branch,previewSeen:false,dismissed:[]))
        for id in 0...2 { XCTAssertTrue(branch.perform(.pick(id))) }
        XCTAssertTrue(branch.perform(.travel(rail:0,to:1)))
        XCTAssertNil(StarRail.LessonStep.current(game:branch,previewSeen:true,dismissed:[]))
    }

    func testExpeditionCodesAreVersionedBoundedAndDoNotStealClassicXPText() {
        for route in StarRail.Expedition.all { XCTAssertEqual(StarRail.Expedition.decode(route.code.lowercased()),route); XCTAssertEqual(StarRail.Expedition.decode(route.shareText),route) }
        for text in ["XP1-000","XP1-037","XP2-001","XP1-1","AXP1-001","XP1-001A","XP1-001-1","XP1-001 XP1-002","XP1-001 XP2-001",String(repeating:"x",count:8193)] {
            XCTAssertNil(StarRail.Expedition.decode(text),text)
        }
        XCTAssertFalse(StarRail.Expedition.containsCodePrefix("2-ABCXPDEF"))
        XCTAssertFalse(StarRail.Expedition.containsCodePrefix("2-AXP1-001"))
        XCTAssertTrue(StarRail.Expedition.containsCodePrefix("朋友：XP2-001"))
        XCTAssertEqual(StarRail.Expedition.decode("XP1-001 XP1-001")?.id,1)
    }

    func testDailyRotationHasThirtySixUniqueBoardsAndChangesAtBeijingMidnight() throws {
        let calendar = Calendar.dayMath
        let start = DayKey(year:2026,month:1,day:1).date(calendar:calendar)
        var ids = Set<Int>()
        for offset in 0..<36 {
            let date = try XCTUnwrap(calendar.date(byAdding:.day,value:offset,to:start))
            ids.insert(StarRail.Expedition.daily(at:date).id)
            XCTAssertEqual(StarRail.Expedition.daily(at:date),StarRail.Expedition.daily(at:date.addingTimeInterval(86_399)))
            XCTAssertNotEqual(StarRail.Expedition.daily(at:date),StarRail.Expedition.daily(at:date.addingTimeInterval(-1)))
        }
        XCTAssertEqual(ids.count,36)
        XCTAssertEqual(StarRail.Expedition.daily(at:start),StarRail.Expedition.daily(at:start.addingTimeInterval(36*86_400)))
    }

    func testExpeditionSaveKeepsBestReplayWhenRetryingAndRejectsCrossModeArchives() throws {
        let won = try solved(expedition())
        var save = StarRail.ExpeditionSave(), main = StarRail.Save(), trials = StarRail.TrialSave()
        XCTAssertTrue(save.keep(won)); XCTAssertEqual(save.totalStars,3)
        XCTAssertTrue(save.keep(expedition())); XCTAssertEqual(save.totalStars,3)
        XCTAssertEqual(save.record(for:StarRail.Expedition(id:1)!),won)
        XCTAssertEqual(StarRail.ExpeditionSave(data:try XCTUnwrap(save.encoded())),save)
        XCTAssertFalse(main.keep(won)); XCTAssertFalse(trials.keep(won))
        XCTAssertFalse(save.keep(StarRail.Game(stage:StarRail.stage(1)!)))
        var archive = won.archive
        archive.expeditionID = 2; XCTAssertNil(StarRail.Game(archive:archive))
        archive = won.archive; archive.trial = .compact; XCTAssertNil(StarRail.Game(archive:archive))
        archive = won.archive; archive.revision = 2; XCTAssertNil(StarRail.Game(archive:archive))
    }

    func testCorruptImportedSaveIsRejectedByBothDataAndDirectDecoder() throws {
        var save = StarRail.ExpeditionSave(); XCTAssertTrue(save.keep(expedition()))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(save.encoded())) as? [String:Any])
        object["version"] = 99
        let data = try JSONSerialization.data(withJSONObject:object)
        XCTAssertNil(StarRail.ExpeditionSave(data:data)); XCTAssertThrowsError(try JSONDecoder().decode(StarRail.ExpeditionSave.self,from:data))
        object["version"] = 1
        object["best"] = object["runs"] // an unplayed board is not a winning record
        XCTAssertNil(StarRail.ExpeditionSave(data:try JSONSerialization.data(withJSONObject:object)))
        var mainObject = try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(StarRail.Save().encoded())) as? [String:Any])
        mainObject["selectedStage"] = 99
        XCTAssertThrowsError(try JSONDecoder().decode(StarRail.Save.self,from:JSONSerialization.data(withJSONObject:mainObject)))
    }

    func testCosmeticsUnlockAndJournalPersistWithoutChangingRules() throws {
        var journal = StarRail.Journal()
        XCTAssertFalse(journal.select(back:.orbit,earned:5)); XCTAssertEqual(journal.back,.starlines)
        XCTAssertTrue(journal.select(back:.orbit,earned:6))
        XCTAssertFalse(journal.select(sky:.nebula,earned:29)); XCTAssertTrue(journal.select(sky:.nebula,earned:30))
        journal.dismiss(.firstFork)
        XCTAssertEqual(StarRail.Journal(data:try XCTUnwrap(journal.encoded())),journal)
        journal.resetLessons(); XCTAssertTrue(journal.dismissedLessons.isEmpty)
        XCTAssertEqual(StarRail.StarMap.restored(earned:0),0); XCTAssertEqual(StarRail.StarMap.restored(earned:72),12)
        XCTAssertEqual(StarRail.StarMap.next(earned:9),12); XCTAssertNil(StarRail.StarMap.next(earned:100))
    }

    func testStarMapCountsLegacyAndCurrentMainOnceAndCannotFarmRepeatedWins() throws {
        var progress = StarRail.Progress(), trials = StarRail.TrialSave(), expeditions = StarRail.ExpeditionSave()
        let old = try solved(StarRail.Game(stage:StarRail.stage(1,revision:1)!))
        let new = try solved(StarRail.Game(stage:StarRail.stage(1)!))
        XCTAssertTrue(progress.record(old)); XCTAssertTrue(progress.record(new))
        XCTAssertEqual(StarRail.StarMap.earned(progress:progress,trials:trials,expeditions:expeditions),3)
        let route = try solved(expedition()), trial = try solved(StarRail.Game(stage:StarRail.Trial(stageID:3,rule:.compact)!.stage))
        for _ in 0..<3 { XCTAssertTrue(expeditions.keep(route)); XCTAssertTrue(trials.keep(trial)) }
        XCTAssertEqual(StarRail.StarMap.earned(progress:progress,trials:trials,expeditions:expeditions),9)
    }

    func testOriginalAudioCuesHaveBoundedFiniteWaveformsAndQuietEndpoints() {
        var signatures = Set<[Float]>()
        for cue in StarRailAudioPCM.Cue.allCases {
            let samples = StarRailAudioPCM.samples(cue)
            XCTAssertEqual(samples.count,Int(Double(StarRailAudioPCM.sampleRate)*StarRailAudioPCM.duration(cue)))
            XCTAssertEqual(samples.first,0); XCTAssertEqual(samples.last,0)
            XCTAssertTrue(samples.allSatisfy { $0.isFinite && abs($0) <= 0.27 })
            XCTAssertGreaterThan(samples.map { $0*$0 }.reduce(0,+)/Float(samples.count),0.0001)
            signatures.insert(Array(samples.prefix(1_000)))
        }
        XCTAssertEqual(signatures.count,6)
    }
}
