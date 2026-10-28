import SwiftUI

// MARK: - 赛季面板

/// 大厅里的「赛季」：任务、赛季奖励（30 级）、商店（皮肤、表情）、排位段位
struct ArenaSeasonSheet: View {
    @ObservedObject private var growth = ArenaProgressStore.shared
    @State private var tab = Tab.quests

    enum Tab: String, CaseIterable, Identifiable {
        case quests = "任务", track = "赛季奖励", shop = "商店", ranked = "排位"
        var id: String { rawValue }
    }

    private var progress: ArenaProgress { growth.progress }

    var body: some View {
        List {
            Section {
                Picker("看哪个", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch tab {
            case .quests: quests
            case .track: track
            case .shop: shop
            case .ranked: rankedInfo
            }
        }
        .appList()
        .navigationTitle("赛季")
        .onAppear { growth.refreshSeason() }
    }

    // MARK: 任务

    @ViewBuilder private var quests: some View {
        let all = progress.quests(Date(), calendar: .current)
        seasonHeader
        Section {
            ForEach(all.filter { !$0.weekly }) { questRow($0) }
        } header: {
            Text("每日任务")
        } footer: {
            Text("每天零点换新的；打完一局自动算进度，做完给赛季经验。")
        }
        Section {
            ForEach(all.filter(\.weekly)) { questRow($0) }
        } header: {
            Text("每周任务")
        } footer: {
            Text("每周一换新的。冒险、排位、联机的局都算。")
        }
    }

    private var seasonHeader: some View {
        let state = progress.season
        let into = state.tier >= ArenaSeason.tiers ? ArenaSeason.pointsPerTier : state.points % ArenaSeason.pointsPerTier
        return Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("赛季 \(state.tier) 级", systemImage: "medal.fill")
                        .font(DS.Font.headline)
                        .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
                    Spacer()
                    Text("还剩 \(ArenaSeason.daysLeft(Date(), calendar: .current)) 天")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: Double(into), total: Double(ArenaSeason.pointsPerTier))
                    .tint(Color(red: 0.55, green: 0.35, blue: 0.95))
                Text(state.tier >= ArenaSeason.tiers ? "这一季满级了" : "再 \(ArenaSeason.pointsPerTier - into) 经验升到 \(state.tier + 1) 级")
                    .font(DS.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func questRow(_ quest: ArenaQuest) -> some View {
        let value = progress.questProgress(quest)
        let done = value >= quest.target
        return HStack(spacing: DS.Space.s) {
            Image(systemName: done ? "checkmark.seal.fill" : "scroll.fill")
                .font(.title3)
                .foregroundStyle(done ? DS.Palette.success : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title).font(DS.Font.headline).foregroundStyle(done ? .secondary : .primary)
                ProgressView(value: Double(value), total: Double(quest.target))
                    .tint(done ? DS.Palette.success : Color.orange)
                Text("\(value)/\(quest.target)").font(DS.Font.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer()
            Text("+\(quest.points)")
                .font(DS.Font.headline.monospacedDigit())
                .foregroundStyle(Color(red: 0.55, green: 0.35, blue: 0.95))
        }
    }

    // MARK: 赛季奖励

    @ViewBuilder private var track: some View {
        seasonHeader
        Section {
            ForEach(1...ArenaSeason.tiers, id: \.self) { tier in
                tierRow(tier)
            }
        } footer: {
            Text("每 \(ArenaSeason.pointsPerTier) 赛季经验升一级，每一级都能领一份。每个月是新的一季，经验和领过的从头来（领到的皮肤、表情一直都有）。")
        }
    }

    private func tierRow(_ tier: Int) -> some View {
        let state = progress.season
        let prize = ArenaSeason.prize(tier)
        let reached = state.tier >= tier
        let claimed = state.claimed.contains(tier)
        return HStack(spacing: DS.Space.s) {
            Text("\(tier)")
                .font(.system(size: 15, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(reached ? Color(red: 0.55, green: 0.35, blue: 0.95) : Color.gray.opacity(0.5)))
            prizeIcon(prize)
            Text(prize.title).font(DS.Font.headline)
            Spacer()
            if claimed {
                Label("领过了", systemImage: "checkmark").font(DS.Font.caption).foregroundStyle(.secondary)
            } else if reached {
                Button("领取") { growth.claim(tier) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.55, green: 0.35, blue: 0.95))
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func prizeIcon(_ prize: ArenaSeason.Prize) -> some View {
        switch prize {
        case .coins:
            Image(systemName: "dollarsign.circle.fill").font(.title2).foregroundStyle(.yellow)
        case .skin(let id):
            if let skin = ArenaSkin.find(id) {
                BrawlerBadge(brawler: skin.brawler, size: 30)
                    .overlay(Circle().strokeBorder(skin.color, lineWidth: 3))
            }
        case .emote(let id):
            Text(ArenaEmote.find(id)?.symbol ?? "🙂").font(.title2)
        }
    }

    // MARK: 商店

    @ViewBuilder private var shop: some View {
        Section {
            HStack {
                Label("\(progress.coins)", systemImage: "dollarsign.circle.fill")
                    .font(DS.Font.headline.monospacedDigit())
                    .foregroundStyle(.yellow)
                Spacer()
                Text("金币打完一局就给").font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
        Section {
            ForEach(ArenaSkin.all) { skin in
                skinRow(skin)
            }
        } header: {
            Text("皮肤")
        } footer: {
            Text("皮肤只换样子，不加属性；联机时别人也看得到。买了在「本事」里给角色穿上。")
        }
        Section {
            ForEach(ArenaEmote.all.filter { !$0.free }) { emote in
                emoteRow(emote)
            }
        } header: {
            Text("表情")
        } footer: {
            Text("对局里点左上角的笑脸，头顶冒一个表情。前四个一开始就有，有的要赛季奖励。")
        }
    }

    private func skinRow(_ skin: ArenaSkin) -> some View {
        let owned = progress.owns(skin: skin)
        return HStack(spacing: DS.Space.s) {
            BrawlerBadge(brawler: skin.brawler, size: 36)
                .overlay(Circle().strokeBorder(skin.color, lineWidth: 3))
            VStack(alignment: .leading, spacing: 2) {
                Text(skin.name).font(DS.Font.headline)
                Text(skin.brawler.name).font(DS.Font.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if owned {
                Label("有了", systemImage: "checkmark").font(DS.Font.caption).foregroundStyle(.secondary)
            } else {
                Button {
                    growth.buy(skin)
                } label: {
                    Label("\(skin.price)", systemImage: "dollarsign.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(progress.coins < skin.price)
            }
        }
    }

    private func emoteRow(_ emote: ArenaEmote) -> some View {
        let owned = progress.owns(emote: emote)
        return HStack(spacing: DS.Space.s) {
            Text(emote.symbol).font(.system(size: 30))
            Text(emote.name).font(DS.Font.headline)
            Spacer()
            if owned {
                Label("有了", systemImage: "checkmark").font(DS.Font.caption).foregroundStyle(.secondary)
            } else if let price = emote.price {
                Button {
                    growth.buy(emote)
                } label: {
                    Label("\(price)", systemImage: "dollarsign.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(progress.coins < price)
            } else {
                Text("赛季奖励").font(DS.Font.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: 排位

    @ViewBuilder private var rankedInfo: some View {
        let points = progress.season.rankPoints
        let current = ArenaRank.tier(points)
        Section {
            HStack(spacing: DS.Space.s) {
                Image(systemName: "shield.lefthalf.filled").font(.largeTitle).foregroundStyle(rankColor(current))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ArenaRank.tiers[current].name) · \(points) 分").font(DS.Font.title)
                    Text("最高到过 \(ArenaRank.tiers[progress.season.bestTier].name)").font(DS.Font.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section {
            ForEach(ArenaRank.tiers.indices, id: \.self) { k in
                let tier = ArenaRank.tiers[k]
                HStack {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(rankColor(k))
                    Text(tier.name).font(DS.Font.headline)
                    Spacer()
                    Text("\(tier.points) 分起 · 电脑 \(tier.botLevel) 级").font(DS.Font.caption).foregroundStyle(.secondary)
                    if k == current { Image(systemName: "location.fill").foregroundStyle(DS.Palette.accent) }
                }
            }
        } header: {
            Text("段位")
        } footer: {
            Text("在大厅把「普通」切到「排位」再开打。排位只打 3v3 的玩法：赢了 +25 分，输了按段位扣 8–20 分（不会扣到 0 以下）；段位越高，电脑越强。排位不加减奖杯，金币照给。")
        }
    }

    private func rankColor(_ tier: Int) -> Color {
        [Color(red: 0.75, green: 0.5, blue: 0.3), Color(red: 0.7, green: 0.75, blue: 0.82), Color(red: 1, green: 0.78, blue: 0.2),
         Color(red: 0.4, green: 0.8, blue: 1), Color(red: 0.75, green: 0.35, blue: 1)][min(max(tier, 0), 4)]
    }
}

// MARK: - 穿哪套皮肤

/// 「本事」里：这个角色穿哪套（原来的样子、有的皮肤），没有的去商店买
struct ArenaSkinSection: View {
    let brawler: Brawler
    @ObservedObject private var growth = ArenaProgressStore.shared

    var body: some View {
        let wearing = growth.progress.skin(brawler)
        Section {
            row(index: 0, name: "原来的样子", color: .gray, owned: true, wearing: wearing == 0)
            ForEach(ArenaSkin.of(brawler)) { skin in
                row(index: skin.index, name: skin.name, color: skin.color, owned: growth.progress.owns(skin: skin), wearing: wearing == skin.index)
            }
        } header: {
            Text("皮肤")
        } footer: {
            Text("没有的皮肤在大厅「赛季 › 商店」里用金币买，有的是赛季奖励。")
        }
    }

    private func row(index: Int, name: String, color: Color, owned: Bool, wearing: Bool) -> some View {
        Button {
            growth.wear(index, for: brawler)
        } label: {
            HStack(spacing: DS.Space.s) {
                Circle().fill(color).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.black.opacity(0.3), lineWidth: 1))
                Text(name).foregroundStyle(owned ? .primary : .secondary)
                Spacer()
                if wearing {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.Palette.accent)
                } else if !owned {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
        }
        .disabled(!owned)
    }
}

extension ArenaSkin {
    /// 皮肤的代表色（列表里画个圆）
    var color: Color { Color(red: tint[0], green: tint[1], blue: tint[2]) }
}

extension ArenaSeason.Prize {
    /// 奖励写成一句话
    var title: String {
        switch self {
        case .coins(let amount): return "\(amount) 金币"
        case .skin(let id): return "皮肤：" + (ArenaSkin.find(id)?.name ?? "")
        case .emote(let id): return "表情：" + (ArenaEmote.find(id).map { "\($0.symbol) \($0.name)" } ?? "")
        }
    }
}
