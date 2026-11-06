import Metal
import UIKit
import XCTest
#if ARENA_RESOURCE_RUNTIME_TESTS
@testable import ArenaResourceRuntime
#else
@testable import ShiftReminder
#endif

/// Synthetic source display lists only. These checks exercise the real Metal
/// backend without shipping or depending on any third-party client assets.
@MainActor
final class ArenaLobbyTimelineTests: XCTestCase {
    func testNestedClockAdvancesUnderSingleFrameRoot() throws {
        let child = clip(2, children: [(1,0)], frames: [
            [[0,-1,0]], [[0,-1,2]], [[0,-1,1]]], fps: 3)
        let root = clip(10, children: [(2,0)], frames: [[[0,-1,-1]]])
        let scene = try fixture(objects: [shape(1),child,root])
        XCTAssertEqual(try scene.frame(time: 0).clipFrames[2], 0)
        XCTAssertEqual(try scene.frame(time: 1.0/3).clipFrames[2], 1)
        XCTAssertEqual(try scene.frame(time: 2.0/3).clipFrames[2], 2)
        XCTAssertEqual(try scene.frame(time: 1).clipFrames[2], 0)
        let renderer = try makeRenderer(scene)
        assertPixel(try renderer.snapshot(time: 0, width: 4, height: 4), [255,0,0,255])
        assertPixel(try renderer.snapshot(time: 1.0/3, width: 4, height: 4), [0,255,0,255])
        assertPixel(try renderer.snapshot(time: 2.0/3, width: 4, height: 4), [0,0,255,255])
    }

    func testSoftMaskRetainsPartialAlpha() throws {
        let root = clip(10, children: [(1,0),(38,0),(1,0),(39,0),(1,0),(40,0)],
            frames: [[[0,-1,1],[1,-1,-1],[2,-1,3],[3,-1,-1],[4,-1,0],[5,-1,-1]]])
        let scene = try fixture(objects: [shape(1),modifier(38),modifier(39),modifier(40),root])
        let frame = try scene.frame(time: 0)
        XCTAssertEqual(frame.operations.count, 2)
        guard case .masked = frame.operations[1] else { return XCTFail("Mask directives were flattened away") }
        let image = try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4)
        assertPixel(image, [128,0,127,255])
    }

    func testNestedSoftMasksMultiplyInsteadOfBecomingBinaryStencil() throws {
        let inner = clip(2, children: [(38,0),(1,0),(39,0),(1,0),(40,0)],
            frames: [[[0,-1,-1],[1,-1,3],[2,-1,-1],[3,-1,0],[4,-1,-1]]])
        let root = clip(10, children: [(1,0),(38,0),(1,0),(39,0),(2,0),(40,0)],
            frames: [[[0,-1,1],[1,-1,-1],[2,-1,3],[3,-1,-1],[4,-1,-1],[5,-1,-1]]])
        let scene = try fixture(objects: [shape(1),modifier(38),modifier(39),modifier(40),inner,root])
        assertPixel(try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4), [64,0,191,255])
    }

    func testAdditiveChildCompositesItsOverlappingPartsBeforeAdding() throws {
        let child = clip(2, children: [(1,0),(1,0)], frames: [[[0,-1,5],[1,-1,4]]])
        let root = clip(10, children: [(1,0),(2,8)], frames: [[[0,-1,2],[1,-1,-1]]])
        let scene = try fixture(objects: [shape(1),child,root])
        let renderer = try makeRenderer(scene)
        // Blue then red source-over inside the child gives premultiplied
        // [128,0,64,192]. ADD applies once to the green destination.
        assertPixel(try renderer.snapshot(time: 0, width: 4, height: 4), [128,255,64,255])
        XCTAssertGreaterThan(try XCTUnwrap(renderer.lastStatistics).renderPasses, 1)
    }

    func testScreenUsesSourceColorForDestinationRGBFactor() throws {
        let root = clip(10, children: [(1,0),(1,4)], frames: [[[0,-1,1],[1,-1,4]]])
        let scene = try fixture(objects: [shape(1),root])
        assertPixel(try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4), [128,0,255,255])
    }

    func testMultiplyPreservesPartialDestinationAndSourceCoverage() throws {
        let root = clip(10, children: [(1,0),(1,3)], frames: [[[0,-1,0],[1,-1,1]]])
        let scene = try fixture(objects: [shape(1),root],
            colors: [[0,0,255,128,0,0,0],[255,0,0,128,0,0,0]])
        // Half-red over half-blue: multiply term is zero, uncovered source
        // and destination each contribute 1/4, combined coverage is 3/4.
        assertPixel(try makeRenderer(scene).snapshot(time: 0,width:4,height:4),[64,0,64,192])
    }

    func testMultiplyCompositesGroupAndWorksOnTransparentTarget() throws {
        let child = clip(2, children: [(1,0),(1,0)], frames: [[[0,-1,0],[1,-1,1]]])
        let root = clip(10,children:[(2,3)],frames:[[[0,-1,-1]]])
        let scene = try fixture(objects:[shape(1),child,root],
            colors:[[0,0,255,128,0,0,0],[255,0,0,128,0,0,0]])
        assertPixel(try makeRenderer(scene).snapshot(time:0,width:4,height:4),[128,0,64,192])
    }

    func testTriangleStripSharedEdgeAndConstantUVDoNotDoubleAlpha() throws {
        let root = clip(10, children: [(1,0)], frames: [[[0,-1,4]]])
        let scene = try fixture(objects: [shape(1),root])
        let pixels = try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4)
        for pixel in 0..<16 { assertPixel(pixels, [128,0,0,128], pixel: pixel) }
    }

    func testParentMatrixAndColorComposeInSourceOrder() throws {
        let colors: [[Double]] = [[128,0,0,128,0,0,0],[128,255,255,128,0,64,0]]
        let child = clip(2, children: [(1,0)], frames: [[[0,-1,0]]])
        let root = clip(10, children: [(2,0)], frames: [[[0,0,1]]])
        let scene = try fixture(objects: [shape(1, extent: 2),child,root], colors: colors,
                                matrices: [[1,0,0,1,1,1]])
        let pixels = try makeRenderer(scene).snapshot(time: 0, width: 4, height: 4)
        assertPixel(pixels, [0,0,0,0])
        assertPixel(pixels, [16,16,0,64], pixel: 5)
    }

    func testUnknownBlendAndUnboundHUDRejectPlayback() throws {
        let root = clip(10, children: [(1,64)], frames: [[[0,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects: [shape(1),root]))
        let supported = clip(10, children: [(1,0)], frames: [[[0,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects: [shape(1),supported], status: "requires_layout_text_and_state_bindings"))
    }

    func testExclusionIsReprovedAcrossEveryFrameAndExactViewport() throws {
        let valid = try exclusionFixture(returnsToViewport: false)
        XCTAssertTrue(try valid.frame(time: 0).operations.isEmpty)
        XCTAssertThrowsError(try exclusionFixture(returnsToViewport: true))
        XCTAssertThrowsError(try exclusionFixture(returnsToViewport: false, viewport: [0,0,20,20]))
    }

    func testMalformedMaskAndFrameRunRejectBeforePlayback() throws {
        let maskless = clip(10, children: [(39,0),(1,0),(40,0)], frames: [[[0,-1,-1],[1,-1,0],[2,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects: [shape(1),modifier(39),modifier(40),maskless]))
        var mismatched = clip(10, children: [(1,0)], frames: [[[0,-1,-1]]])
        mismatched["frameCount"] = 2
        XCTAssertThrowsError(try fixture(objects: [shape(1),mismatched]))
    }

    func testSourceTextRequiresBindingsAndReusedInstancesHaveIndependentValues() throws {
        let text: [String: Any] = ["id":1,"commands":[],"textField":[
            "fontName":"Arial","fontSize":20,"left":0,"top":0,"right":40,"bottom":30,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        var root = clip(10, children: [(1,0),(1,0)], frames: [[[0,-1,-1],[1,-1,-1]]])
        root["children"] = [["objectID":1,"blendMode":0,"name":"coins"],
                            ["objectID":1,"blendMode":0,"name":"trophies"]]
        XCTAssertThrowsError(try fixture(objects: [text,root]))
        let scene = try fixture(objects: [text,root], interfaceState: .init(text: ["coins":"12","trophies":"34"]))
        let values = try scene.frame(time: 0).operations.compactMap { operation -> String? in
            if case .text(let text) = operation { return text.value }; return nil
        }
        XCTAssertEqual(values,["12","34"])
        scene.interfaceState = .init(text: ["coins":"99"], hidden: ["trophies"])
        XCTAssertEqual(try scene.frame(time: 0).operations.count,1)
        scene.interfaceState = .init(text: ["coins":"99"])
        XCTAssertThrowsError(try scene.frame(time: 0), "An unbound counter must not show a source placeholder")
    }

    func testInterfaceStateSelectsNamedFrameAndRejectsUnknownState() throws {
        var root = clip(10, children: [(1,0)], frames: [[[0,-1,0]],[[0,-1,1]]], fps: 1)
        root["frameLabels"] = ["up","down"]
        let scene = try fixture(objects: [shape(1),root], interfaceState: .init(frames: ["":"down"]))
        assertPixel(try makeRenderer(scene).snapshot(time: 0,width:4,height:4),[0,0,255,255])
        scene.interfaceState = .init(frames: ["":"up"])
        assertPixel(try makeRenderer(scene).snapshot(time: 1,width:4,height:4),[255,0,0,255])
        scene.interfaceState = .init(frames: ["":"missing"])
        XCTAssertThrowsError(try scene.frame(time: 0))
    }

    func testCompleteSourceControlPreservesTitleAndHitAreaAndHidesOtherMenus() throws {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        var marker = text; marker["id"] = 4
        var fields = marker["textField"] as! [String:Any]
        fields["right"] = 3; fields["bottom"] = 3; marker["textField"] = fields
        var button = clip(2, children:[(1,0),(3,0),(4,0),(3,0)],
                          frames:[[[0,-1,0],[1,-1,-1],[2,-1,-1],[3,-1,-1]],[[0,-1,1]]])
        button["children"] = [["objectID":1,"name":"art","blendMode":0],
            ["objectID":3,"name":"txt","blendMode":0],["objectID":4,"name":"hit_area","blendMode":0],
            ["objectID":3,"name":"notification","blendMode":0]]
        button["frameLabels"] = ["idle","ready"]
        var root = clip(10, children:[(2,0),(3,0)],frames:[[[0,0,-1],[1,-1,-1]]])
        root["children"] = [["objectID":2,"name":"button","blendMode":0],["objectID":3,"name":"other_menu","blendMode":0]]
        let base = try fixture(objects:[shape(1,extent:2),text,marker,button,root],
                               matrices:[[1,0,0,1,0.5,0.5]],interfaceState:.init())
        let control = try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"button",
            title:"Actual title",idleLabel:"idle",hiddenChildren:["notification"])
        XCTAssertEqual(control.hitRegion.values,[0.5,0.5,3.5,3.5])
        XCTAssertEqual(control.bounds.values,[-2,-2,6,6])
        let frame = try control.scene.frame(time:5)
        XCTAssertEqual(frame.operations.count,2)
        XCTAssertEqual(frame.operations.compactMap { if case .text(let text) = $0 { return text.value }; return nil },["Actual title"])
        XCTAssertEqual(control.scene.interfaceState?.frames["button"],"idle")
        XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"typo",
            title:"Actual title",idleLabel:"idle",hiddenChildren:[]))
        XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"button",
            title:"Actual title",idleLabel:"wrong_state",hiddenChildren:["notification"]))
        XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"button",
            title:"Actual title",idleLabel:"idle",hiddenChildren:[]), "An unbound notification must not leak source placeholders")
    }

    func testTeamControlKeepsNativeTitleWithoutUnboundOnlineOrXPPlaceholders() throws {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        let names = ["txt","hit_area","notification","count_txt","panel_player_online_ph_left",
                     "xp_multiplier","TID_TEAM_UP_TITLE"]
        let children = [(1,0)] + names.map { _ in (3,0) }
        let elements = children.indices.map { [$0,-1,$0 == 0 ? 0 : -1] }
        var button = clip(2,children:children,frames:[elements])
        button["children"] = [["objectID":1,"name":"art","blendMode":0]] +
            names.map { ["objectID":3,"name":$0,"blendMode":0] as [String:Any] }
        var root = clip(10,children:[(2,0),(3,0)],frames:[[[0,-1,-1],[1,-1,-1]]])
        root["children"] = [["objectID":2,"name":"button_navi_team","blendMode":0],
                            ["objectID":3,"name":"another_menu","blendMode":0]]
        let base = try fixture(objects:[shape(1,extent:2),text,button,root],
                               interfaceState:.init(),exportName:"mainscreen_hud_right")
        let control = try ArenaLobbySourceControl(document:base.document,role:.team,title:"组队")
        for time in [0.0,2.0,30.0] {
            let frame = try control.scene.frame(time:time)
            let titles: [String] = frame.operations.compactMap { operation in
                if case .text(let text) = operation { return text.value }; return nil
            }
            XCTAssertEqual(titles,["组队"])
            XCTAssertEqual(frame.operations.count,2)
            XCTAssertEqual(control.hitRegion.values,[0,0,2,2])
        }
    }

    func testNestedSourceActionUsesItsOwnTitleAndHitRegionWithoutRewardPlaceholders() throws {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        var button = clip(2,children:[(1,0),(3,0),(3,0)],frames:[[[0,-1,0],[1,-1,-1],[2,-1,-1]]])
        button["children"] = [["objectID":1,"name":"art","blendMode":0],
            ["objectID":3,"name":"txt","blendMode":0],["objectID":3,"name":"hit_area","blendMode":0]]
        var container = clip(4,children:[(2,0),(3,0)],frames:[[[0,0,-1],[1,-1,-1]]])
        container["children"] = [["objectID":2,"name":"action","blendMode":0],
                                  ["objectID":3,"name":"reward","blendMode":0]]
        var root = clip(10,children:[(4,0)],frames:[[[0,-1,-1]]])
        root["children"] = [["objectID":4,"name":"container","blendMode":0]]
        let base = try fixture(objects:[shape(1,extent:2),text,button,container,root],
                               matrices:[[1,0,0,1,0.5,0.5]],interfaceState:.init())
        let control = try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"container",
            title:"Play",idleLabel:nil,hiddenChildren:["reward"],titlePath:"action/txt",layoutPath:"action")
        XCTAssertEqual(control.hitRegion.values,[0.5,0.5,2.5,2.5])
        let frame = try control.scene.frame(time:5)
        XCTAssertEqual(frame.operations.count,2)
        XCTAssertEqual(frame.operations.compactMap { if case .text(let text) = $0 { return text.value }; return nil },["Play"])
        XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"container",
            title:"Play",idleLabel:nil,hiddenChildren:[],titlePath:"action/txt",layoutPath:"action"))
        XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"container",
            title:"Play",idleLabel:nil,hiddenChildren:["reward"],titlePath:"missing/txt",layoutPath:"action"))
    }

    func testIconOnlyControlsKeepSourceHitAreasWithoutInventedTextFields() throws {
        for role in [ArenaLobbySourceControl.Role.invite, .menu] {
            let base = try iconControlFixture(role: role)
            let control = try ArenaLobbySourceControl(document: base.document, role: role, title: role.title)
            XCTAssertNil(role.titlePath)
            XCTAssertEqual(control.hitRegion.values, [0,0,2,2])
            for time in [0.0,2.0,30.0] {
                let frame = try control.scene.frame(time: time)
                XCTAssertEqual(frame.operations.count, 1)
                XCTAssertTrue(frame.operations.allSatisfy { if case .text = $0 { return false }; return true })
            }
            let renderer = try makeRenderer(control.scene)
            XCTAssertTrue(try renderer.snapshot(time: 0, width: 12, height: 12).contains { $0 != 0 })
        }
    }

    func testNestedCounterRetainsAncestorTransformsAndRefreshesExactSavedBalance() throws {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"999999","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        var counter = clip(2,children:[(1,0),(3,0)],frames:[[[0,-1,0],[1,-1,-1]]])
        counter["children"] = [["objectID":1,"name":"icon","blendMode":0],
                               ["objectID":3,"name":"value_txt","blendMode":0]]
        var container = clip(4,children:[(2,0),(2,0)],frames:[[[0,0,-1],[1,-1,-1]]])
        container["children"] = [["objectID":2,"name":"coins","blendMode":0],
                                 ["objectID":2,"name":"gems","blendMode":0]]
        var root = clip(10,children:[(4,0),(3,0)],frames:[[[0,0,-1],[1,-1,-1]]])
        root["children"] = [["objectID":4,"name":"resources","blendMode":0],
                            ["objectID":3,"name":"debug_value","blendMode":0]]
        let base = try fixture(objects:[shape(1,extent:2),text,counter,container,root],
                               matrices:[[1,0,0,1,0.5,0.5]],interfaceState:.init())
        for value in [120,70,0,1250,2_000_000_000] {
            let control = try ArenaLobbySourceControl(document:base.document,export:"fixture",
                instance:"resources/coins",title:String(value),idleLabel:nil,hiddenChildren:[],titlePath:"value_txt")
            let frame = try control.scene.frame(time:30)
            XCTAssertEqual(control.hitRegion.values,[1,1,3,3])
            XCTAssertEqual(frame.operations.count,2)
            XCTAssertEqual(frame.operations.compactMap { if case .text(let t) = $0 { return t.value }; return nil },[String(value)])
            XCTAssertEqual(control.scene.interfaceState?.hidden,["resources/gems","debug_value"])
        }
        for path in ["resources/missing","resources//coins","resources/coins/", "resources"] {
            XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:path,
                title:"70",idleLabel:nil,hiddenChildren:[],titlePath:"value_txt"))
        }
    }

    func testLongCounterFitsWithoutChangingItsDigitsOrGrowingShortLabels() throws {
        let fields: [String:Any] = ["fontName":"Arial","fontSize":22,"text":"","left":0,"top":0,
            "right":69,"bottom":31,"fontColor":UInt32.max,"outlineColor":0,"styles":2,"align":18]
        let decoded = try JSONDecoder().decode([String:ArenaLobbyTimelineJSONValue].self,
                                               from:JSONSerialization.data(withJSONObject:fields))
        let style = try ArenaLobbySourceText(decoded)
        let font = try XCTUnwrap(UIFont(name:"Arial",size:22))
        for value in ["0","70","1250","2000000000"] {
            let fitted = ArenaLobbyTimelineRenderer.fittedSourceTextFont(font,value:value,style:style)
            let width = (value as NSString).size(withAttributes:[.font:fitted]).width
            XCTAssertLessThanOrEqual(width,69)
            XCTAssertLessThanOrEqual(fitted.pointSize,22)
            if value.count <= 4 { XCTAssertEqual(fitted.pointSize,22) }
        }
    }

    func testIconOnlyControlStillRejectsUnexpectedUnboundSourceText() throws {
        for role in [ArenaLobbySourceControl.Role.invite, .menu] {
            let base = try iconControlFixture(role: role, unexpectedText: true)
            XCTAssertThrowsError(try ArenaLobbySourceControl(document: base.document, role: role, title: role.title))
        }
    }

    func testPlayerCardUsesCurrentNameAndOmitsUnownedPrestige() throws {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"placeholder","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        var card = clip(2,children:[(1,0),(3,0),(3,0)],frames:[[[0,-1,0],[1,-1,-1],[2,-1,-1]]])
        card["children"] = [["objectID":1,"name":"player_image_ph","blendMode":0],
            ["objectID":3,"name":"player_name_txt","blendMode":0],["objectID":3,"name":"prestige","blendMode":0]]
        card["frameLabels"] = ["no_fame"]
        var root = clip(10,children:[(2,0)],frames:[[[0,-1,-1]]])
        root["children"] = [["objectID":2,"name":"button_player_card","blendMode":0]]
        let base = try fixture(objects:[shape(1),text,card,root],interfaceState:.init(),exportName:"mainscreen_hud_top_left")
        for name in ["玩家", "Renamed Player", "玩家名字ABCDEFGHIJKLMNOPQRSTUVWXYZ"] {
            let source = try ArenaLobbySourceControl(document:base.document,role:.profile,title:name)
            let frame = try source.scene.frame(time:30)
            XCTAssertEqual(frame.operations.count,2)
            XCTAssertEqual(frame.operations.compactMap { if case .text(let t) = $0 { return t.value }; return nil },[name])
        }
    }

    private func passControlFixture() throws -> ArenaLobbyTimelineScene {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"placeholder","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        let bar = clip(5,children:[(1,0)],frames:(0..<5).map { [[0,-1,$0]] },fps:10)
        let tier = clip(6,children:[(1,0)],frames:[[[0,-1,0]],[[0,-1,1]],[[0,-1,0]]],fps:3)
        let names = ["art","label_txt","tier_number_txt","value_txt","progress_bar","progress_bar_ready",
                     "bp_discount","icon_brawl_pass_plus","brawl_pass_reward_icon","notification","new_season_txt","tier_node"]
        let ids = [1,3,3,3,5,5,3,3,3,3,3,6]
        let normal = names.indices.filter { $0 != 5 }.map { [$0,-1,$0 == 0 ? 0 : -1] }
        let ready = names.indices.filter { $0 != 4 }.map { [$0,-1,$0 == 0 ? 1 : -1] }
        var pass = clip(2,children:ids.map { ($0,0) },frames:[normal,ready,normal])
        pass["children"] = zip(names,ids).map { ["objectID":$0.1,"name":$0.0,"blendMode":0] as [String:Any] }
        pass["frameLabels"] = ["brawl_pass_inprogress","brawl_pass_ready","brawl_pass_new_season"]
        var container = clip(4,children:[(2,0)],frames:[[[0,-1,-1]]])
        container["children"] = [["objectID":2,"name":"button_brawl_pass","blendMode":0]]
        var root = clip(10,children:[(4,0)],frames:[[[0,-1,-1]]])
        root["children"] = [["objectID":4,"name":"brawl_pass_container","blendMode":0]]
        return try fixture(objects:[shape(1),text,bar,tier,pass,container,root],interfaceState:.init(),
                               exportName:"mainscreen_hud_bottom_left")
    }

    func testPassRetainsSavedProgressAcrossIdleTimeRewardClaimAndSeasonReset() throws {
        let base = try passControlFixture()
        let instance = ArenaLobbySourceControl.Role.season.instance
        for saved in [ArenaLobbySourceControl.Season(tier:2,points:50,pointsPerTier:100,hasReward:false),
                      .init(tier:3,points:0,pointsPerTier:100,hasReward:true),
                      .init(tier:3,points:0,pointsPerTier:100,hasReward:false),
                      .init(tier:50,points:100,pointsPerTier:100,hasReward:true),
                      .init(tier:0,points:0,pointsPerTier:100,hasReward:false)] {
            let source = try ArenaLobbySourceControl(document:base.document,role:.season,title:"通行证",season:saved)
            let index = saved.points * 4 / saved.pointsPerTier
            XCTAssertEqual(source.scene.interfaceState?.frameIndices[instance + "/progress_bar"],index)
            XCTAssertEqual(source.scene.interfaceState?.frameIndices[instance + "/progress_bar_ready"],index)
            XCTAssertEqual(source.scene.interfaceState?.frames[instance],saved.hasReward ? "brawl_pass_ready" : "brawl_pass_inprogress")
            let drawing = String(describing:try source.scene.frame(time:0).operations)
            for time in [0.0,0.9,30] {
                let frame = try source.scene.frame(time:time)
                XCTAssertEqual(String(describing:frame.operations),drawing,"Idle playback must not advance the progress bar")
                XCTAssertEqual(frame.operations.compactMap { if case .text(let t) = $0 { return t.value }; return nil },
                               ["通行证",String(saved.tier),"\(saved.points)/\(saved.pointsPerTier)"])
            }
        }
        XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,role:.season,title:"通行证"))
        for saved in [ArenaLobbySourceControl.Season(tier:0,points:0,pointsPerTier:0,hasReward:false),
                      .init(tier:-1,points:0,pointsPerTier:100,hasReward:false),
                      .init(tier:1,points:101,pointsPerTier:100,hasReward:false)] {
            XCTAssertThrowsError(try ArenaLobbySourceControl(document:base.document,role:.season,title:"通行证",season:saved))
        }
    }

    func testPassTierEffectPlaysOnlyOnceAndSettlesToItsOriginalIdleFrame() throws {
        let base = try passControlFixture()
        let season = ArenaLobbySourceControl.Season(tier:3,points:25,pointsPerTier:100,hasReward:true)
        let source = try ArenaLobbySourceControl(document:base.document,role:.season,title:"通行证",
                                                 season:season,animateSeasonTier:true)
        let first = String(describing:try source.scene.frame(time:0).operations)
        let changed = String(describing:try source.scene.frame(time:0.4).operations)
        XCTAssertNotEqual(first,changed)
        for time in [1.0,2.4,60.4] {
            XCTAssertEqual(String(describing:try source.scene.frame(time:time).operations),first)
            XCTAssertTrue(try source.scene.oneShotPlaybackCompleted(at:time))
        }
        XCTAssertFalse(try source.scene.oneShotPlaybackCompleted(at:0.99))
        XCTAssertThrowsError(try source.scene.oneShotPlaybackCompleted(at: .nan))
        XCTAssertThrowsError(try source.scene.oneShotPlaybackCompleted(at: -1))
        let field = ArenaLobbySourceControl.Role.season.instance + "/tier_node"
        source.scene.interfaceState?.frameIndices[field] = 0
        XCTAssertThrowsError(try source.scene.frame(time:0),"Conflicting loop/one-shot bindings must be rejected")
        let current = ArenaLobbySourceControl.Binding(title:"通行证",season:season)
        XCTAssertFalse(current.playsTierIncrease(after:nil),"Opening the lobby is not a tier gain")
        XCTAssertFalse(current.playsTierIncrease(after:current),"Claiming a reward cannot replay a tier gain")
        XCTAssertTrue(current.playsTierIncrease(after:.init(title:"通行证",season:.init(tier:2,points:99,pointsPerTier:100,hasReward:false))))
        XCTAssertFalse(current.playsTierIncrease(after:.init(title:"通行证",season:.init(tier:50,points:100,pointsPerTier:100,hasReward:false))),"Season resets must not celebrate a tier gain")
    }

    func testSourceControlCacheTracksOnlyItsOwnSavedState() {
        let before = ArenaLobbySourceControl.Values(coins:100,trophies:10,playerName:"Before",
            season:.init(tier:2,points:99,pointsPerTier:100,hasReward:false))
        let after = ArenaLobbySourceControl.Values(coins:50,trophies:10,playerName:"After",
            season:.init(tier:3,points:0,pointsPerTier:100,hasReward:true))
        for role in ArenaLobbySourceControl.Role.allCases {
            let a = before.binding(for:role,localizedTitle:role.title)
            let b = after.binding(for:role,localizedTitle:role.title)
            if [.coins,.profile,.season].contains(role) { XCTAssertNotEqual(a,b) }
            else { XCTAssertEqual(a,b,"Unchanged controls retain their images and animation clocks") }
        }
    }

    func testAnimatedControlKeepsButtonFootprintWhileRetainingParticlesOutsideFirstFrame() throws {
        let particle = clip(2,children:[(1,0)],frames:[[[0,-1,0]],[[0,0,0]]],fps:2)
        var button = clip(4,children:[(2,0)],frames:[[[0,-1,-1]]])
        button["children"] = [["objectID":2,"name":"particle","blendMode":0]]
        var root = clip(10,children:[(4,0)],frames:[[[0,-1,-1]]])
        root["children"] = [["objectID":4,"name":"button","blendMode":0]]
        let base = try fixture(objects:[shape(1,extent:2),particle,button,root],
                               matrices:[[1,0,0,1,10,-8]],interfaceState:.init())
        let source = try ArenaLobbySourceControl(document:base.document,export:"fixture",instance:"button",
            title:"Animate",idleLabel:nil,hiddenChildren:[],titlePath:nil,includeAnimationBounds:true)
        XCTAssertEqual(source.layoutBounds.values,[-2,-2,4,4])
        XCTAssertEqual(source.bounds.values,[-2,-10,14,4])
        let moved = try source.scene.frame(time:0.5)
        XCTAssertEqual(moved.operations.count,1,"Particles beyond the first frame must not be discarded")
        XCTAssertEqual(moved.operations[0].bounds.values,[10,-8,12,-6])
        XCTAssertEqual(source.hitRegion.values,[0,0,2,2],"Particle overflow does not enlarge the button's hit area")
    }

    private func iconControlFixture(role: ArenaLobbySourceControl.Role,
                                    unexpectedText: Bool = false) throws -> ArenaLobbyTimelineScene {
        let text: [String:Any] = ["id":3,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"","left":0,"top":0,"right":2,"bottom":2,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        var names = role == .invite ? ["hit_area","panel_player_online","button_invite_ranked"]
                                    : ["hit_area","notification"]
        if unexpectedText { names.append("unexpected_title") }
        let children = [(1,0)] + names.map { _ in (3,0) }
        let elements = children.indices.map { [$0,-1,$0 == 0 ? 0 : -1] }
        var button = clip(2, children: children, frames: [elements])
        button["children"] = [["objectID":1,"name":"art","blendMode":0]] +
            names.map { ["objectID":3,"name":$0,"blendMode":0] as [String:Any] }
        if role == .invite { button["frameLabels"] = ["normal"] }
        var root = clip(10, children: [(2,0),(3,0)], frames: [[[0,-1,-1],[1,-1,-1]]])
        root["children"] = [["objectID":2,"name":role.instance,"blendMode":0],
                            ["objectID":3,"name":"another_menu","blendMode":0]]
        return try fixture(objects: [shape(1,extent:2),text,button,root],
                           interfaceState: .init(), exportName: role.export)
    }

    func testUnlabeledProgressFrameIsFrozenAndRejectsConflictingBindings() throws {
        let root = clip(10, children: [(1,0)], frames: [[[0,-1,0]],[[0,-1,1]]], fps: 1)
        let scene = try fixture(objects: [shape(1),root], interfaceState: .init(frameIndices: ["":1]))
        assertPixel(try makeRenderer(scene).snapshot(time: 0,width:4,height:4),[0,0,255,255])
        assertPixel(try makeRenderer(scene).snapshot(time: 10,width:4,height:4),[0,0,255,255])
        for index in [-1,2,Int.max] {
            scene.interfaceState = .init(frameIndices: ["":index])
            XCTAssertThrowsError(try scene.frame(time: 0))
        }
        scene.interfaceState = .init(frames: ["":""], frameIndices: ["":0])
        XCTAssertThrowsError(try scene.frame(time: 0))
        scene.interfaceState = .init(frames: ["":""])
        XCTAssertThrowsError(try scene.frame(time: 0), "An empty label is not a named state")
    }

    func testInterfaceBindingTyposAndWrongTargetTypesFailBeforeDrawing() throws {
        let root = clip(10, children: [(1,0)], frames: [[[0,-1,0]],[[0,-1,1]]], fps: 1)
        let scene = try fixture(objects: [shape(1),root], interfaceState: .init())
        XCTAssertNoThrow(try scene.frame(time: 0))
        for state in [ArenaLobbyInterfaceState(text: ["#0:":"wrong target"]),
                      .init(frameIndices: ["#0:":0]), .init(frameIndices: ["typo":0]),
                      .init(hidden: ["typo"])] {
            scene.interfaceState = state
            XCTAssertThrowsError(try scene.frame(time: 0))
        }
        scene.interfaceState = .init(frameIndices: ["":1])
        XCTAssertNoThrow(try scene.frame(time: 0), "Corrected state must recover after an invalid binding")
    }

    func testUnsupportedBlendRequiresExplicitHiddenInstanceAndFailsWhenEnabled() throws {
        let root = clip(10, children:[(1,64)],frames:[[[0,-1,-1]]])
        XCTAssertThrowsError(try fixture(objects:[shape(1),root],interfaceState:.init()))
        let scene = try fixture(objects:[shape(1),root],interfaceState:.init(hidden:["#0:"]))
        XCTAssertTrue(try scene.frame(time:0).operations.isEmpty)
        scene.interfaceState = .init()
        XCTAssertThrowsError(try scene.frame(time:0), "Showing an unsupported layer must never fall back to normal blending")
        scene.interfaceState = nil
        XCTAssertThrowsError(try scene.frame(time:0))
        scene.interfaceState = .init(hidden:["#0:"])
        XCTAssertTrue(try scene.frame(time:100).operations.isEmpty)
    }

    func testHiddenAncestorCoversOnlyItsOwnReusedUnsupportedDescendants() throws {
        let child = clip(2, children:[(1,64)],frames:[[[0,-1,-1]]])
        var root = clip(10, children:[(2,0),(2,0)],frames:[[[0,-1,-1],[1,-1,-1]]])
        root["children"] = [["objectID":2,"blendMode":0,"name":"player"],
                            ["objectID":2,"blendMode":0,"name":"player_two"]]
        XCTAssertThrowsError(try fixture(objects:[shape(1),child,root],interfaceState:.init(hidden:["player"])))
        let scene = try fixture(objects:[shape(1),child,root],interfaceState:.init(hidden:["player","player_two"]))
        XCTAssertTrue(try scene.frame(time:0).operations.isEmpty)
    }

    func testEmptySourceLayoutMarkersProvideTransformedRegionsWithoutGlyphs() throws {
        let marker: [String:Any] = ["id":1,"commands":[],"textField":[
            "fontName":"Arial","fontSize":15,"text":"","left":1,"top":2,"right":4,"bottom":6,
            "fontColor":UInt32.max,"outlineColor":0,"styles":0,"align":0]]
        var root = clip(10, children:[(1,0)],frames:[[[0,0,-1]]])
        root["children"] = [["objectID":1,"blendMode":0,"name":"hit_area"]]
        let scene = try fixture(objects:[marker,root], matrices:[[2,0,0,3,10,20]], interfaceState:.init())
        let frame = try scene.frame(time:0)
        XCTAssertTrue(frame.operations.isEmpty)
        XCTAssertEqual(frame.layoutRegions["hit_area"]?.values,[12,26,18,38])
        scene.interfaceState = .init(hidden:["hit_area"])
        XCTAssertTrue(try scene.frame(time:0).layoutRegions.isEmpty)
        scene.interfaceState = .init(text:["hit_area":"accidental label"])
        XCTAssertThrowsError(try scene.frame(time:0))
    }

    func testReusedProgressClipsCanSelectDifferentFramesIndependently() throws {
        let child = clip(2, children: [(1,0)], frames: [[[0,-1,0]],[[0,-1,1]]], fps: 1)
        var root = clip(10, children: [(2,0),(2,0)], frames: [[[0,-1,-1],[1,-1,-1]]])
        root["children"] = [["objectID":2,"blendMode":0,"name":"coins"],
                            ["objectID":2,"blendMode":0,"name":"trophies"]]
        let scene = try fixture(objects: [shape(1),child,root],
            interfaceState: .init(frameIndices: ["coins":0,"trophies":1]))
        for time in [0.0,1.0,10.0] {
            let colors = try scene.frame(time: time).operations.compactMap { operation -> SIMD4<Float>? in
                if case .draw(let draw) = operation { return draw.vertices.first?.multiply }; return nil
            }
            XCTAssertEqual(colors,[SIMD4<Float>(1,0,0,1), SIMD4<Float>(0,0,1,1)])
        }
        scene.interfaceState = .init(frameIndices: ["":0])
        // Freezing a container must not stop its independent child clocks.
        assertPixel(try makeRenderer(scene).snapshot(time: 1,width:4,height:4),[0,0,255,255])
    }

    func testSourceTextRendersThroughMetalAndRespondsToDataChanges() throws {
        let text: [String: Any] = ["id":1,"commands":[],"textField":[
            "fontName":"Arial","fontSize":30,"left":0,"top":0,"right":80,"bottom":40,
            "fontColor":UInt32.max,"outlineColor":0,"styles":1,"align":0]]
        let root = clip(10,children:[(1,0)],frames:[[[0,-1,-1]]])
        let scene = try fixture(objects:[text,root],viewport:[0,0,80,40],
            interfaceState:.init(text:["#0:":"12"]))
        let renderer = try makeRenderer(scene)
        let first = try renderer.snapshot(time:0,width:80,height:40)
        XCTAssertGreaterThan(first.filter { $0 > 0 }.count, 100)
        scene.interfaceState = .init(text:["#0:":"99"])
        let second = try renderer.snapshot(time:0,width:80,height:40)
        XCTAssertNotEqual(first,second)
        scene.interfaceState = .init(text:["#0:":""])
        XCTAssertTrue(try renderer.snapshot(time:0,width:80,height:40).allSatisfy { $0 == 0 })
    }

    func testClockBoundariesAndAspectFillKeepCorrectCrop() {
        XCTAssertEqual(ArenaLobbyTimelineScene.frameIndex(time: 600.0/60, fps: 60, count: 600), 0)
        XCTAssertEqual(ArenaLobbyTimelineScene.frameIndex(time: 600.0/60, fps: 60, count: 703), 600)
        let rect = ArenaLobbyTimelineRenderer.aspectFillRect(.init([-512,-288,512,288]), width: 100, height: 100)
        XCTAssertEqual(rect.values, [-288,-288,288,288])
    }

    func testIntermediateBudgetUsesLowerDensityBeforeAllocatingOversizedLayers() throws {
        let rect = ArenaLobbyTimelineScene.Rect([0,0,1600,900])
        let layers = (0..<3).map { _ in ArenaLobbyTimelineScene.Operation.layer([],blendMode:3,bounds:rect) }
        XCTAssertEqual(ArenaLobbyTimelineScene.intermediatePixels(operations:layers,sourceRect:rect,density:2),17_356_800)
        XCTAssertEqual(try ArenaLobbyTimelineScene.intermediateDensity(operations:layers,sourceRect:rect,requested:2),1.5)
        XCTAssertEqual(try ArenaLobbyTimelineScene.intermediateDensity(operations:layers,sourceRect:rect,requested:1.25),1.25)
        // Even full-resolution intermediates have a hard limit: never drop
        // source groups or exceed the cap just to make the frame render.
        let oversized = Array(repeating:layers[0],count:12)
        XCTAssertThrowsError(try ArenaLobbyTimelineScene.intermediateDensity(operations:oversized,sourceRect:rect,requested:2))
        XCTAssertThrowsError(try ArenaLobbyTimelineScene.intermediateDensity(operations:layers,sourceRect:rect,requested:.nan))
        let wide = ArenaLobbyTimelineScene.Rect([0,0,5000,1])
        let wideLayer = [ArenaLobbyTimelineScene.Operation.layer([],blendMode:3,bounds:wide)]
        XCTAssertEqual(try ArenaLobbyTimelineScene.intermediateDensity(operations:wideLayer,sourceRect:wide,requested:2),1.5,
                       "A low pixel count must not bypass the Metal texture dimension limit")
    }

    func testIntermediateBudgetMatchesMetalForNestedMaskAndMultiply() throws {
        let inner = clip(2,children:[(38,0),(1,0),(39,0),(1,0),(40,0)],
            frames:[[[0,-1,-1],[1,-1,3],[2,-1,-1],[3,-1,0],[4,-1,-1]]])
        let root = clip(10,children:[(38,0),(1,0),(39,0),(2,3),(40,0)],
            frames:[[[0,-1,-1],[1,-1,3],[2,-1,-1],[3,-1,-1],[4,-1,-1]]])
        let scene = try fixture(objects:[shape(1),modifier(38),modifier(39),modifier(40),inner,root])
        let renderer = try makeRenderer(scene)
        _ = try renderer.snapshot(time:0,width:4,height:4)
        let predicted = ArenaLobbyTimelineScene.intermediatePixels(operations:try scene.frame(time:0).operations,
                                                                  sourceRect:scene.sourceRect,density:1)
        XCTAssertEqual(try XCTUnwrap(renderer.lastStatistics).transientPixels,predicted)
    }

    private func makeRenderer(_ scene: ArenaLobbyTimelineScene) throws -> ArenaLobbyTimelineRenderer {
        guard let device = MTLCreateSystemDefaultDevice() else { throw XCTSkip("Metal device unavailable in this test environment") }
        return try ArenaLobbyTimelineRenderer(device: device, scene: scene,
            atlases: [.init(width: 1, height: 1, rgba: [255,255,255,255])])
    }

    private func shape(_ id: Int, extent: Double = 4) -> [String: Any] {
        ["id": id, "commands": [["textureIndex": 0, "vertices":
            [[0.0,0,0,0],[extent,0,0,0],[0,extent,0,0],[extent,extent,0,0]]]]]
    }
    private func modifier(_ id: Int) -> [String: Any] { ["id":id,"commands":[],"modifier":id] }
    private func clip(_ id: Int, children: [(Int,Int)], frames: [[[Int]]], fps: Double = 60) -> [String: Any] {
        ["id":id,"commands":[],"fps":fps,"frameCount":frames.count,
         "frameLabels":Array(repeating:"",count:frames.count),
         "children":children.map { ["objectID":$0.0,"blendMode":$0.1,"name":""] as [String:Any] },
         "frames":frames.map { ["repeat":1,"elements":$0] as [String:Any] }]
    }

    private func fixture(objects: [[String: Any]], colors: [[Double]]? = nil,
                         matrices: [[Double]] = [], status: String = "ready",
                         exclusions: [[String:Any]] = [], viewport: [Double]? = nil,
                         interfaceState: ArenaLobbyInterfaceState? = nil,
                         exportName: String = "fixture") throws -> ArenaLobbyTimelineScene {
        let palette = colors ?? [[255,0,0,255,0,0,0],[0,0,255,255,0,0,0],
                                 [0,255,0,255,0,0,0],[255,255,255,128,0,0,0],
                                 [255,0,0,128,0,0,0],[0,0,255,128,0,0,0]]
        let nodes = Dictionary(uniqueKeysWithValues: objects.map { (String($0["id"] as! Int),$0) })
        let value: [String: Any] = ["schemaVersion":1,"sourceSCMember":"synthetic.sc",
            "sourceSCSHA256":String(repeating:"0",count:64),"canvasSize":[4,4],"sourceRect":[0,0,4,4],
            "uvDivisor":65535,"primitiveMode":"triangle_strip","clockPolicy":"independent_absolute_clip_fps",
            "textures":[["file":"fixture.png","width":1,"height":1,"alphaEncoding":"straight",
                         "sha256":String(repeating:"0",count:64)]],
            "objects":nodes,"matrices":matrices,"colors":palette,
            "exports":[exportName:["objectID":10,"status":status]],"exclusions":exclusions]
        let document = try JSONDecoder().decode(ArenaLobbyTimelineDocument.self,
            from: JSONSerialization.data(withJSONObject:value))
        return try ArenaLobbyTimelineScene(document: document, exportName: exportName, sourceRect: viewport,
            interfaceState: interfaceState)
    }

    private func exclusionFixture(returnsToViewport: Bool, viewport: [Double]? = nil) throws -> ArenaLobbyTimelineScene {
        let child = clip(2, children: [(1,0)], frames: [[[0,0,-1]],[[0,1,-1]]])
        var root = clip(10, children: [(2,64)], frames: [[[0,-1,-1]]])
        root["children"] = [["objectID":2,"blendMode":64,"name":"","excludedByProof":"outside"]]
        let proof: [String: Any] = ["id":"outside","kind":"complete_timeline_outside_viewport",
            "exportName":"fixture","sourceSCSHA256":String(repeating:"0",count:64),
            "parentObjectID":10,"childIndex":0,"objectID":2,"blendMode":64,
            "sourceRect":[0,0,4,4],"margin":2,"fps":60,"periodFrames":2]
        return try fixture(objects: [shape(1),child,root],
            matrices: [[1,0,0,1,10,0],[1,0,0,1,returnsToViewport ? 0 : 12,0]],
            exclusions: [proof], viewport: viewport)
    }

    private func assertPixel(_ actual: [UInt8], _ expected: [Int], pixel: Int = 0,
                             file: StaticString = #filePath, line: UInt = #line) {
        for component in 0..<4 {
            XCTAssertLessThanOrEqual(abs(Int(actual[pixel*4+component])-expected[component]), 2,
                                    file: file, line: line)
        }
    }
}
