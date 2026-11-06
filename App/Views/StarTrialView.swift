import SwiftUI

struct StarTrialPlay: Identifiable {
    let id = UUID()
    let game: StarRail.Game
}

struct StarTrialDailyCard: View {
    @ObservedObject private var store = StarRailStore.shared
    let date: Date
    var open: (StarRail.Trial) -> Void

    var body: some View {
        let trial = StarRail.Trial.daily(at: date)
        Button { open(trial) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("每日星约", systemImage: "sun.max.fill").font(.subheadline.bold())
                    Spacer()
                    Text(DayKey(date: date, calendar: .dayMath).description).font(.caption.monospacedDigit())
                }
                HStack(spacing: 14) {
                    TileGlyph(kind: trial.stageID + 2).frame(width: 50, height: 50)
                        .padding(10).background(TileTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(trial.stage.title).font(.system(.title3, design: .rounded).bold())
                        Text(trial.rule.title).font(.subheadline).foregroundStyle(TileTheme.gold)
                        Text(store.trials.record(for: trial) == nil ? "同盘同规则 · 接受今日契约" : "这条航线已通关 · 查看个人最佳")
                            .font(.caption).foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right").font(.headline)
                }
                Text("12 项契约每日轮换 · 北京时间 00:00 更新")
                    .font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white).padding(20)
            .background(LinearGradient(colors: [Color(red: 0.23, green: 0.20, blue: 0.28), RailPalette.ink],
                                        startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(TileTheme.gold.opacity(0.35)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("trials.daily")
    }
}

struct StarTrialHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var store = StarRailStore.shared
    @State private var rule = StarRail.TrialRule.compact
    @State private var play: StarTrialPlay?
    @State private var now = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("把每一手\n变成计划。").font(.system(size: 32, weight: .heavy, design: .rounded))
                            Text("完成 \(store.trials.completed)/12 · 精通 \(store.trials.mastered)/12")
                                .font(.subheadline.bold()).foregroundStyle(TileTheme.gold)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "sparkles").font(.system(size: 42)).foregroundStyle(RailPalette.lilac).padding(.top, 12)
                    }
                    Text("先用主线前两关熟悉移层，再选择一份契约。三星且全程不撤回可点亮精通星章；允许反复练习，不拼手速。")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.65)).lineSpacing(4)
                    StarTrialDailyCard(date: now, open: open)
                    Picker("契约规则", selection: $rule) {
                        ForEach(StarRail.TrialRule.allCases, id: \.self) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("trials.rules")
                    Label(rule.detail, systemImage: rule == .compact ? "square.grid.3x2" : rule == .pulse ? "bolt.fill" : "flag.checkered")
                        .font(.subheadline).foregroundStyle(RailPalette.lilac).lineSpacing(4)
                    ForEach(StarRail.Trial.all.filter { $0.rule == rule }) { trial in
                        trialButton(trial)
                    }
                    Text("本机最佳优先比较星级，再比较撤回、移层、槽位峰值和溢出能量。星约码固定棋盘与规则，可分享给朋友。")
                        .font(.footnote).foregroundStyle(.white.opacity(0.45)).lineSpacing(4)
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(RailSkyBackdrop(theme: store.sky).ignoresSafeArea())
            .navigationTitle("星约试炼").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() } }
            }
            .fullScreenCover(item: $play) { StarRailBoardView(game: $0.game) }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: scenePhase) { if $0 == .active { now = Date() } }
    }

    private func open(_ trial: StarRail.Trial) { play = StarTrialPlay(game: store.trials.game(for: trial)) }

    private func trialButton(_ trial: StarRail.Trial) -> some View {
        let best = store.trials.record(for: trial)
        let resumed = store.trials.runs[trial.id].flatMap(StarRail.Game.init(archive:))
        return Button { open(trial) } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 17).fill(RailPalette.lilac.opacity(0.12))
                    Image(systemName: best?.stars == 3 && best?.rewinds == 0 ? "star.circle.fill" : "sparkle")
                        .font(.system(size: 29)).foregroundStyle(best == nil ? RailPalette.lilac : TileTheme.gold)
                }
                .frame(width: 58, height: 64).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(trial.stage.title).font(.headline)
                    Text("\(trial.stage.capacity) 格槽 · \(trial.stage.energyLimit) 点储能" + (trial.stage.shiftLimit.map { " · \($0) 次移层" } ?? ""))
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    if let best {
                        TileStars(count: best.stars)
                        Text("本机最佳：撤回 \(best.rewinds) · 移层 \(best.state.shifts) · 峰值 \(best.state.peak)")
                            .font(.caption2).foregroundStyle(.white.opacity(0.5))
                    } else {
                        Text("尚未完成").font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                }
                Spacer(minLength: 0)
                Text(resumed?.status == .won ? "战绩" : resumed?.status == .lost ? "复盘" : resumed?.actions.isEmpty == false ? "继续" : "挑战")
                    .font(.caption.bold())
            }
            .padding(16).background(TileTheme.panel, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RailPalette.lilac.opacity(0.2)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("trials.\(trial.id)")
    }
}
