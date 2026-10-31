import SwiftUI

/// A list and a full detail page using the existing menu and animated character renderer.
struct ArenaHeroSelection: View {
    let selected: Brawler
    var startsMatch = false
    let onClose: () -> Void
    let onSelect: (Brawler) -> Void
    var onSourceHeroes: (() -> Void)?
    @State private var inspected: Brawler?

    var body: some View {
        ArenaMenuScreen(title: inspected?.name ?? "选择英雄", onClose: {
            if inspected != nil { inspected = nil } else { onClose() }
        }, scrollContent: false) {
            GeometryReader { geometry in
                if let hero = inspected {
                    detail(hero, height: geometry.size.height)
                } else {
                    ScrollView {
                        if let onSourceHeroes, ArenaResourcePackStore.shared.manifest != nil {
                            Button("原版英雄 · \(ArenaResourcePackStore.shared.manifest?.heroes.count ?? 0)", action: onSourceHeroes)
                                .buttonStyle(ArenaMenuButtonStyle()).padding(10)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            ForEach(ArenaQualitySample.heroes, id: \.self) { hero in
                                Button { inspected = hero } label: {
                                    VStack(spacing: 10) {
                                        BrawlerBadge(brawler: hero, size: 76, selected: hero == selected)
                                        Text(hero.name).font(.title3.bold())
                                        Text(hero.role).font(.subheadline)
                                        HStack(spacing: 5) {
                                            if hero == selected {
                                                ArenaVendorIcon(name: "checkmark").frame(width: 14, height: 14)
                                            }
                                            Text(hero == selected ? "已选择 · 查看详情" : "查看详情")
                                        }.font(.caption).foregroundStyle(.cyan)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 180)
                                    .padding(10)
                                }
                                .buttonStyle(ArenaMenuButtonStyle())
                                .accessibilityIdentifier("arena.hero.\(hero.rawValue)")
                            }
                        }
                        Text(startsMatch ? "三种打法 · 选择英雄后进入双闸交汇对战" : "三种打法 · 选择后返回大厅，再进入双闸交汇")
                            .font(.caption).foregroundStyle(.white.opacity(0.75)).padding(.top, 12)
                    }

                    .task { await ArenaPortraits.shared.prepare() }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let hero = inspected {
                HStack(spacing: 12) {
                    Button { ArenaSound.shared.menu(.uiBack); inspected = nil } label: {
                        HStack(spacing: 8) {
                            ArenaVendorIcon(name: "arrowLeft").frame(width: 16, height: 16)
                            Text("返回英雄列表")
                        }.frame(maxWidth: .infinity, minHeight: 44)
                    }
                        .buttonStyle(ArenaMenuButtonStyle())
                        .accessibilityIdentifier("arena.hero.back")
                    Button { ArenaSound.shared.menu(.uiSelect); onSelect(hero) } label: {
                        Text(startsMatch ? "使用\(hero.name)开始对战" : "选择\(hero.name)").frame(maxWidth: .infinity, minHeight: 44)
                    }
                        .buttonStyle(ArenaMenuButtonStyle())
                        .accessibilityIdentifier("arena.hero.select")
                }
                .frame(maxWidth: 720).padding(.horizontal, 16).padding(.vertical, 10)
                .frame(maxWidth: .infinity).background(ArenaMenuTheme.canvas)
            }
        }
    }

    private func detail(_ hero: Brawler, height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                ArenaShowcase(brawler: hero, qualitySample: true)
                    .frame(width: 220, height: max(1, height - 24))
                    .accessibilityIdentifier("arena.hero.model.\(hero.rawValue)")
                Text("拖动转身 · 轻点观看动作")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 220, height: height)
            ArenaMenuCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(hero.role).font(.title3.bold()).foregroundStyle(.cyan)
                        Text("普通攻击").font(.headline)
                        Text(hero.attackNote)
                        Text(hero.superNote).foregroundStyle(.yellow)
                        Divider().overlay(.white.opacity(0.2))
                        Text("基础生命 \(hero.maxHealth) · 射程 \(hero.attackRange, specifier: "%.1f") 格")
                        Text("每发装填 \(hero.reload, specifier: "%.1f") 秒 · 最多储存 3 发")
                        Text(tactics(hero)).foregroundStyle(.white.opacity(0.8))
                    }
                    .font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
                }
            }.frame(height: height)
        }

    }

    private func tactics(_ hero: Brawler) -> String {
        switch hero {
        case .barbarian: return "借掩体接近敌人，近身连续挥斧；攒满大招后越墙跃击，落地争夺据点。"
        case .mage: return "站在掩体后投掷火球；观察落点和飞行时间，用陨石压制据点，避免被近身。"
        default: return "用短墙遮住换弹空窗；从侧路换角度，用穿透重弩打击站成一线的敌人。"
        }
    }
}
