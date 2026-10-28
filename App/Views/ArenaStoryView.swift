import SwiftUI

// MARK: - 冒险地图

/// 冒险：三章左右翻，每章一条路上四关（过了的写着几颗星，下一关在闪，后面的锁着）。
/// 点一关看这一关打谁、和谁一起、三颗星要做到什么；开打前、打赢后放对话
struct ArenaStoryView: View {
    /// 上场用的角色（大厅里选的）、一对一另外带的两个
    let brawler: Brawler
    let partners: [Brawler]
    let name: String
    /// 截图用：一打开就放第一关开打前的对话
    var showIntro = false
    @ObservedObject private var growth = ArenaProgressStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var chapter = 1
    @State private var selected: ArenaStory.Level?
    @State private var talk: Talk?
    @State private var playing: ArenaHomeView.ArenaEntry?
    /// 正在打的那一关、开打前最近一次打完的记录（打完回来看要不要放打赢后的对话）
    @State private var current: ArenaStory.Level?
    @State private var lastBefore: ArenaProgressStore.StoryResult?

    /// 一段对话，说完了做什么
    struct Talk: Identifiable {
        let id = UUID()
        let lines: [ArenaStory.Line]
        /// 说完了开打这一关（nil：说完就回地图）
        let then: ArenaStory.Level?
    }

    private var progress: ArenaProgress { growth.progress }

    var body: some View {
        ZStack {
            background(for: chapter)
            VStack(spacing: 0) {
                topBar
                TabView(selection: $chapter) {
                    ForEach(ArenaStory.chapters) { item in
                        chapterPage(item).tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }
            if let level = selected {
                levelCard(level)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
            if let talk {
                ArenaDialogue(lines: talk.lines) {
                    self.talk = nil
                    if let level = talk.then { start(level) }
                }
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selected)
        .animation(.easeOut(duration: 0.25), value: talk?.id)
        .modifier(ArenaLandscape())
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            // 翻到还没打完的那一章
            if let open = ArenaStory.levels.last(where: { progress.isOpen($0.id) }), let chapter = ArenaStory.chapter(of: open.id) {
                self.chapter = chapter.id
            }
            if showIntro, let first = ArenaStory.levels.first {
                talk = Talk(lines: first.before, then: nil)
            }
        }
        .fullScreenCover(item: $playing, onDismiss: finished) { entry in
            ArenaPlayView(setup: entry.setup)
        }
    }

    private var topBar: some View {
        HStack(spacing: DS.Space.s) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left").font(.headline).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(.black.opacity(0.3), in: Circle())
            }
            .accessibilityLabel("回大厅")
            Text("冒险")
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .arenaOutline(2)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "star.fill").foregroundStyle(Color(uiColor: ArenaPalette.gold))
                Text("\(progress.totalStoryStars)/\(ArenaStory.levels.count * 3)")
            }
            .font(.system(size: 16, weight: .black, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.black.opacity(0.3), in: Capsule())
            HStack(spacing: 6) {
                BrawlerBadge(brawler: brawler, size: 28)
                Text("\(brawler.name) \(progress.level(brawler)) 级")
            }
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .arenaInk()
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(.black.opacity(0.3), in: Capsule())
        }
        .padding(.horizontal, DS.Space.l)
        .padding(.top, DS.Space.s)
    }

    // MARK: 一章

    /// 一章的底色：草原绿、森林青、墓地紫
    private func background(for chapter: Int) -> some View {
        let colors: [Color]
        switch chapter {
        case 1: colors = [Color(red: 0.42, green: 0.75, blue: 0.95), Color(red: 0.38, green: 0.7, blue: 0.3)]
        case 2: colors = [Color(red: 0.12, green: 0.35, blue: 0.38), Color(red: 0.1, green: 0.42, blue: 0.24)]
        default: colors = [Color(red: 0.26, green: 0.14, blue: 0.4), Color(red: 0.14, green: 0.1, blue: 0.22)]
        }
        return LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: chapter)
    }

    private func chapterPage(_ item: ArenaStory.Chapter) -> some View {
        GeometryReader { geo in
            let spots = item.levels.indices.map { k in
                CGPoint(x: geo.size.width * (0.13 + 0.245 * CGFloat(k)), y: geo.size.height * (k % 2 == 0 ? 0.62 : 0.36))
            }
            ZStack {
                VStack(spacing: 2) {
                    Text("第 \(item.id) 章 · \(item.title)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1.8)
                    Text(item.place)
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .arenaInk()
                }
                .position(x: geo.size.width / 2, y: 26)
                // 关和关之间的小路
                Path { path in
                    guard let first = spots.first else { return }
                    path.move(to: first)
                    for (a, b) in zip(spots, spots.dropFirst()) {
                        path.addQuadCurve(to: b, control: CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 30))
                    }
                }
                .stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [2, 14]))
                ForEach(Array(item.levels.enumerated()), id: \.element.id) { k, level in
                    levelNode(level)
                        .position(spots[k])
                }
                recruitNote(item)
                    .position(x: geo.size.width / 2, y: geo.size.height - 30)
            }
        }
        .padding(.bottom, 26)
    }

    private func levelNode(_ level: ArenaStory.Level) -> some View {
        let open = progress.isOpen(level.id)
        let stars = progress.stars(level.id)
        let next = open && stars == 0
        return Button {
            selected = level
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(open ? level.mode.tint : Color.gray.opacity(0.7))
                    Circle().strokeBorder(.black.opacity(0.7), lineWidth: 3)
                    if open {
                        Image(systemName: level.mode == .boss ? "crown.fill" : level.mode.icon)
                            .font(.system(size: 22, weight: .black))
                            .foregroundStyle(.white)
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 20, weight: .black)).foregroundStyle(.white.opacity(0.85))
                    }
                }
                .frame(width: level.mode == .boss ? 74 : 62, height: level.mode == .boss ? 74 : 62)
                .overlay {
                    if next {
                        Circle().strokeBorder(Color(uiColor: ArenaPalette.gold), lineWidth: 4).padding(-6)
                    }
                }
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { k in
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(k < stars ? Color(uiColor: ArenaPalette.gold) : .black.opacity(0.3))
                    }
                }
                Text("\(level.id) \(level.title)")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .arenaOutline(1)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .buttonStyle(.plain)
        .disabled(!open)
        .accessibilityLabel("\(level.id) \(level.title)，" + (open ? "\(stars) 颗星" : "还没开"))
    }

    /// 这一章打完谁会加入
    private func recruitNote(_ item: ArenaStory.Chapter) -> some View {
        let done = item.levels.last.map { progress.stars($0.id) > 0 } ?? false
        return HStack(spacing: 6) {
            Text(done ? "已经加入：" : "打完这一章加入：")
            ForEach(item.recruits, id: \.self) { recruit in
                BrawlerBadge(brawler: recruit, size: 26)
                Text(recruit.name)
            }
        }
        .font(.system(size: 13, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .arenaInk()
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(.black.opacity(0.28), in: Capsule())
    }

    // MARK: 一关

    private func levelCard(_ level: ArenaStory.Level) -> some View {
        let stars = progress.stars(level.id)
        let map = ArenaMap.named(level.map)?.title ?? ""
        return ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { selected = nil }
            VStack(spacing: DS.Space.s) {
                HStack {
                    Text("\(level.id) \(level.title)")
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .arenaOutline(1.8)
                    Spacer()
                    Button {
                        selected = nil
                    } label: {
                        Image(systemName: "xmark").font(.headline).foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
                HStack(spacing: 8) {
                    Image(systemName: level.mode.icon)
                    Text("\(level.mode.title) · \(map)")
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: DS.Space.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("对手").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                        HStack(spacing: 4) {
                            if level.mode == .boss {
                                BrawlerBadge(brawler: .guardian, size: 40)
                                    .overlay(alignment: .top) { Text("👑").font(.system(size: 14)).offset(y: -10) }
                                Text("骷髅王 \(level.bossLevel ?? level.enemyLevel) 级")
                            } else {
                                ForEach(Array(level.enemies.enumerated()), id: \.offset) { _, enemy in
                                    BrawlerBadge(brawler: enemy, size: 36)
                                }
                                Text("\(level.enemyLevel) 级")
                            }
                        }
                        if !level.allies.isEmpty {
                            Text("队友").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                            HStack(spacing: 4) {
                                ForEach(Array(level.allies.prefix(level.mode.seatTeams.filter { $0 == 0 }.count - 1).enumerated()), id: \.offset) { _, ally in
                                    BrawlerBadge(brawler: ally, size: 36)
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("三颗星").font(.system(size: 12, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.7))
                        goalRow(1, "赢下这一关", done: stars >= 1)
                        goalRow(2, "一次没被打倒", done: stars >= 2)
                        goalRow(3, level.goal.note, done: stars >= 3)
                        Text(stars == 0 ? "第一次过关 \(level.coins) 金币，每颗星再给 \(ArenaStory.coinsPerStar)" : "多拿一颗星给 \(ArenaStory.coinsPerStar) 金币")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                HStack(spacing: DS.Space.s) {
                    Text("上场：\(brawler.name) \(progress.level(brawler)) 级")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    Button("开打") {
                        selected = nil
                        talk = Talk(lines: level.before, then: level)
                    }
                    .buttonStyle(ArenaGameButton(face: ArenaGameButton.yellow.face, edge: ArenaGameButton.yellow.edge, height: 50))
                }
            }
            .padding(DS.Space.l)
            .frame(maxWidth: 560)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(red: 0.08, green: 0.1, blue: 0.2).opacity(0.92))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(level.mode.tint, lineWidth: 3))
            )
            .padding(DS.Space.l)
        }
    }

    private func goalRow(_ count: Int, _ text: String, done: Bool) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { _ in
                    Image(systemName: "star.fill").font(.system(size: 11, weight: .black))
                }
            }
            .foregroundStyle(done ? Color(uiColor: ArenaPalette.gold) : .white.opacity(0.35))
            .frame(width: 40, alignment: .leading)
            Text(text)
            if done {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(uiColor: ArenaPalette.myName))
            }
        }
    }

    // MARK: 开打、打完

    private func start(_ level: ArenaStory.Level) {
        current = level
        lastBefore = growth.lastStory
        playing = ArenaHomeView.ArenaEntry(setup: ArenaController.Setup(
            mode: level.mode, brawler: brawler, name: name, level: progress.level(brawler),
            lineup: [brawler] + partners, loadout: progress.loadout(for: brawler), story: level))
    }

    /// 一局关掉了：这一关赢了就放打赢后的对话
    private func finished() {
        guard let level = current else { return }
        current = nil
        // 这次真的打完了（中途退出不算）、赢了
        if let last = growth.lastStory, last != lastBefore, last.level == level.id, last.stars > 0 {
            talk = Talk(lines: level.after, then: nil)
            // 翻到下一关所在的那一章
            if let next = ArenaStory.next(after: level.id), let chapter = ArenaStory.chapter(of: next.id) {
                self.chapter = chapter.id
            }
        }
    }
}

// MARK: - 对话

/// 对话：下面一个对话框，左边说话的人的头像和名字，字一个一个出来；点一下出完、再点下一句，右上角能跳过
struct ArenaDialogue: View {
    let lines: [ArenaStory.Line]
    var onFinish: () -> Void
    @State private var index = 0
    @State private var shown = 0
    @State private var typing: Task<Void, Never>?

    private var line: ArenaStory.Line? { lines.indices.contains(index) ? lines[index] : nil }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.5).ignoresSafeArea()
            if let line {
                box(line)
                    .padding(.horizontal, DS.Space.l)
                    .padding(.bottom, DS.Space.l)
                    .id(index)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            Button("跳过") { finish() }
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background(.white.opacity(0.18), in: Capsule())
                .padding(DS.Space.m)
        }
        .contentShape(Rectangle())
        .onTapGesture { advance() }
        .onAppear { type() }
        .onDisappear { typing?.cancel() }
        .animation(.easeOut(duration: 0.2), value: index)
    }

    private func box(_ line: ArenaStory.Line) -> some View {
        let text = Array(line.text)
        let visible = String(text.prefix(shown))
        return HStack(alignment: .top, spacing: DS.Space.m) {
            if line.speaker != .narrator {
                portrait(line.speaker)
            }
            VStack(alignment: .leading, spacing: 6) {
                if line.speaker != .narrator {
                    Text(line.speaker.name)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(color(line.speaker))
                        .arenaOutline(1.2)
                }
                // 先用整句占好位置，字一个个盖上去（框不跟着字变高）
                ZStack(alignment: .topLeading) {
                    Text(line.text).opacity(0)
                    Text(visible)
                }
                .font(.system(size: 19, weight: line.speaker == .narrator ? .bold : .heavy, design: .rounded))
                .italic(line.speaker == .narrator)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: line.speaker == .narrator ? .center : .leading)
                .multilineTextAlignment(line.speaker == .narrator ? .center : .leading)
                HStack {
                    Spacer()
                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundStyle(.white.opacity(shown >= text.count ? 0.8 : 0))
                }
            }
        }
        .padding(DS.Space.m)
        .frame(maxWidth: 720)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.18).opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(color(line.speaker).opacity(0.85), lineWidth: 3))
        )
    }

    @ViewBuilder private func portrait(_ speaker: ArenaStory.Speaker) -> some View {
        switch speaker {
        case .brawler(let brawler):
            BrawlerBadge(brawler: brawler, size: 76)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        case .king:
            BrawlerBadge(brawler: .guardian, size: 76)
                .overlay(Circle().strokeBorder(Color(red: 0.75, green: 0.2, blue: 0.3), lineWidth: 4))
                .overlay(alignment: .top) { Text("👑").font(.system(size: 26)).offset(y: -16) }
        case .elder:
            Text("👴")
                .font(.system(size: 44))
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color(red: 0.95, green: 0.85, blue: 0.6)))
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
        case .narrator:
            EmptyView()
        }
    }

    private func color(_ speaker: ArenaStory.Speaker) -> Color {
        switch speaker {
        case .brawler(let brawler): return brawler.unlockAt == 0 ? Color(uiColor: ArenaPalette.allyName) : Color(red: 0.75, green: 0.95, blue: 0.7)
        case .king: return Color(red: 1, green: 0.42, blue: 0.4)
        case .elder: return Color(uiColor: ArenaPalette.gold)
        case .narrator: return .white.opacity(0.6)
        }
    }

    /// 一个字一个字地出来
    private func type() {
        typing?.cancel()
        shown = 0
        let count = line.map { Array($0.text).count } ?? 0
        typing = Task { @MainActor in
            while shown < count {
                try? await Task.sleep(nanoseconds: 32_000_000)
                if Task.isCancelled { return }
                shown += 1
            }
        }
    }

    private func advance() {
        let count = line.map { Array($0.text).count } ?? 0
        if shown < count {
            typing?.cancel()
            shown = count
            return
        }
        if index + 1 < lines.count {
            index += 1
            type()
        } else {
            finish()
        }
    }

    private func finish() {
        typing?.cancel()
        onFinish()
    }
}
