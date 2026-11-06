import SwiftUI

struct StarJourneyHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StarRailStore.shared
    @State private var play: StarRailPlay?
    @State private var selectedAbility = StarJourney.Ability.capacitor
    @State private var restartPrompt = false
    @State private var offeredResume = false
    var autoResume = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let reward = store.journeys.pendingReward {
                        StarJourneyRewardView(reward:reward) { store.acknowledgeJourneyReward(reward.id) }
                    } else {
                        heading
                        if let run = store.journeys.active, !run.finished { activeRun(run) }
                        else { abilitySelection }
                        if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(TileTheme.gold) }
                        Text("每轮三关，一项能力贯穿全程。途中可保存退出；重开当前关会恢复该关的起始能量。每种能力与路线组合只累计最佳星级。")
                            .font(.caption).foregroundStyle(.white.opacity(0.55)).lineSpacing(4)
                    }
                }.padding(20).frame(maxWidth:600).frame(maxWidth:.infinity)
            }
            .background(RailSkyBackdrop(theme:store.sky).ignoresSafeArea())
            .navigationTitle("星际旅程").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("返回") { dismiss() }.accessibilityIdentifier("journey.close") } }
            .fullScreenCover(item:$play) { StarRailBoardView(game:$0.game) }
            .alert("更换能力并重开整轮？",isPresented:$restartPrompt) {
                Button("取消",role:.cancel) {}
                Button("重开整轮",role:.destructive) { if store.startJourney(selectedAbility), let run=store.journeys.active { play=StarRailPlay(game:run.game) } }
            } message: { Text("当前三关进度会重新开始，已获得的星章和最佳记录保留。") }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onAppear {
            guard !offeredResume else { return }; offeredResume=true
            if autoResume, store.journeys.pendingReward == nil, let run=store.journeys.active, !run.finished, run.game.status != .won { play=StarRailPlay(game:run.game) }
        }
    }
    private var heading: some View {
        HStack(spacing:16) {
            VStack(alignment:.leading,spacing:8) {
                Text("带着选择，\n走完一段星河。").font(.system(size:31,weight:.heavy,design:.rounded))
                Text("三关连程 · 清盘 → 护送 → 返航").font(.subheadline).foregroundStyle(TileTheme.mint)
            }
            Spacer(minLength:0); RailBrandMark(side:56)
        }
    }
    @ViewBuilder private func activeRun(_ run: StarJourney.Run) -> some View {
        let game=run.game
        JourneyChapterStrip(chapter:run.chapter,completed:run.completed.count)
        Label(run.ability.title,systemImage:abilitySymbol(run.ability)).font(.headline).foregroundStyle(TileTheme.gold)
        Text(run.ability.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
        if game.status == .won {
            Text("第 \(run.chapter+1) 关完成 · \(game.stars) 星").font(.title3.bold()).accessibilityIdentifier("journey.intermission")
            Text("剩余 \(game.state.energy) 点能量 · \(run.ability == .navigator ? "导航能力不携带关间能量" : "下一关会继承剩余能量")")
                .font(.caption).foregroundStyle(TileTheme.mint)
            if run.chapter == 0 {
                Text("选择下一段航线").font(.headline)
                ForEach(StarJourney.Route.allCases,id:\.self) { route in
                    Button { if let next=store.advanceJourney(route:route) { play=StarRailPlay(game:next) } } label: {
                        VStack(alignment:.leading,spacing:8) {
                            HStack { Text(route.title).font(.headline); Spacer(); Image(systemName:"arrow.up.right") }
                            Text(route.detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            Text("预计起始能量 \(run.nextEnergy(after:game,route:route))/\(run.ability.energyLimit)").font(.caption).foregroundStyle(TileTheme.gold)
                        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
                            .background((route == .supply ? TileTheme.mint : RailPalette.lilac).opacity(0.12),in:RoundedRectangle(cornerRadius:20))
                    }.buttonStyle(.plain).accessibilityIdentifier("journey.route.\(route.rawValue)")
                }
            } else {
                Button("进入第三关 · 限能返航") { if let next=store.advanceJourney() { play=StarRailPlay(game:next) } }
                    .buttonStyle(TilePrimaryButton()).accessibilityIdentifier("journey.next")
            }
        } else {
            Text(game.stage.objective).font(.subheadline).foregroundStyle(.white.opacity(0.75))
            Button("继续第 \(run.chapter+1) 关 · \(game.stage.title)") { play=StarRailPlay(game:game) }
                .buttonStyle(TilePrimaryButton()).accessibilityIdentifier("journey.resume")
        }
        DisclosureGroup("更换能力 / 重开整轮") { abilitySelection.padding(.top,12) }
            .tint(TileTheme.mint).font(.subheadline)
    }
    private var abilitySelection: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("选择本轮能力").font(.title3.bold())
            Text("能力带来便利，也改变限制。选定后贯穿三关。").font(.caption).foregroundStyle(.white.opacity(0.6))
            ForEach(StarJourney.Ability.allCases,id:\.self) { ability in
                Button { selectedAbility=ability } label: {
                    HStack(spacing:14) {
                        Image(systemName:abilitySymbol(ability)).font(.title2).foregroundStyle(TileTheme.gold).frame(width:30)
                        VStack(alignment:.leading,spacing:6) {
                            Text(ability.title).font(.headline)
                            Text(ability.detail).font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer(minLength:0)
                        Image(systemName:selectedAbility == ability ? "checkmark.circle.fill" : "circle").foregroundStyle(TileTheme.mint)
                    }.padding(16).background(.white.opacity(selectedAbility == ability ? 0.10 : 0.04),in:RoundedRectangle(cornerRadius:18))
                    .overlay(RoundedRectangle(cornerRadius:18).strokeBorder(selectedAbility == ability ? TileTheme.mint.opacity(0.65) : .clear))
                }.buttonStyle(.plain).accessibilityIdentifier("journey.ability.\(ability.rawValue)")
                .accessibilityAddTraits(selectedAbility == ability ? .isSelected : [])
            }
            Button("开始三关旅程") {
                if let active=store.journeys.active, !active.finished { restartPrompt=true }
                else if store.startJourney(selectedAbility), let run=store.journeys.active { play=StarRailPlay(game:run.game) }
            }.buttonStyle(TilePrimaryButton()).accessibilityIdentifier("journey.start")
            if store.journeys.best.count > 0 {
                Text("已完成 \(store.journeys.best.count)/6 种能力与航线组合 · 最佳累计 \(store.journeys.totalStars) 星章")
                    .font(.caption).foregroundStyle(TileTheme.gold)
            }
        }
    }
    private func abilitySymbol(_ ability:StarJourney.Ability) -> String {
        ability == .capacitor ? "bolt.circle.fill" : ability == .navigator ? "arrow.uturn.backward.circle.fill" : "square.stack.3d.up.fill"
    }
}

struct JourneyChapterStrip: View {
    let chapter: Int
    let completed: Int
    var body: some View {
        HStack(spacing:8) {
            ForEach(0..<3,id:\.self) { index in
                VStack(spacing:6) {
                    Image(systemName:index < completed ? "checkmark.circle.fill" : ["square.grid.3x3.fill","sparkle","arrow.uturn.backward.circle"][index])
                    Text(["清盘","护送","返航"][index]).font(.caption.bold())
                }.frame(maxWidth:.infinity).padding(.vertical,12)
                    .foregroundStyle(index <= chapter ? TileTheme.mint : .white.opacity(0.3))
                    .background(index == chapter ? TileTheme.mint.opacity(0.12) : .white.opacity(0.035),in:RoundedRectangle(cornerRadius:14))
                    .accessibilityLabel("第 \(index+1) 关，\(index < completed ? "已完成" : index == chapter ? "当前关卡" : "尚未到达")")
            }
        }
    }
}
