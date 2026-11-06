import SwiftUI

struct StarJourneyRewardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var store = StarRailStore.shared
    let reward: StarJourney.Reward
    var done: () -> Void
    @State private var displayedStars: Int
    init(reward:StarJourney.Reward,done:@escaping () -> Void) {
        self.reward=reward;self.done=done;_displayedStars=State(initialValue:reward.totalBefore)
    }
    private var newSkies: [StarRail.SkyTheme] {
        StarRail.SkyTheme.allCases.filter { $0.requiredStars > reward.totalBefore && $0.requiredStars <= reward.totalAfter }
    }
    private var newBacks: [StarRail.CardBack] {
        StarRail.CardBack.allCases.filter { $0.requiredStars > reward.totalBefore && $0.requiredStars <= reward.totalAfter }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:18) {
            HStack {
                VStack(alignment:.leading,spacing:6) {
                    Text("一段星河，已抵达。").font(.system(size:28,weight:.heavy,design:.rounded))
                    Text("三关合计 \(reward.score)/9 星 · \(reward.route.title)")
                        .font(.subheadline).foregroundStyle(TileTheme.mint)
                }
                Spacer(minLength:0);RailBrandMark(side:48)
            }.accessibilityIdentifier("journey.reward")
            Text(reward.earned > 0 ? "本次新获 \(reward.earned) 枚星章" : "本次完成旅程，最佳星级已保留")
                .font(.headline).foregroundStyle(TileTheme.gold).accessibilityIdentifier("journey.reward.stars")
            StarConstellationMap(earned:displayedStars)
            Text("累计 \(reward.totalAfter) 星章 · 已修复 \(StarRail.StarMap.restored(earned:reward.totalAfter))/12 颗星")
                .font(.subheadline.bold())
            if !newSkies.isEmpty || !newBacks.isEmpty {
                Text("刚刚解锁").font(.title3.bold())
                ForEach(newSkies,id:\.self) { sky in
                    HStack(spacing:12) {
                        RailSkyBackdrop(theme:sky).frame(width:56,height:44).clipShape(RoundedRectangle(cornerRadius:12))
                        Text(sky.title).font(.subheadline.bold());Spacer()
                        Button(store.sky == sky ? "已使用" : "使用天幕") { store.select(sky:sky) }
                            .disabled(store.sky == sky).accessibilityIdentifier("journey.unlock.sky.\(sky.rawValue)")
                    }
                }
                ForEach(newBacks,id:\.self) { back in
                    HStack(spacing:12) {
                        RailCardBack(style:back,side:44)
                        Text(back.title).font(.subheadline.bold());Spacer()
                        Button(store.cardBack == back ? "已使用" : "使用牌背") { store.select(back:back) }
                            .disabled(store.cardBack == back).accessibilityIdentifier("journey.unlock.back.\(back.rawValue)")
                    }
                }
            }
            if let next=StarRail.StarMap.next(earned:store.earnedStars) {
                Text("下一目标：再获 \(next-store.earnedStars) 枚星章，修复下一颗星。").font(.subheadline).foregroundStyle(TileTheme.mint)
            } else { Text("星图已经点亮，试试另一种能力与航线组合。").font(.subheadline).foregroundStyle(TileTheme.mint) }
            Button("收下奖励 · 选择下一次旅程",action:done).buttonStyle(TilePrimaryButton()).accessibilityIdentifier("journey.reward.done")
        }
        .task(id:reward.id) {
            if reduceMotion { displayedStars=reward.totalAfter;return }
            let steps=StarRail.StarMap.thresholds.filter { $0 > reward.totalBefore && $0 <= reward.totalAfter }
            for step in steps {
                do { try await Task.sleep(nanoseconds:150_000_000) } catch { return }
                guard !Task.isCancelled else { return }
                displayedStars=step
            }
            displayedStars=reward.totalAfter
        }
    }
}
