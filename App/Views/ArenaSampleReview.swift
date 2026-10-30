import SwiftUI

/// Trial entry and two review pages share the arena menu components.
struct ArenaSampleReview: View {
    let onClose: () -> Void
    let onPlay: () -> Void
    @State private var page = 0

    var body: some View {
        ArenaMenuScreen(title: "蓝月港 · 试玩样板", onClose: onClose) {
            VStack(spacing: 12) {
                Picker("样板页面", selection: $page) {
                    Text("游侠").tag(0)
                    Text("双闸交汇").tag(1)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("arena.sample.pages")
                if page == 0 { hero } else { map }
                Button(action: onPlay) {
                    Label("以游侠进入试玩", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ArenaMenuButtonStyle())
                .accessibilityIdentifier("arena.sample.play")
                Text("单人＋电脑队友 · 不计排位 · 画面与动作仍在制作")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                ArenaShowcase(brawler: .ranger, qualitySample: true)
                    .frame(width: 220, height: 235)
                    .accessibilityIdentifier("arena.sample.hero")
                Text("拖动转身 · 轻点观看动作")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            ArenaMenuCard {
                Text("游侠").font(.title2.bold())
                Text("远程单发 · 把握射线与换弹时机")
                    .font(.subheadline).foregroundStyle(.cyan)
                Text(Brawler.ranger.attackNote).font(.subheadline)
                Text(Brawler.ranger.superNote).font(.subheadline)
                Divider().overlay(.white.opacity(0.2))
                Text("基础射程 \(Brawler.ranger.attackRange, specifier: "%.0f") 格 · 每发装填 \(Brawler.ranger.reload, specifier: "%.1f") 秒")
                    .font(.caption)
                Text("用短墙遮住换弹空窗；从侧路换角度，避免一直站在中路对射。")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var map: some View {
        HStack(alignment: .top, spacing: 16) {
            ArenaSampleMapPreview().frame(width: 220, height: 275)
            ArenaMenuCard {
                Text("双闸交汇").font(.title2.bold())
                Text("抢占据点 · 蓝月港").foregroundStyle(.cyan)
                Text("中路快速到点，两侧绕行寻找夹击角度。利用暖金属掩体接近目标，留意草丛里的对手。")
                    .font(.subheadline)
                Text("金棕：墙体   绿色：草丛\n蓝点：己方出生   红点：对方出生\n中心白圈：实际据点范围")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                Text("21 × 29 格 · 三人对三人")
                    .font(.caption.bold())
            }
        }
    }
}

struct ArenaSampleMapPreview: View {
    private let map = ArenaMap.twinGates
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / CGFloat(map.width), size.height / CGFloat(map.height))
            let origin = CGPoint(x: (size.width - CGFloat(map.width) * unit) / 2,
                                 y: (size.height - CGFloat(map.height) * unit) / 2)
            for y in 0..<map.height {
                for x in 0..<map.width {
                    let color: Color
                    switch map.tile(x, y) {
                    case .wall: color = Color(red: 0.70, green: 0.52, blue: 0.30)
                    case .bush: color = Color(red: 0.25, green: 0.58, blue: 0.39)
                    default: color = Color(red: 0.20, green: 0.34, blue: 0.39)
                    }
                    let rect = CGRect(x: origin.x + CGFloat(x) * unit, y: origin.y + CGFloat(y) * unit,
                                      width: unit, height: unit)
                    context.fill(Path(rect), with: .color(color))
                }
            }
            let radius = CGFloat(ArenaGame.zoneRadius) * unit
            let center = CGPoint(x: origin.x + CGFloat(map.center.x) * unit,
                                 y: origin.y + CGFloat(map.center.y) * unit)
            context.stroke(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                  width: radius * 2, height: radius * 2)), with: .color(.white), lineWidth: 1.5)
            for (team, spawns) in map.spawns.enumerated() {
                for spawn in spawns {
                    let rect = CGRect(x: origin.x + CGFloat(spawn.x) * unit - 3,
                                      y: origin.y + CGFloat(spawn.y) * unit - 3, width: 6, height: 6)
                    context.fill(Path(ellipseIn: rect), with: .color(team == 0 ? .cyan : .red))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("双闸交汇地图：己方从下方出生，中间是据点，两侧有掩体与草丛可绕行")
    }
}
