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
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases) { item in
                    Button {
                        tab = item
                        opened = nil
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .arenaOutline(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tab == item ? Color(red: 0.55, green: 0.35, blue: 0.95) : .black.opacity(0.35)))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.black.opacity(0.65), lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            ZStack(alignment: .bottom) {
                ScrollView {
                    switch tab {
                    case .quests: quests
                    case .track: track
                    case .shop: shop
                    case .ranked: rankedInfo
                    }
                }
                if let opened {
                    questDetail(opened)
                }
            }
        }
        .onAppear { growth.refreshSeason() }
        .environment(\.colorScheme, .dark)
    }

    @State private var opened: ArenaQuest?

    // MARK: 任务

    private var quests: some View {
        let all = progress.quests(Date(), calendar: .current)
        return VStack(alignment: .leading, spacing: 8) {
            seasonHeader
            Text("每日")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
            ForEach(all.filter { !$0.weekly }) { questCard($0) }
            Text("每周")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 4)
            ForEach(all.filter(\.weekly)) { questCard($0) }
        }
    }

    private var seasonHeader: some View {
        let state = progress.season
        let into = state.tier >= ArenaSeason.tiers ? ArenaSeason.pointsPerTier : state.points % ArenaSeason.pointsPerTier
        let fraction = CGFloat(into) / CGFloat(ArenaSeason.pointsPerTier)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("赛季 \(state.tier) 级")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                Spacer()
                Text("还剩 \(ArenaSeason.daysLeft(Date(), calendar: .current)) 天")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().fill(Color(red: 0.62, green: 0.4, blue: 1)).frame(width: 180 * fraction)
            }
            .frame(width: 180, height: 10)
            .overlay(Capsule().strokeBorder(.black.opacity(0.6), lineWidth: 1.5))
            Text(state.tier >= ArenaSeason.tiers ? "这一季满级了" : "再 \(ArenaSeason.pointsPerTier - into) 经验升到 \(state.tier + 1) 级")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 2))
    }

    private func questCard(_ quest: ArenaQuest) -> some View {
        let value = progress.questProgress(quest)
        let done = value >= quest.target
        let fraction = CGFloat(value) / CGFloat(max(quest.target, 1))
        return Button {
            opened = quest
        } label: {
            HStack(spacing: 10) {
                Image(systemName: done ? "checkmark.seal.fill" : "scroll.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(done ? Color(red: 0.3, green: 0.75, blue: 0.35) : Color.orange))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.black.opacity(0.55), lineWidth: 2))
                VStack(alignment: .leading, spacing: 5) {
                    Text(quest.title)
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.45))
                        Capsule().fill(done ? Color(red: 0.4, green: 0.9, blue: 0.35) : Color.orange)
                            .frame(width: max(8, 160 * fraction))
                    }
                    .frame(width: 160, height: 8)
                    Text("\(value)/\(quest.target)")
                        .font(.system(size: 11, weight: .black, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text("+\(quest.points)")
                    .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(Capsule().fill(Color(red: 0.5, green: 0.28, blue: 0.9)))
                    .overlay(Capsule().strokeBorder(.black.opacity(0.55), lineWidth: 2))
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.black.opacity(0.38)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    /// 第三层：这个任务怎么算
    private func questDetail(_ quest: ArenaQuest) -> some View {
        let value = progress.questProgress(quest)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(quest.title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                Spacer()
                Button {
                    opened = nil
                } label: {
                    Image(systemName: "xmark").font(.headline.weight(.black)).foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(red: 0.85, green: 0.22, blue: 0.22)))
                }
                .buttonStyle(.plain)
            }
            Text(quest.detail)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
            Text("进度 \(value)/\(quest.target)，做完 +\(quest.points) 赛季经验")
                .font(.system(size: 12, weight: .black, design: .rounded).monospacedDigit())
                .foregroundStyle(Color(red: 1, green: 0.86, blue: 0.35))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(red: 0.16, green: 0.1, blue: 0.28).opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.black, lineWidth: 3))
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
