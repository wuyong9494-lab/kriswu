import SwiftUI

struct TileGameHomeView: View {
    @ObservedObject private var records = TileRecordStore.shared
    @ObservedObject private var rails = StarRailStore.shared
    @State private var play: TilePlay?
    @State private var code = ""
    @State private var lobby: GameRoomEntry?
    @State private var social = false
    @State private var help = false
    @State private var starRails = false
    @State private var railPlay: StarRailPlay?
    @State private var trialPlay: StarTrialPlay?
    @State private var trialHall = false
    @State private var expeditionHall = false
    @State private var collection = false
    @State private var journeyHall = false
    @State private var modesExpanded = false
    @State private var preparingMaster = false
    @State private var dailyRequest: DayKey?
    @State private var preparedDaily: (day: DayKey, seed: UInt64)?
    @State private var masterRequest: TileGame.RuleSet?
    @State private var now = Date()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                masterEntries
                daily
                Button { modesExpanded.toggle() } label: {
                    HStack { Label("更多玩法 · 原进度保留",systemImage:"square.grid.2x2"); Spacer(); Image(systemName:modesExpanded ? "chevron.up" : "chevron.down") }
                        .font(.headline).padding(16).background(.white.opacity(0.05),in:RoundedRectangle(cornerRadius:16))
                }.buttonStyle(.plain).accessibilityIdentifier("tiles.modes")
                if modesExpanded {
                    journeyEntry
                    constellationEntry
                    StarExpeditionDailyCard(date: now) { route in railPlay = StarRailPlay(game: rails.expeditions.game(for: route)) }
                    legacyResume
                    expeditionEntries
                    trialEntry
                    starRailEntry
                    journey
                    quickPlay
                    challenge
                    Button { social = true } label: {
                        Label("和朋友比一局", systemImage: "person.2.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(18)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                }
                Button("玩法与星级") { help = true }.font(.subheadline).foregroundStyle(.white.opacity(0.65))
            }
            .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(RailSkyBackdrop(theme: rails.sky).ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .navigationTitle(TileGame.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TileTheme.navy, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .fullScreenCover(item: $play) { TileBoardView(play: $0, race: nil) }
        .fullScreenCover(isPresented: $starRails) { StarRailHomeView() }
        .fullScreenCover(item: $railPlay) { StarRailBoardView(game: $0.game) }
        .fullScreenCover(isPresented: $trialHall) { StarTrialHomeView() }
        .fullScreenCover(isPresented: $expeditionHall) { StarExpeditionHomeView() }
        .fullScreenCover(isPresented: $collection) { StarCollectionView() }
        .fullScreenCover(isPresented: $journeyHall) { StarJourneyHomeView() }
        .fullScreenCover(item: $trialPlay) { StarRailBoardView(game: $0.game) }
        .onAppear { now = Date() }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .onChange(of: scenePhase) { if $0 == .active { now = Date() } }
        .fullScreenCover(item: $lobby) { TileRaceLobbyView(room: $0.room) }
        .sheet(isPresented: $social) {
            NavigationStack {
                List {
                    GameRoomButtons(kind: .tiles, remotePlayers: 2...4, nearbyCapacity: TileRaceGame.most) { entry in
                        social = false
                        // 等连接面板收起再呈现房间，避免两个呈现动作竞争。
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            lobby = GameRoomEntry(room: entry)
                        }
                    }
                }
                .navigationTitle("经典竞速")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { social = false } } }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $help) { helpSheet }
    }

    private var legacyResume: some View {
        Button {
            if let game = rails.save.game(for: rails.save.progress.nextStage.id) { railPlay = StarRailPlay(game: game) }
        } label: {
            HStack {
                Text("\(rails.save.progress.totalStars == 18 ? "精进航线" : "开始航行") · 第 \(rails.save.progress.nextStage.id) 关")
                Spacer()
                Text(rails.save.progress.nextStage.title).font(.subheadline)
                Image(systemName: "arrow.right")
            }
            .padding(.horizontal, 18)
        }
        .buttonStyle(TilePrimaryButton())
        .accessibilityIdentifier("tiles.railContinue")
    }
    private var constellationEntry: some View {
        Button { collection = true } label: {
            HStack(spacing:16) {
                Image(systemName:"star.circle.fill").font(.system(size:32)).foregroundStyle(TileTheme.gold)
                VStack(alignment:.leading,spacing:6) {
                    Text("星图 · 修复 \(StarRail.StarMap.restored(earned:rails.earnedStars))/12").font(.headline)
                    Text(StarRail.StarMap.next(earned:rails.earnedStars).map { "再获 \($0-rails.earnedStars) 星章，点亮下一颗星" } ?? "十二颗星已点亮，继续挑战最佳航线")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength:0);Image(systemName:"chevron.right")
            }.padding(18).background(TileTheme.gold.opacity(0.08),in:RoundedRectangle(cornerRadius:20))
        }.buttonStyle(.plain).accessibilityIdentifier("tiles.collection")
    }

    private var expeditionEntries: some View {
        HStack(spacing: 12) {
            Button { expeditionHall = true } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Label("分岔远征", systemImage: "arrow.triangle.branch").font(.headline)
                    Text("6 种结构 · 36 条航线").font(.caption).foregroundStyle(.white.opacity(0.6))
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(TileTheme.mint.opacity(0.10), in: RoundedRectangle(cornerRadius: 18))
            }.buttonStyle(.plain).accessibilityIdentifier("tiles.expeditions")

        }
    }

    private var trialEntry: some View {
        Button { trialHall = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "sparkles").font(.title2).foregroundStyle(RailPalette.lilac)
                VStack(alignment: .leading, spacing: 5) {
                    Text("星约试炼").font(.headline)
                    Text("12 项策略契约 · 已完成 \(rails.trials.completed) · 精通 \(rails.trials.mastered)")
                        .font(.caption).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .padding(20).background(RailPalette.lilac.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).accessibilityIdentifier("tiles.trials")
    }

    private var starRailEntry: some View {
        Button { starRails = true } label: {
            HStack(spacing: 16) {
                Image(systemName: "arrow.triangle.swap").font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(TileTheme.mint)
                VStack(alignment: .leading, spacing: 6) {
                    Text("移排练习 · 星轨移层").font(.system(.title3, design: .rounded).bold())
                    Text("6 关手工航线 · 从观察到双轨规划")
                        .font(.caption).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
            }
            .padding(20).background(TileTheme.mint.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(TileTheme.mint.opacity(0.4)))
        }
        .buttonStyle(.plain).accessibilityIdentifier("tiles.starRails")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(TileGame.displayName).font(.system(size: 38, weight: .heavy, design: .rounded))
                        .minimumScaleFactor(0.65).lineLimit(1)
                    Text("留一格，想三步。")
                        .font(.system(.subheadline, design: .rounded)).foregroundStyle(.white.opacity(0.65))
                    Label("大师通关 \(records.records.wins[3, default: 0]) · 深空通关 \(records.constellationRecords.wins[3, default: 0])", systemImage: "star.fill")
                        .font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(TileTheme.gold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                RailHomeArtwork(back: rails.cardBack).scaleEffect(0.9).frame(width: 130, height: 145)
            }


        }
    }

    private var journeyEntry: some View {
        VStack(spacing: 12) {
            Button { journeyHall = true } label: {
                HStack {
                    Text(rails.journeys.pendingReward != nil ? "查看旅程奖励" : rails.journeys.active?.finished == false ? "继续旅程" : "开始星际旅程")
                    Spacer()
                    Text(rails.journeys.active?.finished == false ? "第 \(rails.journeys.active!.chapter+1)/3 关" : "三关 · 一段星河").font(.subheadline)
                    Image(systemName:"arrow.right")
                }.padding(.horizontal,18)
            }.buttonStyle(TilePrimaryButton()).accessibilityIdentifier("tiles.journeyContinue")
            if let run=rails.journeys.active, !run.finished {
                JourneyChapterStrip(chapter:run.chapter,completed:run.completed.count)
            }
        }
    }

    private var masterEntries: some View {
        VStack(spacing: 12) {
            masterButton("大师", detail: "9 种图案 · 拆开遮挡，留好下一组三张", rule: .classic)
            masterButton("深空大师", detail: "12 种图案 · 更多交错，提前安排取牌顺序", rule: .constellation)
            if preparingMaster {
                ProgressView("正在准备牌局…").tint(TileTheme.mint)
            }
        }
        .task(id: masterRequest) {
            guard let rule = masterRequest else { return }
            let base = UInt64.random(in: 0..<TileGame.seedLimit)
            let worker = Task.detached(priority: .userInitiated) {
                TileGame.masterSeed(startingAt: base, ruleSet: rule)
            }
            let seed = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            play = TilePlay(level: .hard, seed: seed, mode: .solo, ruleSet: rule, screenedMaster: true)
            preparingMaster = false
            masterRequest = nil
        }
    }

    private func masterButton(_ title: String, detail: String, rule: TileGame.RuleSet) -> some View {
        Button {
            preparingMaster = true
            masterRequest = rule
        } label: {
            HStack(spacing: 14) {
                Image(systemName: rule == .classic ? "star.fill" : "sparkles")
                    .font(.title).foregroundStyle(TileTheme.gold)
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(.title2, design: .rounded).bold())
                    Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(TileTheme.mint.opacity(rule == .classic ? 0.12 : 0.2), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).disabled(preparingMaster || dailyRequest != nil)
        .accessibilityIdentifier("tiles.master.\(rule.rawValue)")
    }

    private var journey: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("经典星域", detail: "\(records.journey.totalStars) / 36 星 · 原进度保留")
            Button { open(records.journey.nextStage) } label: {
                Label("继续经典 · 第 \(records.journey.nextStage.id) 关", systemImage: "arrow.right")
                    .font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            }
            .buttonStyle(.plain).accessibilityIdentifier("tiles.continue")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(TileJourney.stages) { stage in
                    let unlocked = records.journey.isUnlocked(stage.id)
                    Button { open(stage) } label: {
                        VStack(spacing: 9) {
                            HStack {
                                Text(String(format: "%02d", stage.id)).font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                                Spacer()
                                Image(systemName: unlocked ? "sparkle" : "lock.fill")
                                    .font(.system(size: 13)).foregroundStyle(unlocked ? TileTheme.mint : .white.opacity(0.2))
                            }
                            Text(stage.name).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                            TileStars(count: records.journey.stars[stage.id] ?? 0).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(13)
                        .foregroundStyle(.white.opacity(unlocked ? 1 : 0.38))
                        .background(unlocked ? TileTheme.panel : .white.opacity(0.025), in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(unlocked ? TileTheme.mint.opacity(0.22) : .white.opacity(0.06)))
                    }
                    .buttonStyle(.plain).disabled(!unlocked)
                    .accessibilityIdentifier("tiles.stage.\(stage.id)")
                    .accessibilityLabel("第 \(stage.id) 关，\(stage.name)，\(unlocked ? "已解锁" : "未解锁")")
                }
            }
        }
    }

    private var quickPlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("自由挑战", detail: "每次都是新牌局")
            HStack(spacing: 10) {
                ForEach(TileGame.Level.allCases, id: \.self) { level in
                    Button { play = TilePlay(level: level, seed: UInt64.random(in: 0..<TileGame.seedLimit), mode: .solo) } label: {
                        VStack(spacing: 10) {
                            TileGlyph(kind: [4, 7, 2][level.rawValue - 1]).frame(width: 44, height: 44)
                            Text(TileTheme.title(level)).font(.system(.headline, design: .rounded))
                            Text(["6 种 · 4 层", "10 种 · 6 层", "12 种 · 8 层"][level.rawValue - 1]).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("tiles.quick.\(level.rawValue)")
                }
            }
        }
    }

    private var daily: some View {
        Button { dailyRequest = DayKey(date: Date(), calendar: .dayMath) } label: {
            HStack(spacing: 16) {
                Image(systemName: "sun.max.fill").font(.system(size: 26)).foregroundStyle(TileTheme.gold)
                VStack(alignment: .leading, spacing: 5) {
                    Text(dailyRequest == nil ? "每日一关 · 深空大师" : "正在准备今日牌局…").font(.headline)
                    Text(records.constellationRecords.daily[TileGame.dailyPlanningRecordKey(DayKey(date: now, calendar: .dayMath))]?.won == true ? "今日已通关，再试一次更高连消" : "北京时间每日更新 · 同日同一盘")
                        .font(.caption).foregroundStyle(.white.opacity(0.6))
                    if let entry = records.dailyAttempts.entries[TileGame.dailyPlanningRecordKey(DayKey(date: now, calendar: .dayMath))] {
                        Text("今日 \(entry.attempts) 次尝试 · 首局\(firstAttemptTitle(entry.firstOutcome))")
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right")
            }
            .padding(20).background(TileTheme.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).accessibilityIdentifier("tiles.daily")
        .disabled(preparingMaster || dailyRequest != nil)
        .task(id: dailyRequest) {
            guard let day = dailyRequest else { return }
            let seed: UInt64
            if let cached = preparedDaily, cached.day == day {
                seed = cached.seed
            } else {
                let worker = Task.detached(priority: .userInitiated) { TileGame.dailyPlanningSeed(day) }
                seed = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: { worker.cancel() }
            }
            guard !Task.isCancelled else { return }
            preparedDaily = (day, seed)
            play = TilePlay(level: .hard, seed: seed, mode: .daily(day), screenedDaily: true, planningDaily: true)
            dailyRequest = nil
        }
    }

    private func firstAttemptTitle(_ outcome: TileDailyAttempts.Outcome) -> String {
        switch outcome {
        case .pending: return "结果待定"
        case .wonWithoutTools: return "无道具通关"
        case .lost: return "未通关"
        case .usedTools: return "使用道具"
        case .abandoned: return "中途退出"
        }
    }

    private var challenge: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("接一张挑战书", detail: "远征码 / 星约码 / 经典码")
            HStack(spacing: 10) {
                TextField("输入或粘贴挑战码", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(.subheadline, design: .monospaced)).padding(14)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("tiles.code")
                Button {
                    if let route = StarRail.Expedition.decode(code), !StarRail.Trial.containsCodePrefix(code) {
                        railPlay = StarRailPlay(game: rails.expeditions.game(for: route)); return
                    }
                    if let trial = StarRail.Trial.decode(code), !StarRail.Expedition.containsCodePrefix(code) {
                        trialPlay = StarTrialPlay(game: rails.trials.game(for: trial))
                        return
                    }
                    guard !StarRail.Trial.containsCodePrefix(code), !StarRail.Expedition.containsCodePrefix(code), let decoded = TileGame.decode(code) else {
                        ToastCenter.shared.show("挑战码不完整或版本不支持，请粘贴朋友分享的完整挑战码", style: .warning)
                        return
                    }
                    play = TilePlay(level: decoded.level, seed: decoded.seed, mode: .challenge, ruleSet: decoded.ruleSet)
                } label: {
                    Image(systemName: "arrow.right").font(.headline).frame(width: 46, height: 46)
                        .background(TileTheme.mint, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(TileTheme.ink)
                }
                .buttonStyle(.plain).disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("开始挑战")
            }
        }
    }

    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(.headline, design: .rounded))
            Spacer()
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.45))
        }
    }

    private func open(_ stage: TileJourney.Stage) {
        guard records.journey.isUnlocked(stage.id) else { return }
        play = TilePlay(level: stage.level, seed: stage.seed, mode: .journey(stage.id))
    }

    private var helpSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    helpRow("01", "经典规则：先看遮挡，再选牌", "只能拿没有被压住的牌。三张相同自动消除，槽内七张未能消除就会卡住。底部两摞也是牌堆，需要逐层取出。")
                    helpRow("02", "给下一组三张留位置", "越往深空走，牌种越多、遮挡越复杂。不要见一对就拿，先想第三张被谁压住。每个初始牌局都有通关路径。")
                    helpRow("03", "连消靠规划，不靠手速", "每次消除后的四次取牌内再消除，连消加一；单次得分从 100 分递增，五连及以上每次 500 分。使用道具会中断连消。")
                    helpRow("04", "把一星变成三星", "通关得一星；不用道具得两星；再达到轻松 3 连、进阶 4 连、大师 5 连即可三星。成绩只保留最好的一次。")
                    helpRow("05", "道具各用一次", "撤回上一张未消除的牌；移出槽左侧最多三张；洗牌只打乱牌堆中的图案。洗牌不会替你清槽，也不保证当前选择能被挽回。")
                    helpRow("✧", "三关星际旅程", "先选择贯穿整轮的能力，依次完成清盘、星核护送和限能返航。第一关后选择近航补给或远航追光；星门由指定图案三消开启。护送关不用清盘，但星核必须留在轨道，抵达目标时收集槽需为空。关间能量按所选能力继承，退出会保存当前进度。")
                    helpRow("✦", "分岔远征与星图", "近岔花 1 点能量，远岔花 2 点，返航花 1 点。预览两端的遮挡，再选择路线。完成主线、星约和远征，累计最佳星级修复星图，解锁天幕和星牌外观。复盘能逐手回看并从某一步重试。")
                    helpRow("★", "星轨主线与试炼", "每消除一组三张为轨道充能。预览移层后，决定先开窗还是留槽。星约试炼会改变槽位、储能和移层预算；三星且全程不撤回可点亮精通星章，允许随时重试。")
                }
                .padding(24)
            }
            .background(TileTheme.navy).navigationTitle("玩法与星级")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("明白了") { help = false } } }
        }
        .preferredColorScheme(.dark)
    }

    private func helpRow(_ index: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(index)  \(title)").font(.headline).foregroundStyle(TileTheme.mint)
            Text(detail).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineSpacing(5)
        }
    }
}
