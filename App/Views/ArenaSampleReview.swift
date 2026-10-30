import SwiftUI

/// Hero and map guides for the released Twin Gates match.
struct ArenaSampleReview: View {
    let onClose: () -> Void
    let onPlay: () -> Void
    let playHero: Brawler
    @State private var page: Int

    init(onClose: @escaping () -> Void, onPlay: @escaping () -> Void, initialPage: Int = 0, playHero: Brawler = .ranger) {
        self.onClose = onClose
        self.onPlay = onPlay
        self.playHero = playHero
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ArenaMenuScreen(title: "双闸交汇 · 作战指南", onClose: onClose, scrollContent: false) {
            GeometryReader { viewport in
                let previewHeight = max(1, viewport.size.height - 56)
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        pageButton(playHero.name, index: 0)
                        pageButton("双闸交汇", index: 1)
                    }
                    .accessibilityIdentifier("arena.sample.pages")
                    if page == 0 { hero(height: previewHeight) } else { map(height: previewHeight) }
                }
                .background(GeometryReader { proxy in
                    Color.clear.onAppear { markReady(proxy.size) }
                        .onChange(of: proxy.size) { size in markReady(size) }
                        .onChange(of: page) { _ in markReady(proxy.size) }
                })
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                Button(action: onPlay) {
                    Label("以\(playHero.name)开始对战", systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(ArenaMenuButtonStyle())
                .accessibilityIdentifier("arena.sample.play")
                Text("单人＋电脑队友 · 普通对战 · 正常结算奖杯、金币与赛季经验")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(ArenaMenuTheme.canvas)
        }
    }

    private func pageButton(_ title: String, index: Int) -> some View {
        Button { page = index } label: {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(ArenaMenuButtonStyle())
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(page == index ? Color.cyan : Color.clear, lineWidth: 2))
        .accessibilityIdentifier("arena.sample.page.\(index)")
        .accessibilityAddTraits(page == index ? .isSelected : [])
    }

    private func markReady(_ size: CGSize) {
        guard ProcessInfo.processInfo.arguments.contains("-demo"), size.width > 0, size.height > 0 else { return }
        let evidence: [String: Any] = ["scene": "sampleReview", "page": page,
            "width": size.width, "height": size.height, "map": ArenaMap.twinGates.id]
        guard let data = try? JSONSerialization.data(withJSONObject: evidence),
              let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? data.write(to: folder.appendingPathComponent("arena-sample-menu-ready.json"), options: .atomic)
    }

    private func hero(height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 4) {
                ArenaShowcase(brawler: playHero, qualitySample: true)
                    .frame(width: 220, height: max(1, height - 22))
                    .accessibilityIdentifier("arena.sample.hero")
                Text("拖动转身 · 轻点观看动作")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: 220, height: height, alignment: .top)
            ArenaMenuCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(playHero.name).font(.title2.bold())
                        Text(playHero.role)
                            .font(.subheadline).foregroundStyle(.cyan)
                        Text(playHero.attackNote).font(.subheadline)
                        Text(playHero.superNote).font(.subheadline)
                        Divider().overlay(.white.opacity(0.2))
                        Text("基础射程 \(playHero.attackRange, specifier: "%.0f") 格 · 每发装填 \(playHero.reload, specifier: "%.1f") 秒")
                            .font(.caption)
                        Text("利用短墙和草丛换角度；留意普攻、大招与敌人之间的距离。")
                            .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
    }

    private func map(height: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ArenaSampleMapPreview().frame(width: 220, height: height)
            ArenaMenuCard {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("双闸交汇").font(.title2.bold())
                        Text("抢占据点 · 蓝月港").foregroundStyle(.cyan)
                        Text("中路快速到点，两侧绕行寻找夹击角度。利用暖金属掩体接近目标，留意草丛里的对手。")
                            .font(.subheadline)
                        Text("金棕：墙体   绿色：草丛\n蓝点：己方出生   红点：对方出生\n中心白圈：实际据点范围")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                        Text("21 × 29 格 · 三人对三人")
                            .font(.caption.bold())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: height)
        }
        .frame(height: height)
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
