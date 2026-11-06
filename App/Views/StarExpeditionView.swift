import SwiftUI

struct StarExpeditionDailyCard: View {
    @ObservedObject private var store = StarRailStore.shared
    let date: Date
    var open: (StarRail.Expedition) -> Void
    var body: some View {
        let route = StarRail.Expedition.daily(at: date)
        Button { open(route) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("今日挑战 · 分岔远征", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.subheadline.bold())
                    Spacer()
                    Text(route.code).font(.caption.monospaced()).foregroundStyle(TileTheme.gold)
                }
                HStack(spacing: 14) {
                    RailBrandMark(side: 52)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(route.stage.title).font(.title3.bold())
                        Text("近岔 1 能量 · 远岔 2 能量 · 自选路线").font(.caption).foregroundStyle(.white.opacity(0.7))
                        if let best = store.expeditions.record(for: route) { TileStars(count: best.stars) }
                    }
                    Spacer(minLength: 0); Image(systemName: "arrow.up.right")
                }
                Text("36 条同盘航线轮换 · 北京时间 00:00 更新")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            .padding(18).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(TileTheme.mint.opacity(0.3)))
        }.buttonStyle(.plain).accessibilityIdentifier("expeditions.daily")
    }
}

struct StarExpeditionHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StarRailStore.shared
    @State private var play: StarRailPlay?
    @State private var replay: StarRailPlay?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 7) {
                            Text("每条岔路，\n都有下一步。").font(.system(size: 32, weight: .heavy, design: .rounded))
                            Text("\(store.expeditions.best.count)/36 航线完成 · \(store.expeditions.totalStars) 星章")
                                .font(.subheadline.bold()).foregroundStyle(TileTheme.gold)
                        }
                        Spacer(); RailBrandMark(side: 62)
                    }
                    Text("六种棋盘结构，近岔花 1 点能量，远岔花 2 点，返航花 1 点。两条分岔之间要先回起点；预览遮挡与成本，再决定先消哪一组。")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineSpacing(4)
                    Button("继续远征 · \(store.expeditions.next.code)") { open(store.expeditions.next) }
                        .buttonStyle(TilePrimaryButton()).accessibilityIdentifier("expeditions.continue")
                    ForEach(0..<6, id: \.self) { template in
                        let routes = StarRail.Expedition.all.filter { $0.template == template }
                        VStack(alignment: .leading, spacing: 12) {
                            Text(routes[0].stage.title.components(separatedBy: " · ")[0]).font(.title3.bold()).foregroundStyle(TileTheme.mint)
                            Text(routes[0].stage.lesson).font(.caption).foregroundStyle(.white.opacity(0.6))
                            ForEach(routes) { route in row(route) }
                        }.padding(.top, 6)
                    }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(RailSkyBackdrop(theme: store.sky).ignoresSafeArea())
            .navigationTitle("分岔远征").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() }.accessibilityIdentifier("expeditions.close") } }
            .fullScreenCover(item: $play) { StarRailBoardView(game: $0.game) }
            .sheet(item: $replay) { StarRailReplayView(game: $0.game, back: store.cardBack, sky: store.sky) }
        }.preferredColorScheme(.dark).foregroundStyle(.white)
    }
    private func row(_ route: StarRail.Expedition) -> some View {
        let best = store.expeditions.record(for: route)
        let resumed = !(store.expeditions.runs[route.id]?.actions.isEmpty ?? true)
        return HStack(spacing: 8) {
            Button { open(route) } label: {
                HStack(spacing: 14) {
                    Text(String(format: "%02d", route.id)).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(TileTheme.mint)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(route.code).font(.subheadline.monospaced().bold())
                        TileStars(count: best?.stars ?? 0)
                    }
                    Spacer(minLength: 4)
                    Text(resumed ? "继续" : "出发").font(.subheadline.bold())
                }.padding(14).frame(maxWidth: .infinity)
            }.buttonStyle(.plain).accessibilityIdentifier("expeditions.route.\(route.id)")
            if let best {
                Button { replay = StarRailPlay(game: best) } label: { Image(systemName: "play.rectangle").frame(width: 44, height: 48) }
                    .accessibilityLabel("回看第 \(route.id) 条最佳航线").accessibilityIdentifier("expeditions.best.\(route.id)")
            }
        }.background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
    private func open(_ route: StarRail.Expedition) { play = StarRailPlay(game: store.expeditions.game(for: route)) }
}
