import SwiftUI

/// Same geometry for live play and turn-by-turn replay. The caller owns input;
/// a cosmetic animation never changes the engine's occlusion or card identity.
struct StarRailCanvas: View {
    let game: StarRail.Game
    let state: StarRail.State
    var preview: StarRail.Preview?
    var back: StarRail.CardBack = .starlines
    var highlighted: Set<Int> = []
    var canPick = false
    var onPick: (Int) -> Void = { _ in }

    var body: some View {
        GeometryReader { geo in
            let unit = max(1,min((geo.size.width-32)/CGFloat(game.stage.width),(geo.size.height-32)/CGFloat(game.stage.height)))
            let side = max(10,unit*4-7)
            let origin=CGPoint(x:(geo.size.width-unit*CGFloat(game.stage.width))/2,y:(geo.size.height-unit*CGFloat(game.stage.height))/2)
            ZStack(alignment:.topLeading) {
                RailBoardBackdrop(columns:max(1,game.stage.width/4),rows:max(1,game.stage.height/4))
                ForEach(game.stage.rails) { rail in
                    ForEach(0..<rail.stopCount,id:\.self) { stop in
                        if stop != state.positions[rail.id] && (rail.stopCount == 2 || state.positions[rail.id] == 0 || stop == 0) {
                            route(rail,stop:stop,unit:unit,side:side,origin:origin)
                        }
                    }
                }
                .accessibilityHidden(true).allowsHitTesting(false)
                ForEach(game.board(in:state)) { card in
                    let shown=preview?.proposed ?? state
                    let point=game.point(card,in:shown)
                    let free=game.blockers(of:card.id,in:shown).isEmpty
                    let anchor=game.isAnchor(card.id,in:shown)
                    Button { onPick(card.id) } label: {
                        if game.isStarCore(card.id) { RailStarCoreFace(side:side,covered:!free) }
                        else {
                            RailTileFace(kind:card.kind,side:side,covered:!free,rail:card.rail,layer:card.z,anchor:anchor,
                                highlight:highlight(card.id),back:back)
                        }
                    }
                    .buttonStyle(.plain).disabled(!canPick || preview != nil || !free || anchor || game.status(of:state) != .playing)
                    .position(x:CGFloat(point.x+2)*unit+origin.x+CGFloat(card.z)*2,y:CGFloat(point.y+2)*unit+origin.y-CGFloat(card.z)*4)
                    .zIndex(Double(card.z))
                    .transition(.scale(scale:0.8).combined(with:.opacity))
                    .accessibilityIdentifier("rails.card.\(card.id)")
                    .accessibilityLabel("\(game.isStarCore(card.id) ? "星核，需要护送，不可取走" : StarRail.names[card.kind])，第 \(card.z) 层，\(anchor ? "航线未完成，需保留" : free ? "可取" : "被盖住")")
                }
            }
        }
        .accessibilityIdentifier("rails.board")
    }
    private func highlight(_ id: Int) -> Color {
        if preview?.revealed.contains(id) == true { return TileTheme.mint }
        if preview?.covered.contains(id) == true { return .orange }
        return highlighted.contains(id) ? TileTheme.gold : .clear
    }
    private func route(_ rail: StarRail.Rail, stop: Int, unit: CGFloat, side: CGFloat, origin: CGPoint) -> some View {
        let selected = preview?.rail == rail.id && preview?.proposed.positions[rail.id] == stop
        var proposed=state; proposed.positions[rail.id]=stop
        return ForEach(game.board(in:state).filter { $0.rail == rail.id }) { card in
            let current=game.point(card,in:state),target=game.point(card,in:proposed)
            Path { path in
                path.move(to:CGPoint(x:CGFloat(current.x+2)*unit+origin.x,y:CGFloat(current.y+2)*unit+origin.y))
                path.addLine(to:CGPoint(x:CGFloat(target.x+2)*unit+origin.x,y:CGFloat(target.y+2)*unit+origin.y))
            }
            .stroke(RailPalette.rail(rail.id).opacity(selected ? 0.8 : 0.16),style:StrokeStyle(lineWidth:selected ? 2.5 : 1,dash:[3,6]))
            RoundedRectangle(cornerRadius:side*0.2)
                .fill(RailPalette.rail(rail.id).opacity(selected ? 0.10 : 0.02))
                .overlay(RoundedRectangle(cornerRadius:side*0.2).stroke(RailPalette.rail(rail.id).opacity(selected ? 0.75 : 0.22),style:StrokeStyle(lineWidth:1.3,dash:[3,4])))
                .frame(width:side,height:side)
                .position(x:CGFloat(target.x+2)*unit+origin.x,y:CGFloat(target.y+2)*unit+origin.y)
        }
    }
}

/// Cargo has a distinct silhouette and no matching symbol: it cannot strand a pair.
struct RailStarCoreFace: View {
    let side: CGFloat
    var covered = false
    var body: some View {
        VStack(spacing:1) {
            Image(systemName:"sparkles").font(.system(size:side*0.38,weight:.heavy))
            Text("星核").font(.system(size:max(7,side*0.18),weight:.black,design:.rounded))
        }
        .foregroundStyle(Color(red:1,green:0.94,blue:0.7))
        .frame(width:side,height:side)
        .background(LinearGradient(colors:[Color(red:0.66,green:0.39,blue:0.12),Color(red:0.27,green:0.17,blue:0.20)],startPoint:.topLeading,endPoint:.bottomTrailing),in:RoundedRectangle(cornerRadius:side*0.32))
        .overlay(RoundedRectangle(cornerRadius:side*0.32).strokeBorder(TileTheme.gold,lineWidth:2))
        .shadow(color:TileTheme.gold.opacity(0.3),radius:6)
        .opacity(covered ? 0.6 : 1)
    }
}
