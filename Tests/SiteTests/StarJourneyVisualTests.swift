import XCTest
import SwiftUI
import UIKit
import AVFoundation
@testable import ShiftReminder

final class StarJourneyVisualTests: XCTestCase {
    private func win(_ initial:StarRail.Game) throws -> StarRail.Game {
        guard case .solved(let actions,_) = StarRailSolver.solveJourney(initial) else {
            throw NSError(domain:"StarJourneyVisualTests",code:1)
        }
        var game=initial
        for action in actions { XCTAssertTrue(game.perform(action)) }
        XCTAssertEqual(game.status,.won)
        return game
    }
    @MainActor
    func testJourneySaveRestoresEveryChapterRewardAndKeepsOtherModes() throws {
        let suite="star-journey-tests.\(UUID().uuidString)"
        let defaults=try XCTUnwrap(UserDefaults(suiteName:suite))
        defer { defaults.removePersistentDomain(forName:suite) }
        var store=StarRailStore(defaults:defaults)
        var legacy=StarRail.Game(stage:StarRail.stage(1)!)
        XCTAssertTrue(legacy.perform(.pick(0)));XCTAssertTrue(store.keep(legacy))
        let legacyData=defaults.data(forKey:StarRail.Save.storageKey)
        XCTAssertTrue(store.startJourney(.capacitor))
        for chapter in 0...2 {
            var game=try XCTUnwrap(store.journeys.active?.game)
            XCTAssertTrue(game.perform(.pick(0)));XCTAssertTrue(store.keep(game))
            store=StarRailStore(defaults:defaults)
            XCTAssertEqual(store.journeys.active?.game,game)
            XCTAssertTrue(store.keep(try win(game)))
            store=StarRailStore(defaults:defaults)
            XCTAssertEqual(store.journeys.active?.chapter,chapter)
            if chapter < 2 { XCTAssertNotNil(store.advanceJourney(route:chapter == 0 ? .signal : nil)) }
        }
        XCTAssertEqual(store.earnedStars,10)
        XCTAssertEqual(store.journeys.pendingReward?.earned,10)
        XCTAssertEqual(defaults.data(forKey:StarRail.Save.storageKey),legacyData)
        store.select(back:.orbit);store.select(sky:.dawn)
        let restored=StarRailStore(defaults:defaults)
        XCTAssertEqual(restored.cardBack,.orbit);XCTAssertEqual(restored.sky,.dawn)
        restored.acknowledgeJourneyReward(try XCTUnwrap(restored.journeys.pendingReward?.id))
        XCTAssertNil(StarRailStore(defaults:defaults).journeys.pendingReward)
        let bad=Data("bad-journey".utf8);defaults.set(bad,forKey:StarJourney.Save.storageKey)
        let recovered=StarRailStore(defaults:defaults)
        XCTAssertNil(recovered.journeys.active)
        XCTAssertEqual(recovered.save.game(for:1),legacy)
        XCTAssertEqual(defaults.data(forKey:StarJourney.Save.storageKey+".unreadable"),bad)
    }
    @MainActor
    func testJourneyGateCoreObjectivesAndRewardRenderAtPhoneSizes() throws {
        let runID=UUID()
        for (name,size,type) in [("compact",CGSize(width:375,height:667),DynamicTypeSize.large),
                                  ("max",CGSize(width:440,height:956),.large),
                                  ("landscape",CGSize(width:956,height:440),.large),
                                  ("large-text",CGSize(width:440,height:956),.accessibility2)] {
            for chapter in [1,2] {
                let config=StarJourney.Configuration(runID:runID,ability:.navigator,chapter:chapter,route:.signal)
                let board=StarRailBoardView(game:.init(stage:config.stage),previewRail:0)
                    .frame(width:size.width,height:size.height).environment(\.dynamicTypeSize,type)
                try attach(board,name:"journey-\(chapter)-\(name)",size:size)
            }
        }
        var save=StarJourney.Save();save.start(ability:.navigator)
        for chapter in 0...2 {
            XCTAssertTrue(save.keep(try win(save.active!.game)))
            if chapter < 2 { XCTAssertTrue(save.advance(route:chapter == 0 ? .signal : nil)) }
        }
        let reward=try XCTUnwrap(save.pendingReward)
        let view=ScrollView { StarJourneyRewardView(reward:reward,animateRestoration:false,done:{}).padding(20) }
            .background(RailSkyBackdrop(theme:.midnight)).frame(width:440,height:956)
        try attach(view,name:"journey-restoration-reward",size:CGSize(width:440,height:956))
        for stars in [0,10] {
            let map=StarConstellationMap(earned:stars).frame(width:400,height:324)
            try attach(map,name:"journey-star-map-\(stars)",size:CGSize(width:400,height:324))
        }
    }
    @MainActor
    private func attach<V:View>(_ view:V,name:String,size:CGSize) throws {
        let renderer=ImageRenderer(content:view);renderer.scale=1
        let image=try XCTUnwrap(renderer.uiImage)
        XCTAssertEqual(image.size,size)
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count,5_000)
        let shot=XCTAttachment(image:image);shot.name=name;shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor
    func testAudioEngineLoadsCuesStopsInBackgroundAndResumes() async throws {
        let sound=StarRailSound()
        defer { sound.configure(active:false,enabled:false) }
        sound.configure(active:true,enabled:true)
        XCTAssertTrue(sound.running)
        XCTAssertEqual(sound.loadedCueCount,StarRailAudioPCM.Cue.allCases.count)
        for cue in StarRailAudioPCM.Cue.allCases { sound.play(cue) }
        sound.configure(active:false,enabled:true);XCTAssertFalse(sound.running)
        sound.play(.win);XCTAssertFalse(sound.running)
        sound.configure(active:true,enabled:true);XCTAssertTrue(sound.running)
        NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:nil,
            userInfo:[AVAudioSessionInterruptionTypeKey:AVAudioSession.InterruptionType.began.rawValue])
        for _ in 0..<20 where sound.running { try await Task.sleep(nanoseconds:25_000_000) }
        XCTAssertFalse(sound.running)
        NotificationCenter.default.post(name:AVAudioSession.interruptionNotification,object:nil,
            userInfo:[AVAudioSessionInterruptionTypeKey:AVAudioSession.InterruptionType.ended.rawValue,
                      AVAudioSessionInterruptionOptionKey:AVAudioSession.InterruptionOptions.shouldResume.rawValue])
        for _ in 0..<20 where !sound.running { try await Task.sleep(nanoseconds:25_000_000) }
        XCTAssertTrue(sound.running)
        sound.configure(active:true,enabled:false);XCTAssertFalse(sound.running)
    }
}
