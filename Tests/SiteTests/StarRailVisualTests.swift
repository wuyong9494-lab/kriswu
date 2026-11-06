import XCTest
import SwiftUI
import UIKit
@testable import ShiftReminder

final class StarRailVisualTests: XCTestCase {
    @MainActor
    func testCeramicFacesCoveredStateAndAnchorsRenderDistinctly() throws {
        var unique = Set<Data>()
        for (covered, rail, layer, anchor) in [(false, 0, 1, false), (true, 0, 1, false), (false, 1, 2, true)] {
            let view = RailTileFace(kind: 7, side: 80, covered: covered, rail: rail, layer: layer, anchor: anchor)
                .padding(18).background(RailPalette.ink)
            let renderer = ImageRenderer(content: view); renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            unique.insert(try XCTUnwrap(image.pngData()))
            let attachment = XCTAttachment(image: image)
            attachment.name = "rail-face-\(covered)-\(rail)-\(anchor)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        XCTAssertEqual(unique.count, 3)
    }

    @MainActor
    func testSmallLargeAndLandscapeBoardsAndTwoRailPreviewRender() throws {
        for (name, size, stage, preview) in [
            ("tutorial", CGSize(width: 440, height: 956), 1, Optional<Int>.none),
            ("compact", CGSize(width: 375, height: 667), 4, Optional(0)),
            ("dual", CGSize(width: 440, height: 956), 6, Optional(1)),
            ("landscape", CGSize(width: 956, height: 440), 5, Optional<Int>.none)
        ] {
            let game = StarRail.Game(stage: StarRail.stage(stage)!)
            let view = StarRailBoardView(game: game, previewRail: preview)
                .frame(width: size.width, height: size.height).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view); renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size, size)
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5_000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "star-rails-\(name)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    @MainActor
    func testStoreWritesOnlyItsOwnKeyAndCanRecoverAfterRecreation() throws {
        let suite = "star-rails-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let old = Data("classic-sentinel".utf8)
        defaults.set(old, forKey: "tileGame.records")
        defaults.set(old, forKey: "tileGame.journey.v2")
        let store = StarRailStore(defaults: defaults)
        var game = StarRail.Game(stage: StarRail.stage(1)!)
        XCTAssertTrue(game.perform(.pick(0)))
        store.keep(game)
        let recreated = StarRailStore(defaults: defaults)
        XCTAssertEqual(recreated.save.game(for: 1), game)
        XCTAssertEqual(defaults.data(forKey: "tileGame.records"), old)
        XCTAssertEqual(defaults.data(forKey: "tileGame.journey.v2"), old)
    }

    @MainActor
    func testUnreadableSaveIsPreservedBeforeReplacement() throws {
        let suite = "star-rails-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bad = Data("unreadable-save".utf8)
        defaults.set(bad, forKey: StarRail.Save.storageKey)
        let store = StarRailStore(defaults: defaults)
        XCTAssertNotNil(store.notice)
        store.keep(StarRail.Game(stage: StarRail.stage(1)!))
        XCTAssertEqual(defaults.data(forKey: StarRail.Save.storageKey + ".unreadable"), bad)
        XCTAssertNotNil(StarRail.Save(data: try XCTUnwrap(defaults.data(forKey: StarRail.Save.storageKey))))
    }

    @MainActor
    func testTrialSaveRestoresSeparatelyAndPreservesCampaignAndBestReplay() throws {
        let suite = "star-trial-tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = StarRailStore(defaults: defaults)
        var campaign = StarRail.Game(stage: StarRail.stage(1)!)
        XCTAssertTrue(campaign.perform(.pick(0))); XCTAssertTrue(store.keep(campaign))
        let campaignData = defaults.data(forKey: StarRail.Save.storageKey)
        let trial = StarRail.Trial(stageID: 3, rule: .master)!
        var game = StarRail.Game(stage: trial.stage)
        guard case .solved(let actions, _) = StarRailSolver.solve(game, maxShifts: trial.stage.plannedMoves, maxPeak: trial.stage.targetPeak) else {
            return XCTFail("Expected independent solution")
        }
        for action in actions { XCTAssertTrue(game.perform(action)) }
        XCTAssertTrue(store.keep(game)); XCTAssertEqual(store.trials.mastered, 1)
        XCTAssertTrue(game.undo()); XCTAssertTrue(store.keep(game))
        let restored = StarRailStore(defaults: defaults)
        XCTAssertEqual(restored.trials.game(for: trial), game)
        XCTAssertEqual(restored.trials.record(for: trial)?.status, .won)
        XCTAssertEqual(restored.trials.game(for: trial).rewinds, 1)
        XCTAssertEqual(defaults.data(forKey: StarRail.Save.storageKey), campaignData)
        XCTAssertEqual(restored.save.game(for: 1), campaign)
        defaults.set(Data("bad-trial-save".utf8), forKey: StarRail.TrialSave.storageKey)
        let recovered = StarRailStore(defaults: defaults)
        XCTAssertEqual(recovered.save.game(for: 1), campaign)
        XCTAssertNotNil(defaults.data(forKey: StarRail.TrialSave.storageKey + ".unreadable"))
    }

    @MainActor
    func testBrandedHomeAndContractBoardsRenderAtLargeTextAndCompactWidth() throws {
        for largeText in [false, true] {
            let home = TileGameHomeView().frame(width: 375, height: 812)
                .environment(\.dynamicTypeSize, largeText ? .accessibility2 : .large)
            let renderer = ImageRenderer(content: home); renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 5_000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "star-tile-home-largeText-\(largeText)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        for rule in StarRail.TrialRule.allCases {
            let trial = StarRail.Trial(stageID: 6, rule: rule)!
            let view = StarRailBoardView(game: .init(stage: trial.stage)).frame(width: 440, height: 956)
            let renderer = ImageRenderer(content: view); renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "star-trial-\(rule.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    @MainActor
    func testExpeditionBranchReplayAndCosmeticsRenderAcrossPhoneSizes() throws {
        let route = StarRail.Expedition(id: 31)!
        let game = StarRail.Game(stage: route.stage)
        for (name, size) in [("small", CGSize(width:375,height:667)), ("max", CGSize(width:440,height:956)), ("landscape", CGSize(width:956,height:440))] {
            let view = StarRailBoardView(game:game,previewRail:0).frame(width:size.width,height:size.height)
            let renderer=ImageRenderer(content:view);renderer.scale=1
            let image=try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size,size)
            let shot=XCTAttachment(image:image);shot.name="expedition-\(name)";shot.lifetime = .keepAlways;add(shot)
        }
        var images = Set<Data>()
        for back in StarRail.CardBack.allCases {
            let view=RailTileFace(kind:5,side:88,covered:false,rail:0,layer:1,anchor:true,back:back).padding(20).background(RailPalette.ink)
            let renderer=ImageRenderer(content:view);renderer.scale=2
            let image=try XCTUnwrap(renderer.uiImage)
            images.insert(try XCTUnwrap(image.pngData()))
            let shot=XCTAttachment(image:image);shot.name="expedition-back-\(back.rawValue)";shot.lifetime = .keepAlways;add(shot)
        }
        XCTAssertEqual(images.count,4,"Unlocked card backs must visibly change the actual face edge")
        let replay=ImageRenderer(content:StarRailReplayView(game:game).frame(width:375,height:667));replay.scale=1
        XCTAssertNotNil(replay.uiImage)
    }

    @MainActor
    func testExpeditionPersistenceCosmeticUnlockAndCorruptJournalIsolation() throws {
        let suite="star-expansion-tests.\(UUID().uuidString)"
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite));defer { defaults.removePersistentDomain(forName:suite) }
        let store=StarRailStore(defaults:defaults)
        var campaign=StarRail.Game(stage:StarRail.stage(1)!);XCTAssertTrue(campaign.perform(.pick(0)))
        XCTAssertTrue(store.keep(campaign))
        let campaignData=defaults.data(forKey:StarRail.Save.storageKey)
        for id in 1...3 {
            var game=StarRail.Game(stage:StarRail.Expedition(id:id)!.stage)
            guard case .solved(let actions,_)=StarRailSolver.solve(game,nodeLimit:5_000,maxShifts:game.stage.plannedMoves,maxPeak:game.stage.targetPeak) else { return XCTFail("Expected independent solution") }
            for action in actions { XCTAssertTrue(game.perform(action)) }
            XCTAssertTrue(store.keep(game))
        }
        XCTAssertEqual(store.earnedStars,9)
        store.select(back:.orbit);store.select(sky:.dawn)
        let restored=StarRailStore(defaults:defaults)
        XCTAssertEqual(restored.cardBack,.orbit);XCTAssertEqual(restored.sky,.dawn)
        XCTAssertEqual(restored.earnedStars,9);XCTAssertEqual(restored.expeditions.best.count,3)
        XCTAssertEqual(defaults.data(forKey:StarRail.Save.storageKey),campaignData)
        let bad=Data("corrupt-journal".utf8);defaults.set(bad,forKey:StarRail.Journal.storageKey)
        let recovered=StarRailStore(defaults:defaults)
        XCTAssertEqual(recovered.earnedStars,9);XCTAssertEqual(recovered.sky,.midnight)
        XCTAssertEqual(defaults.data(forKey:StarRail.Journal.storageKey + ".unreadable"),bad)
        XCTAssertEqual(recovered.save.game(for:1),campaign)
    }

    @MainActor
    func testDisabledOrInactiveSoundDoesNotStartAnAudioEngine() {
        let sound=StarRailSound()
        sound.configure(active:false,enabled:true);sound.play(.pick)
        XCTAssertFalse(sound.running);XCTAssertEqual(sound.loadedCueCount,0)
        sound.configure(active:true,enabled:false);sound.play(.win)
        XCTAssertFalse(sound.running);XCTAssertEqual(sound.loadedCueCount,0)
    }

}
