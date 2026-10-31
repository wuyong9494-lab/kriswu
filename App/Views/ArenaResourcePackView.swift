import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let arenaResourcePack = UTType(exportedAs: "com.kriswu.arena-resource-pack", conformingTo: .data)
}

struct ArenaResourcePackView: View {
    let onClose: () -> Void
    var onSelectHero: ((ArenaSourceHero) -> Void)?
    var onProjectHeroes: (() -> Void)?
    @ObservedObject private var store = ArenaResourcePackStore.shared
    @State private var page = Page.heroes
    @State private var picking = false
    @State private var selectedMap: ArenaResourcePackManifest.Map?
    @State private var importError: String?
    private enum Page: String, CaseIterable { case heroes = "英雄资源", maps = "地图布局", themes = "大厅主题", music = "音乐" }

    var body: some View {
        ArenaMenuScreen(title: "原版资源", onClose: onClose, scrollContent: false) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if let manifest = store.manifest {
                        Text("\(manifest.heroes.count) 条英雄配置 · \(manifest.maps.count) 个布局 · \(manifest.music.count) 首音乐")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    } else if store.hasBundledPack {
                        Text(store.error == nil ? "正在自动准备内置资源…" : "内置资源暂未加载完成")
                            .font(.subheadline)
                    } else {
                        Text("此版本尚未包含内置的原版资源。")
                            .font(.subheadline)
                    }
                    Spacer()
                    if let onProjectHeroes {
                        Button("项目英雄", action: onProjectHeroes).buttonStyle(ArenaMenuButtonStyle())
                    }
                    if store.hasBundledPack, store.error != nil {
                        Button("重新加载") {
                            Task { await store.loadBundledPackIfNeeded() }
                        }.buttonStyle(ArenaMenuButtonStyle()).disabled(store.preparingResources)
                    }
                    Menu("更多") {
                        Button("从文件导入其他资源包") { picking = true }
                    }.buttonStyle(ArenaMenuButtonStyle()).disabled(store.preparingResources)
                }
                if store.preparingResources {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: store.importing ? store.progress : nil).tint(.cyan)
                        Text(store.importing ? "正在准备资源 · \(Int(store.progress * 100))%" : "正在检查内置资源…")
                            .font(.caption).foregroundStyle(.white.opacity(0.8))
                    }
                }
                if let error = store.error ?? importError { Text(error).font(.caption).foregroundStyle(.orange) }
                if let error = store.lobbySceneError {
                    HStack {
                        Text(error).font(.caption).foregroundStyle(.orange)
                        Button("重新加载大厅动画") { store.retryLobbyScene() }
                            .buttonStyle(ArenaMenuButtonStyle())
                    }
                }
                if let manifest = store.manifest {
                    Picker("资源类别", selection: $page) {
                        ForEach(Page.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                    Group {
                        switch page {
                        case .heroes: heroes(manifest)
                        case .maps: maps(manifest)
                        case .themes: themes(manifest)
                        case .music: music(manifest)
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: store.hasBundledPack ? "shippingbox.fill" : "arrow.down.app")
                            .font(.system(size: 34))
                        Text(store.hasBundledPack
                             ? "大厅、英雄、地图和音乐已随 App 提供，首次进入时会自动准备，无需选择文件。"
                             : "更新到含内置资源的版本后，大厅、英雄、地图和音乐会自动加载。")
                            .multilineTextAlignment(.center)
                    }.frame(maxWidth: 460)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.white.opacity(0.75)).font(.subheadline)
                    Spacer()
                }
            }
        }
        .fileImporter(isPresented: $picking, allowedContentTypes: [.arenaResourcePack, .data], allowsMultipleSelection: false) { result in
            do {
                if let url = try result.get().first {
                    importError = nil
                    Task { await store.install(from: url) }
                }
            } catch { importError = error.localizedDescription }
        }
        .task {
            await store.loadBundledPackIfNeeded()
            chooseFirstHero()
        }
        .onChange(of: store.manifest?.id) { _ in chooseFirstHero() }
        .sheet(item: $selectedMap) { map in ArenaResourceMapView(map: map) }
    }

    private func chooseFirstHero() {
        guard store.selectedHero == nil, let heroes = store.manifest?.heroes,
              let first = heroes.first(where: { $0.id == ArenaImportedCombatAssets.shared.playable.first?.id })
                ?? heroes.first(where: { $0.faceComposed && $0.modelFile != nil }) ?? heroes.first(where: { $0.modelFile != nil }) else { return }
        store.selectHero(id: first.id)
    }

    private func heroes(_ manifest: ArenaResourcePackManifest) -> some View {
        let playable = Set(ArenaImportedCombatAssets.shared.playable.map(\.id))
        let ordered = manifest.heroes.sorted {
            if playable.contains($0.id) != playable.contains($1.id) { return playable.contains($0.id) }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return HStack(alignment: .top, spacing: 12) {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(ordered) { hero in
                        Button { store.selectHero(id: hero.id) } label: {
                            HStack {
                                Text(hero.name).multilineTextAlignment(.leading)
                                Spacer()
                                if playable.contains(hero.id) { Image(systemName: "play.circle.fill").foregroundStyle(.green) }
                                if hero.id == store.selectedHeroID { Image(systemName: "checkmark") }
                            }.padding(9).frame(maxWidth: .infinity, minHeight: 40)
                        }.buttonStyle(ArenaMenuButtonStyle()).disabled(hero.modelFile == nil)
                    }
                }
            }.frame(width: 165)
            if let hero = store.selectedHero, let file = hero.modelFile, let url = store.url(for: file) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(hero.name).font(.title3.bold())
                    ArenaImportedHeroView(url: url, name: hero.name, idleAnimation: hero.idleAnimation,
                                          heroID: hero.id,
                                          live: !picking && !store.importing)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Text("左右拖动查看").font(.caption)
                    if let profile = ArenaImportedCombatAssets.shared.hero(id: hero.id), profile.canPlay {
                        Text("生命 \(profile.health) · 移速 \(profile.speed, specifier: "%.2f") · 弹药 \(profile.weapon?.ammoCapacity ?? 0)")
                            .font(.caption)
                        Button("选择\(hero.name)对战") {
                            store.selectCombatHero(id: hero.id)
                            if let onSelectHero { onSelectHero(profile) } else { onClose() }
                        }.buttonStyle(ArenaMenuButtonStyle())
                    } else {
                        Text("模型与动作可查看；特殊技能规则仍在适配，暂未开放对战。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(hero.notes, id: \.self) { note in
                        Text(note).font(.caption2).foregroundStyle(.white.opacity(0.75))
                    }
                }
            } else {
                Text("选择一个有模型的角色").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func maps(_ manifest: ArenaResourcePackManifest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("已适配的地图可在大厅的地图选择中进入对战；这里同时保留所有已读取的原始布局。")
                    .font(.caption).foregroundStyle(.orange)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 10) {
                    ForEach(manifest.maps) { map in
                        Button { selectedMap = map } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(map.title).font(.headline)
                                Text("\(map.width) × \(map.height) · 查看布局").font(.caption)
                            }.frame(maxWidth: .infinity, minHeight: 62, alignment: .leading).padding(10)
                        }.buttonStyle(ArenaMenuButtonStyle())
                    }
                }
            }
        }
    }

    private func themes(_ manifest: ArenaResourcePackManifest) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("在大厅使用原版背景和音乐", isOn: Binding(get: { store.enabled }, set: { store.setEnabled($0) }))
                Text(manifest.themes.contains(where: { $0.sceneFile != nil })
                     ? "选择后用于大厅，背景随原资源的动画时间轴播放。"
                     : "当前资源包提供静态背景；大厅按钮操作当前 App 的实际功能。")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180))], spacing: 12) {
                    ForEach(manifest.themes) { theme in
                        Button { store.selectTheme(id: theme.id) } label: {
                            VStack(spacing: 8) {
                                if let url = store.url(for: theme.backgroundFile), let image = UIImage(contentsOfFile: url.path) {
                                    Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 110)
                                }
                                Label(theme.title, systemImage: store.currentTheme?.id == theme.id ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline)
                            }.padding(8).frame(maxWidth: .infinity)
                        }.buttonStyle(ArenaMenuButtonStyle())
                    }
                }
            }
        }
    }

    private func music(_ manifest: ArenaResourcePackManifest) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("选择后立即用于大厅，音量和静音沿用现有声音设置。")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                Button("跟随大厅主题") { store.selectLobbyMusic(id: nil) }.buttonStyle(ArenaMenuButtonStyle())
                ForEach(manifest.music) { track in
                    Button { store.setEnabled(true); store.selectLobbyMusic(id: track.id) } label: {
                        HStack {
                            Image(systemName: store.music(for: "lobby")?.track.id == track.id ? "speaker.wave.2.fill" : "music.note")
                            Text(track.title).lineLimit(2)
                            Spacer()
                            Text("用于大厅").font(.caption)
                        }.padding(10).frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(ArenaMenuButtonStyle())
                }
            }
        }
    }
}

private struct ArenaResourceMapView: View {
    let map: ArenaResourcePackManifest.Map
    @Environment(\.dismiss) private var dismiss
    @State private var layout: ArenaResourceMapLayout?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if let layout {
                    Canvas { context, size in
                        let cell = min(size.width / CGFloat(map.width), size.height / CGFloat(map.height))
                        let origin = CGPoint(x: (size.width - cell * CGFloat(map.width)) / 2, y: (size.height - cell * CGFloat(map.height)) / 2)
                        for (y, row) in layout.rows.enumerated() {
                            for (x, symbol) in row.enumerated() {
                                let tile = layout.legend[String(symbol)]
                                let color: Color
                                if let tile {
                                    color = tile.water ? .blue : tile.bush ? .green : tile.blocksMovement ? .brown : Color(white: 0.82)
                                } else { color = .purple }
                                let rect = CGRect(x: origin.x + CGFloat(x) * cell, y: origin.y + CGFloat(y) * cell, width: cell + 0.2, height: cell + 0.2)
                                context.fill(Path(rect), with: .color(color))
                            }
                        }
                    }
                    Text("棕色：阻挡移动 · 绿色：草丛 · 蓝色：水域 · 紫色：含义待确认")
                        .font(.caption).multilineTextAlignment(.center)
                    Text("布局预览，不代表原版环境画面或已经可玩。\(map.unresolvedCells) 个格子的规则待确认。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                } else { Text(error ?? "正在读取布局…") }
            }.padding().navigationTitle(map.title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .task {
            do {
                guard let url = ArenaResourcePackStore.shared.url(for: map.layoutFile) else { throw CocoaError(.fileNoSuchFile) }
                let value = try JSONDecoder().decode(ArenaResourceMapLayout.self, from: Data(contentsOf: url))
                try value.validate(width: map.width, height: map.height)
                guard value.id == map.id else { throw ArenaResourcePackManifest.ValidationError.invalid("地图标识不匹配") }
                layout = value
            } catch { self.error = "地图布局暂时无法显示" }
        }
    }
}
