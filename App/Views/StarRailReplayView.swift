import SwiftUI

struct StarRailReplayView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let game: StarRail.Game
    let back: StarRail.CardBack
    let sky: StarRail.SkyTheme
    var restore: ((Int) -> Void)?
    @State private var index: Int
    private let states: [StarRail.State]
    private let moments: [StarRail.ReviewMoment]

    init(game: StarRail.Game, back: StarRail.CardBack = .starlines, sky: StarRail.SkyTheme = .midnight, restore: ((Int) -> Void)? = nil) {
        self.game = game; self.back = back; self.sky = sky; self.restore = restore
        states = game.replayStates; moments = game.reviewMoments
        _index = State(initialValue: game.actions.count)
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if dynamicTypeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 16) {
                            canvas.frame(height: min(geo.size.width, 450))
                            controls
                        }
                        .padding(12).frame(maxWidth: 620).frame(maxWidth: .infinity)
                    }
                } else if geo.size.width > geo.size.height * 1.3 {
                    HStack(spacing: 12) {
                        canvas
                        ScrollView { controls }.frame(width: min(330, geo.size.width * 0.45))
                    }.padding(12)
                } else {
                    VStack(spacing: 12) {
                        canvas.frame(minHeight: 160)
                        ScrollView { controls }.frame(maxHeight: geo.size.height * 0.52)
                    }.padding(12)
                }
            }
            .background(RailSkyBackdrop(theme: sky).ignoresSafeArea())
            .navigationTitle("逐手复盘").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() }.accessibilityIdentifier("replay.close") } }
        }.preferredColorScheme(.dark).foregroundStyle(.white)
    }
    private var canvas: some View {
        StarRailCanvas(game: game, state: states[index], back: back).accessibilityIdentifier("replay.board")
    }
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("第 \(index) / \(game.actions.count) 手").monospacedDigit().accessibilityIdentifier("replay.step")
                Spacer()
                Text("储能 \(states[index].energy) · 峰值 \(states[index].peak)").font(.caption).foregroundStyle(TileTheme.gold)
            }.font(.headline)
            Text(index == 0 ? "初始棋盘" : game.actionDescription(at: index - 1)).font(.subheadline).foregroundStyle(TileTheme.mint)
            StarRailTray(game: game, state: states[index]).frame(height: 38)
            HStack {
                Button { index = max(0, index - 1) } label: { Label("上一步", systemImage: "chevron.left").frame(minHeight: 44) }
                    .disabled(index == 0).accessibilityIdentifier("replay.previous")
                Spacer()
                Button { index = min(game.actions.count, index + 1) } label: { Label("下一步", systemImage: "chevron.right").frame(minHeight: 44) }
                    .disabled(index == game.actions.count).accessibilityIdentifier("replay.next")
            }.font(.subheadline.bold())
            if let restore {
                Button("从这里重试 · 撤回 \(game.actions.count - index) 手") { restore(index); dismiss() }
                    .buttonStyle(TilePrimaryButton()).disabled(index == game.actions.count)
                    .accessibilityIdentifier("replay.restore")
                Text("回到当时的棋盘、能量和收集槽；试炼与远征会累计撤回次数，已有最佳成绩保留。")
                    .font(.footnote).foregroundStyle(.white.opacity(0.72))
            }
            if !moments.isEmpty {
                Text("关键步骤").font(.subheadline.bold())
                ForEach(moments) { moment in
                    Button { index = moment.restoreIndex } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("第 \(moment.id) 手 · \(moment.title)").font(.subheadline.bold()).foregroundStyle(TileTheme.gold)
                            Text(moment.detail).font(.caption).foregroundStyle(.white.opacity(0.75))
                            Text("查看此前局面").font(.caption2).foregroundStyle(TileTheme.mint)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("replay.moment.\(moment.id)")
                }
                Text("这里记录实际发生的变化，并不表示该步一定导致无解。")
                    .font(.footnote).foregroundStyle(.white.opacity(0.72))
            }
        }.padding(.bottom, 8)
    }
}
