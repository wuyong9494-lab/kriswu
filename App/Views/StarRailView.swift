import SwiftUI
import UIKit

struct StarRailPlay: Identifiable {
    let id = UUID()
    let game: StarRail.Game
}

struct StarRailHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StarRailStore.shared
    @State private var play: StarRailPlay?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("星轨\n移层").font(.system(size: 38, weight: .heavy, design: .rounded))
                            Text("留一格，想三步。")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.7))
                            Label("\(store.save.progress.totalStars) / 18", systemImage: "star.fill")
                                .foregroundStyle(TileTheme.gold).font(.headline)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        RailHomeArtwork(back: store.cardBack)
                    }
                    Text("三消储能 · 轨道开窗 · 双轨让行")
                        .font(.subheadline.bold()).foregroundStyle(TileTheme.mint)
                    if let notice = store.notice { Text(notice).font(.footnote).foregroundStyle(TileTheme.gold) }
                    ForEach(StarRail.stages) { stage in
                        if stage.id % 2 == 1 {
                            HStack {
                                Text(RailPalette.chapter(stage.id)).font(.headline)
                                Spacer()
                                Text(stage.id <= 2 ? "学会观察" : stage.id <= 4 ? "规划下一组" : "安排往返顺序")
                                    .font(.caption).foregroundStyle(.white.opacity(0.45))
                            }
                            .padding(.top, 8)
                        }
                        stageButton(stage)
                    }
                    Text("每关先完成航线目标，再清空所有牌。三星还需控制移层次数和收集槽峰值；撤回可完整恢复上一手。旧航程、挑战码和多人竞速从星了个星首页进入。")
                        .font(.footnote).foregroundStyle(.white.opacity(0.6)).lineSpacing(4)
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(RailSkyBackdrop(theme: store.sky).ignoresSafeArea())
            .navigationTitle("星轨移层").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }.accessibilityIdentifier("rails.home.close")
                }
            }
            .fullScreenCover(item: $play) { StarRailBoardView(game: $0.game) }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }

    private func stageButton(_ stage: StarRail.Stage) -> some View {
        let unlocked = store.save.progress.unlocked(stage.id)
        let resumed = !(store.save.runs[stage.id]?.actions.isEmpty ?? true)
        return Button {
            if let game = store.save.game(for: stage.id) { play = StarRailPlay(game: game) }
        } label: {
            HStack(spacing: 14) {
                Text(String(format: "%02d", stage.id))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(TileTheme.mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text(stage.title).font(.headline)
                    Text(stage.lesson).font(.caption).foregroundStyle(.white.opacity(0.65))
                    TileStars(count: store.save.progress.stars[stage.id] ?? 0)
                    if let old = store.save.progress.legacyStars[stage.id] {
                        Text("旧版 \(old) 星已保留").font(.caption2).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Spacer(minLength: 0)
                if unlocked {
                    Text(resumed ? "继续" : "出发").font(.subheadline.bold())
                } else {
                    Image(systemName: "lock.fill")
                }
            }
            .padding(18)
            .background(LinearGradient(colors: [TileTheme.panel, RailPalette.board], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(unlocked ? TileTheme.mint.opacity(0.28) : .white.opacity(0.06)))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
            .opacity(unlocked ? 1 : 0.45)
        }
        .buttonStyle(.plain).disabled(!unlocked).accessibilityIdentifier("rails.stage.\(stage.id)")
        .accessibilityLabel("第 \(stage.id) 关，\(stage.title)，\(unlocked ? (resumed ? "继续进度" : "已解锁") : "未解锁")")
    }
}

struct StarRailBoardView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = StarRailStore.shared
    @State private var session: StarRail.Session
    @State private var selectedRail: Int?
    @State private var selectedStop: Int?
    @State private var inspection = false
    @State private var restartPrompt = false
    @State private var animationTask: Task<Void, Never>?
    @State private var trialHall = false
    @State private var replay: StarRailPlay?
    @State private var previewSeen = false
    @State private var lastFeedback: String?
    @AppStorage("tileGame.haptics") private var haptics = true
    @AppStorage("tileGame.sound") private var sounds = true

    init(game: StarRail.Game, previewRail: Int? = nil) {
        _session = State(initialValue: StarRail.Session(game: game))
        _selectedRail = State(initialValue: previewRail)
    }
    private var game: StarRail.Game { session.game }
    private var trial: StarRail.Trial? { game.stage.trial.flatMap { StarRail.Trial(stageID: game.stage.id, rule: $0) } }
    private var journeyConfig: StarJourney.Configuration? { game.stage.journey }
    private var expedition: StarRail.Expedition? { game.stage.expeditionID.flatMap(StarRail.Expedition.init(id:)) }
    private var preview: StarRail.Preview? { selectedRail.flatMap { game.preview($0, to: selectedStop, in: game.state) } }
    private var lesson: StarRail.LessonStep? {
        StarRail.LessonStep.current(game: game, previewSeen: previewSeen, dismissed: store.journal.dismissedLessons)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                if geo.size.width > geo.size.height * 1.3 {
                    HStack(spacing: 12) {
                        playArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                        VStack(spacing: 8) {
                            objective
                            if preview == nil, let lesson { lessonBanner(lesson) }
                            if game.status == .playing { railControls }
                            Spacer(minLength: 0)
                            trayAndTools
                        }
                        .frame(width: min(330, geo.size.width * 0.43))
                    }
                    .padding(10)
                } else {
                    VStack(spacing: 8) {
                        objective
                        if preview == nil, let lesson { lessonBanner(lesson) }
                        playArea.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if game.status == .playing { railControls }
                        trayAndTools
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                }
            }
            .background(RailSkyBackdrop(theme: store.sky).ignoresSafeArea())
            .navigationTitle(journeyConfig.map { "旅程 \($0.chapter+1)/3 · \($0.title)" } ?? expedition.map { "\($0.code) · \(game.stage.title)" } ?? "\(game.stage.id) · \(game.stage.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("保存返回") { stopAnimation(); if store.keep(game) { dismiss() } }
                        .accessibilityIdentifier("rails.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { clearPreview(); inspection = true } label: { Image(systemName: "square.3.layers.3d") }
                        .accessibilityLabel("查看所有叠层和规则").accessibilityIdentifier("rails.inspect")
                }
            }
            .sheet(isPresented: $inspection) { inspectionSheet }
            .sheet(item: $replay) { item in
                StarRailReplayView(game: item.game, back: store.cardBack, sky: store.sky) { index in
                    stopAnimation(); clearPreview()
                    if session.rewind(to: index) {
                        lastFeedback = "已回到第 \(index) 手，可以重新规划"; store.keep(game)
                    }
                }
            }
            .fullScreenCover(isPresented: $trialHall) { StarTrialHomeView() }
            .alert("重新开始这一关？", isPresented: $restartPrompt) {
                Button("取消", role: .cancel) {}
                Button("重开", role: .destructive) { restart() }
            } message: { Text(game.stage.revision < StarRail.catalogRevision ? "将开始新版航线，旧版星级保留。" : "本关当前棋盘会重置，已获得的星级保留。") }
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .onAppear { session.setActive(scenePhase == .active); store.keep(game); configureSound() }
        .onChange(of: sounds) { _ in configureSound() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { stopAnimation(); clearPreview(); store.keep(game) }
            session.setActive(phase == .active); configureSound()
        }
        .onChange(of: game.status) { status in if status != .playing { inspection = false } }
        .onDisappear {
            stopAnimation(); session.setActive(false); store.keep(game)
            StarRailSound.shared.configure(active: false, enabled: sounds)
        }
    }
    private var objective: some View {
        VStack(spacing: 5) {
            HStack(spacing: 8) {
                RailEnergyMeter(value: game.state.energy, limit: game.stage.energyLimit).accessibilityIdentifier("rails.energy")
                Spacer(minLength: 0)
                Text(journeyConfig?.objective == .escort ? "已配对 \(game.state.matches) 组" : "消除 \(game.state.matches * 3)/\(game.stage.cards.count)")
                Text("移层 \(game.state.shifts)/\(game.stage.plannedMoves)").foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            if journeyConfig?.objective == .escort {
                Text("开星门 → B 轨让行 → 星核送达 · 收集槽需清空")
                    .font(.system(size:10)).foregroundStyle(TileTheme.mint).frame(maxWidth:.infinity,alignment:.leading)
            } else {
                ProgressView(value: Double(game.state.matches * 3), total: Double(game.stage.cards.count)).tint(TileTheme.mint)
            }
            if let config = journeyConfig {
                HStack {
                    Text("\(config.ability.title) · \(game.stage.capacity) 格")
                    Spacer()
                    if let budget = config.energyBudget { Text("总耗能 \(game.state.spentEnergy)/\(budget)").accessibilityIdentifier("journey.budget") }
                    else if config.objective == .escort { Text("星核 → \(config.route == .supply ? "近岔" : "远岔")").accessibilityIdentifier("journey.goal") }
                }.font(.system(size:10,weight:.semibold)).foregroundStyle(TileTheme.gold)
            }
            if let trial {
                Text("\(trial.rule.title) · 本局撤回 \(game.rewinds) 次 · 零撤回三星可精通")
                    .font(.system(size: 10)).foregroundStyle(TileTheme.gold).accessibilityIdentifier("rails.rewinds")
            }
            if let notice = store.notice { Text(notice).font(.caption2).foregroundStyle(TileTheme.gold) }
        }
        .padding(.horizontal, 4)
    }
    private func lessonBanner(_ step: StarRail.LessonStep) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(step.title).font(.system(size: 12, weight: .bold)).foregroundStyle(TileTheme.gold)
                Text(step.instruction).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button { store.dismissLesson(journeyConfig?.lesson ?? (expedition == nil ? .firstOrbit : .firstFork)) } label: {
                Image(systemName: "xmark").font(.caption).frame(width: 32, height: 32)
            }
            .accessibilityLabel("跳过教学").accessibilityIdentifier("rails.lesson.skip")
        }
        .padding(8).background(TileTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("rails.lesson")
    }
    @ViewBuilder private var playArea: some View {
        if game.status == .playing {
            StarRailCanvas(game: game, state: game.state, preview: preview, back: store.cardBack,
                           highlighted: lesson?.highlightedCards ?? [], canPick: session.canInteract) { act(.pick($0)) }
        } else {
            ScrollView { resultPanel }
        }
    }
    private var railControls: some View {
        VStack(spacing: 6) {
            if let gate = game.starGate {
                HStack(spacing:6) {
                    Image(systemName:game.gateOpen(in:game.state) ? "lock.open.fill" : "lock.fill")
                    Text(game.gateOpen(in:game.state) ? "星门已开启 · A 轨可以通行" : "星门锁定 · 配对三张\(StarRail.names[gate.kind])开启")
                    Spacer(minLength:0)
                }.font(.system(size:11,weight:.semibold)).foregroundStyle(game.gateOpen(in:game.state) ? TileTheme.mint : TileTheme.gold)
                .accessibilityIdentifier("journey.gate")
            }
            HStack(spacing: 8) {
                ForEach(game.stage.rails) { rail in
                    Button {
                        if selectedRail == rail.id { clearPreview() }
                        else { selectedRail = rail.id; selectedStop = nil; previewSeen = true }
                    } label: {
                        HStack(spacing: 6) {
                            Text(rail.id == 0 ? "A" : "B").font(.system(size: 16, weight: .heavy, design: .rounded))
                            Text("\(rail.stopName(game.state.positions[rail.id])) · 预览").font(.system(size: 12, weight: .semibold))
                            Spacer(minLength: 0)
                            Image(systemName: "arrow.left.arrow.right").font(.caption)
                        }
                        .foregroundStyle(RailPalette.rail(rail.id)).padding(.horizontal, 10).frame(minHeight: 38)
                        .background(RailPalette.rail(rail.id).opacity(selectedRail == rail.id ? 0.2 : 0.08), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(lesson?.asksForPreview == true ? TileTheme.gold.opacity(0.6) : .clear))
                    }
                    .buttonStyle(.plain).disabled(!session.canInteract)
                    .accessibilityIdentifier("rails.preview.\(rail.id)")
                }
            }
            if let preview {
                destinationChoices(preview)
                HStack(spacing: 6) {
                    Text("露出 \(preview.revealed.count)").foregroundStyle(TileTheme.mint)
                    Text("盖住 \(preview.covered.count)").foregroundStyle(.orange)
                    Spacer(minLength: 0)
                    Text(preview.reason ?? "余能 \(preview.proposed.energy) · 预览不消耗")
                        .foregroundStyle(preview.canMove ? .white.opacity(0.6) : TileTheme.gold)
                        .lineLimit(2).minimumScaleFactor(0.8)
                }.font(.system(size: 11))
                if preview.canMove {
                    let ready = game.kindPlans(in: preview.proposed).filter(\.canComplete).map { StarRail.names[$0.kind] }
                    Text(ready.isEmpty ? "移层后暂无可直接完成的三张" : "可凑齐：\(ready.joined(separator: "、"))")
                        .font(.system(size: 10)).foregroundStyle(RailPalette.lilac).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Button("取消") { clearPreview() }.frame(minHeight: 40).accessibilityIdentifier("rails.preview.cancel")
                    Spacer(minLength: 0)
                    Button {
                        act(game.moveAction(rail: preview.rail, to: preview.proposed.positions[preview.rail]))
                    } label: {
                        let rail = game.stage.rails[preview.rail], stop = preview.proposed.positions[preview.rail]
                        Label("\(rail.stopName(stop)) · \(game.moveCost(rail:rail.id,to:stop,in:game.state) == 0 ? "免费" : "−\(game.moveCost(rail:rail.id,to:stop,in:game.state))")", systemImage: "bolt.fill")
                            .font(.system(size: 13, weight: .bold)).padding(.horizontal, 18).frame(minHeight: 40)
                            .foregroundStyle(RailPalette.ink).background(TileTheme.mint, in: Capsule())
                    }
                    .buttonStyle(.plain).disabled(!preview.canMove || !session.canInteract)
                    .opacity(preview.canMove && session.canInteract ? 1 : 0.35).accessibilityIdentifier("rails.move")
                }.font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(8).background(RailPalette.ink.opacity(0.8), in: RoundedRectangle(cornerRadius: 16))
    }
    @ViewBuilder private func destinationChoices(_ preview: StarRail.Preview) -> some View {
        let rail = game.stage.rails[preview.rail]
        if rail.stopCount > 2 && game.state.positions[rail.id] == 0 {
            HStack(spacing: 8) {
                ForEach(1..<rail.stopCount, id: \.self) { stop in
                    Button { selectedStop = stop } label: {
                        Text("\(rail.stopName(stop)) · \(game.moveCost(rail:rail.id,to:stop,in:game.state)) 能量")
                            .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).frame(minHeight: 32)
                            .background(preview.proposed.positions[rail.id] == stop ? RailPalette.lilac.opacity(0.35) : .white.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("rails.stop.\(rail.id).\(stop)")
                    .accessibilityAddTraits(preview.proposed.positions[rail.id] == stop ? .isSelected : [])
                }
            }
        }
    }
    private var trayAndTools: some View {
        VStack(spacing: 5) {
            HStack {
                Text(lastFeedback ?? "三张消除 · 给下一组留位置").lineLimit(1).minimumScaleFactor(0.7)
                    .accessibilityIdentifier("rails.feedback")
                Spacer(minLength: 4)
                Text("\(game.state.tray.count)/\(game.stage.capacity) 格").monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(game.state.tray.count >= game.stage.capacity - 2 ? TileTheme.gold : TileTheme.mint)
            StarRailTray(game: game, state: game.state).frame(height: 42).accessibilityIdentifier("rails.tray")
            HStack {
                Button {
                    clearPreview()
                    if session.undo() { lastFeedback = "已撤回上一手"; if haptics { Haptics.select() }; store.keep(game) }
                } label: { Label("撤回", systemImage: "arrow.uturn.backward") }
                .disabled(!session.canInteract || !game.canUndo).accessibilityIdentifier("rails.undo")
                Spacer(minLength: 6)
                Button { stopAnimation(); clearPreview(); replay = StarRailPlay(game: game) } label: {
                    Label("复盘", systemImage: "backward.end")
                }
                .disabled(game.actions.isEmpty).accessibilityIdentifier("rails.replay")
                Spacer(minLength: 6)
                Button("重开") { restartPrompt = true }.accessibilityIdentifier("rails.restart")
            }
            .font(.system(size: 13, weight: .semibold)).frame(minHeight: 38)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RailPalette.ink.opacity(0.9), in: RoundedRectangle(cornerRadius: 16))
    }
    private var resultPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            RailBrandMark(side: 48)
            Text(game.status == .won ? "航线完成" : "这条路暂时走不通").font(.title2.bold()).accessibilityIdentifier("rails.result")
            if game.status == .won {
                TileStars(count: game.stars)
                Text("移层 \(game.state.shifts) 次 · 槽位峰值 \(game.state.peak) · 撤回 \(game.rewinds) 次").font(.subheadline)
                Text("星图累计 \(store.earnedStars) 星 · 已修复 \(StarRail.StarMap.restored(earned: store.earnedStars))/12 颗星")
                    .font(.caption).foregroundStyle(TileTheme.gold)
                if let config = journeyConfig {
                    Text(config.chapter == 2 ? "三关旅程已完成，查看星图与本次奖励。" : "本关剩余 \(game.state.energy) 点能量；回到旅程选择下一段航线。")
                        .font(.subheadline).foregroundStyle(TileTheme.mint)
                    Button(config.chapter == 2 ? "查看旅程奖励" : "继续旅程") {
                        stopAnimation(); if store.keep(game) { dismiss() }
                    }.buttonStyle(TilePrimaryButton()).accessibilityIdentifier("journey.advance")
                } else if let expedition {
                    if let next = StarRail.Expedition(id: expedition.id + 1) {
                        Button("下一航线 · \(next.stage.title)") { open(store.expeditions.game(for: next)) }
                            .buttonStyle(TilePrimaryButton()).accessibilityIdentifier("rails.next")
                    }
                    ShareLink(item: expedition.shareText) { Label("分享同盘 · \(expedition.code)", systemImage: "square.and.arrow.up") }
                } else if let trial {
                    Text(game.stars == 3 && game.rewinds == 0 ? "精通星章已点亮" : "三星且零撤回可点亮精通星章").foregroundStyle(TileTheme.gold)
                    ShareLink(item: trial.shareText) { Label("分享星约码 · \(trial.id)", systemImage: "square.and.arrow.up") }
                        .accessibilityIdentifier("trials.share")
                    Button("再挑战一次") { restart() }.buttonStyle(TilePrimaryButton()).accessibilityIdentifier("trials.retry")
                } else if let next = StarRail.stage(game.stage.id + 1) {
                    Button("下一关 · \(next.title)") { open(store.save.game(for: next.id) ?? StarRail.Game(stage: next)) }
                        .buttonStyle(TilePrimaryButton()).accessibilityIdentifier("rails.next")
                } else {
                    Button("开启星约试炼") { trialHall = true }.buttonStyle(TilePrimaryButton())
                }
            } else {
                Text(game.failureReason(in: game.state) ?? "撤回一步，重新规划。").font(.subheadline).lineSpacing(4)
                ForEach(game.reviewMoments.suffix(2)) { moment in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("第 \(moment.id) 手 · \(moment.title)").font(.subheadline.bold())
                        Text(moment.detail).font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Text("下方复盘可逐手查看，并回到任一步重新尝试。").font(.caption).foregroundStyle(TileTheme.mint)
            }
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
    private var inspectionSheet: some View {
        NavigationStack {
            List {
                Section("操作反馈") {
                    Toggle("原创音效", isOn: $sounds).accessibilityIdentifier("rails.sound")
                    Toggle("触感反馈", isOn: $haptics)
                    Button("下次重新显示互动教学") { store.resetLessons() }
                    Text("小屏或大字号时，可在下方叠层列表取牌。音效遵循手机静音设置。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("当前航线") {
                    Text(game.stage.objective)
                    if let config = journeyConfig {
                        Text(config.ability.detail)
                        if let budget = config.energyBudget { Text("本关总耗能预算 \(budget)，已使用 \(game.state.spentEnergy)。免费返航不消耗预算。") }
                    }
                    Text(game.stage.tip).accessibilityIdentifier("rails.hint")
                    ForEach(game.stage.rails) { rail in Text(goalText(rail)).foregroundStyle(RailPalette.rail(rail.id)) }
                    Text("三星：移层不超过 \(game.stage.plannedMoves) 次、三消结算后槽位峰值不超过 \(game.stage.targetPeak)。不限时。")
                    if let trial { Text(trial.rule.detail); ShareLink(item: trial.shareText) { Text("分享同一星约") } }
                    if let expedition { ShareLink(item: expedition.shareText) { Text("分享同一远征航线") } }
                }
                Section("轨道规则") {
                    if let config = journeyConfig { Text(config.ability.detail) }
                    Text("三消获得 1 点能量，上限 \(game.stage.energyLimit)；超出部分不储存。普通轨道移动花 1 点；分岔近端花 1 点，远端花 2 点，返航花 1 点。两个分岔之间要先返航。")
                    Text("轨道上方有牌时不能移动；终点有同层牌时不能进入。预览中绿色标出新露出的牌，橙色标出将盖住的牌。所有图案始终可查，不需要猜盲牌。")
                    Text("轨道最后一张锚牌要留到目标完成。先储备返程能量，再决定取牌。复盘回到早先步骤会计入试炼和远征的撤回次数；最佳成绩保留。")
                }
                Section("配对观察 · 当前局面") {
                    ForEach(game.kindPlans(in: game.state)) { item in
                        HStack {
                            TileGlyph(kind: item.kind).frame(width: 30, height: 30)
                            Text(StarRail.names[item.kind]); Spacer()
                            Text("槽内 \(item.inTray) · 可取 \(item.available) · 在盘 \(item.remaining)")
                                .font(.caption).foregroundStyle(item.canComplete ? TileTheme.mint : .secondary)
                        }
                    }
                }
                ForEach((0...2).reversed(), id: \.self) { layer in
                    let cards = game.board(in: game.state).filter { $0.z == layer }
                    if !cards.isEmpty {
                        Section(layer == 0 ? "底层" : "第 \(layer) 层") {
                            ForEach(cards) { card in
                                let blockers = game.blockers(of: card.id, in: game.state)
                                Button { act(.pick(card.id)) } label: {
                                    HStack {
                                        TileGlyph(kind: card.kind).frame(width: 36, height: 36)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(game.isStarCore(card.id) ? "星核（护送目标）" : StarRail.names[card.kind]) · 第 \(card.y/4+1) 行 / \(card.x/4+1) 列")
                                            Text(game.isStarCore(card.id) ? "不可取走：移轨护送到指定岔口" : game.isAnchor(card.id, in: game.state) ? "锚牌：航线完成后才能取" : blockers.isEmpty ? "当前可取" : "被 \(names(Set(blockers))) 盖住")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(); Image(systemName: "plus.circle.fill").foregroundStyle(TileTheme.mint)
                                    }.frame(minHeight: 48)
                                }
                                .buttonStyle(.plain).disabled(!session.canInteract || game.rejection(.pick(card.id), in: game.state) != nil)
                                .accessibilityIdentifier("rails.listCard.\(card.id)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("叠层与航线").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { inspection = false }.accessibilityIdentifier("rails.inspect.done") } }
        }.preferredColorScheme(.dark)
    }
    private func goalText(_ rail: StarRail.Rail) -> String {
        let mask = game.stage.goalMask(rail: rail.id)
        let goal = game.state.arrivals & mask == mask
        return "\(rail.name) · 在\(rail.stopName(game.state.positions[rail.id])) · \(goal ? "航线目标已完成" : "航线目标未完成")"
    }
    private func names(_ ids: Set<Int>) -> String {
        let counts = Dictionary(grouping: ids, by: { game.stage.cards[$0].kind })
        return counts.isEmpty ? "无" : counts.keys.sorted().map { "\(StarRail.names[$0]) ×\(counts[$0]!.count)" }.joined(separator: "、")
    }
    private func configureSound() { StarRailSound.shared.configure(active: scenePhase == .active, enabled: sounds) }
    private func clearPreview() { selectedRail = nil; selectedStop = nil }
    private func act(_ action: StarRail.Action) {
        guard session.canInteract else { return }
        let beforeMatches = game.state.matches, beforeOverflow = game.state.overflowEnergy
        let gateWasOpen = game.gateOpen(in:game.state)
        var token: UUID?, accepted = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            if case .pick(let id) = action { accepted = session.take(id) }
            else { token = session.submit(action); accepted = token != nil }
        }
        guard accepted else { return }
        clearPreview()
        let cue: StarRailAudioPCM.Cue
        if game.status == .lost {
            lastFeedback = "路线受阻 · 复盘可以回到前一步"; cue = .fail
            if haptics { Haptics.warning() }
        } else if game.status == .won {
            lastFeedback = "航线完成 · \(game.stars) 星"; cue = .win
            if haptics { Haptics.success() }
        } else if !gateWasOpen && game.gateOpen(in:game.state) {
            lastFeedback = "星门已开启 · A 轨可以通行"; cue = .charge
            if haptics { Haptics.success() }
        } else if game.state.matches > beforeMatches {
            let full = game.state.overflowEnergy > beforeOverflow
            lastFeedback = full ? "三消完成 · 储能已满" : "三消完成 · 能量 +1"; cue = full ? .match : .charge
            if haptics { Haptics.success() }
        } else if token != nil {
            lastFeedback = "移层完成 · 余能 \(game.state.energy)"; cue = .shift
            if haptics { Haptics.select() }
        } else {
            lastFeedback = nil; cue = .pick
            if haptics { Haptics.tap() }
        }
        if sounds { StarRailSound.shared.play(cue) }
        if let lastFeedback { UIAccessibility.post(notification: .announcement, argument: lastFeedback) }
        store.keep(game)
        if let token {
            animationTask?.cancel()
            animationTask = Task { @MainActor in
                if !reduceMotion { try? await Task.sleep(nanoseconds: 180_000_000) }
                guard !Task.isCancelled else { return }
                session.finish(token)
            }
        }
    }
    private func stopAnimation() {
        animationTask?.cancel(); animationTask = nil
        if let token = session.pending { session.finish(token) }
    }
    private func open(_ next: StarRail.Game) {
        stopAnimation(); clearPreview(); lastFeedback = nil; previewSeen = false
        session = StarRail.Session(game: next); store.keep(game)
    }
    private func restart() {
        stopAnimation(); clearPreview(); lastFeedback = nil; previewSeen = false; session.restart(); store.keep(game)
    }
}

struct StarRailTray: View {
    let game: StarRail.Game
    let state: StarRail.State
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<game.stage.capacity, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(.black.opacity(0.25))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(0.1)))
                    if index < state.tray.count {
                        let kind = game.stage.cards[state.tray[index]].kind
                        RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.92, green: 0.95, blue: 0.88)).padding(2)
                        TileGlyph(kind: kind).padding(6)
                        if state.tray.filter({ game.stage.cards[$0].kind == kind }).count == 2 {
                            RoundedRectangle(cornerRadius: 8).strokeBorder(TileTheme.gold, lineWidth: 2).padding(2)
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit).frame(maxWidth: .infinity)
                .accessibilityLabel(index < state.tray.count ? StarRail.names[game.stage.cards[state.tray[index]].kind] : "空槽")
            }
        }.accessibilityElement(children: .combine)
    }
}
