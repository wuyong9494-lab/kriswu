import SwiftUI

struct StarCollectionView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = StarRailStore.shared
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("把星空，\n一颗颗点亮。").font(.system(size: 32, weight: .heavy, design: .rounded))
                            Text("累计 \(store.earnedStars) 星章").font(.headline).foregroundStyle(TileTheme.gold)
                        }
                        Spacer(); RailBrandMark()
                    }
                    StarConstellationMap(earned:store.earnedStars)
                    if let next = StarRail.StarMap.next(earned: store.earnedStars) {
                        Text("再获 \(next-store.earnedStars) 枚星章，修复下一颗星。").font(.subheadline).foregroundStyle(TileTheme.mint)
                    } else { Text("十二颗星已全部修复。继续挑战你的最佳航线。").font(.subheadline).foregroundStyle(TileTheme.gold) }
                    Text("旅程、主线、星约和远征的最佳星级累计修复星图；同一关反复通关不会重复获得星章。外观不改变规则和难度。")
                        .font(.caption).foregroundStyle(.white.opacity(0.6)).lineSpacing(4)
                    Text("航行天幕").font(.title3.bold())
                    ForEach(StarRail.SkyTheme.allCases, id: \.self) { sky in skyChoice(sky) }
                    Text("星牌边框与背纹").font(.title3.bold())
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(StarRail.CardBack.allCases, id: \.self) { back in backChoice(back) }
                    }
                }.padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(RailSkyBackdrop(theme: store.sky).ignoresSafeArea())
            .navigationTitle("星图修复").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("返回") { dismiss() }.accessibilityIdentifier("collection.close") } }
        }.foregroundStyle(.white).preferredColorScheme(.dark)
    }
    private func skyChoice(_ sky: StarRail.SkyTheme) -> some View {
        let unlocked = store.earnedStars >= sky.requiredStars
        return Button { store.select(sky: sky) } label: {
            HStack(spacing: 14) {
                RailSkyBackdrop(theme: sky).frame(width: 60, height: 48).clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(sky.title).font(.subheadline.bold())
                    Text(unlocked ? "已解锁" : "\(sky.requiredStars) 星章解锁").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Image(systemName: store.sky == sky ? "checkmark.circle.fill" : unlocked ? "circle" : "lock.fill").foregroundStyle(TileTheme.mint)
            }.padding(12).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain).disabled(!unlocked).accessibilityIdentifier("collection.sky.\(sky.rawValue)")
    }
    private func backChoice(_ back: StarRail.CardBack) -> some View {
        let unlocked = store.earnedStars >= back.requiredStars
        return Button { store.select(back: back) } label: {
            VStack(spacing: 12) {
                HStack(spacing: 5) {
                    RailCardBack(style: back, side: 46).rotationEffect(.degrees(-8))
                    RailTileFace(kind: 5, side: 46, covered: false, rail: nil, layer: 0, anchor: false, back: back)
                }.frame(height: 64)
                Label(back.title, systemImage: store.cardBack == back ? "checkmark.circle.fill" : unlocked ? "circle" : "lock.fill")
                    .font(.subheadline.bold()).foregroundStyle(StarRailStyle.accent(back))
                Text(unlocked ? "已解锁" : "\(back.requiredStars) 星章解锁").font(.caption).foregroundStyle(.white.opacity(0.55))
            }.frame(maxWidth: .infinity).padding(.vertical, 16).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain).disabled(!unlocked).accessibilityIdentifier("collection.back.\(back.rawValue)")
    }
}

struct StarConstellationMap: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let earned: Int
    private let names = ["启航", "回声", "双子", "晨曦", "引力", "极光", "流星", "星云", "日珥", "银河", "天穹", "归航"]
    var body: some View {
        GeometryReader { geo in
            let points = [(0.12,0.15),(0.38,0.08),(0.65,0.18),(0.87,0.10),(0.80,0.42),(0.53,0.36),(0.27,0.43),(0.10,0.65),(0.36,0.78),(0.57,0.64),(0.86,0.74),(0.67,0.93)]
            ZStack {
                Canvas { context, size in
                    for i in 1..<points.count {
                        var path = Path()
                        path.move(to: CGPoint(x: points[i-1].0*size.width, y: points[i-1].1*size.height))
                        path.addLine(to: CGPoint(x: points[i].0*size.width, y: points[i].1*size.height))
                        let lit = earned >= StarRail.StarMap.thresholds[i]
                        context.stroke(path, with: .color(lit ? TileTheme.mint.opacity(0.65) : .white.opacity(0.12)), style: StrokeStyle(lineWidth: lit ? 2 : 1, dash: lit ? [] : [3,5]))
                    }
                }.accessibilityHidden(true)
                ForEach(0..<12, id: \.self) { index in
                    let lit = earned >= StarRail.StarMap.thresholds[index]
                    VStack(spacing: 3) {
                        Image(systemName: lit ? "star.fill" : "star").font(.system(size: lit ? 20 : 16))
                            .foregroundStyle(lit ? TileTheme.gold : .white.opacity(0.3))
                            .shadow(color: lit ? TileTheme.gold.opacity(0.5) : .clear, radius: 9)
                            .scaleEffect(lit ? 1 : 0.8)
                            .animation(reduceMotion ? nil : .spring(response:0.4,dampingFraction:0.6),value:lit)
                        Text(names[index]).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(lit ? 0.85 : 0.4))
                    }
                    .position(x: points[index].0*geo.size.width, y: points[index].1*geo.size.height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(names[index])，\(lit ? "已修复" : "需要 \(StarRail.StarMap.thresholds[index]) 星章")")
                }
            }
        }
        .frame(height: 300).padding(12).background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityIdentifier("collection.map")
    }
}
