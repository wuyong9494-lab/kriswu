import SwiftUI

/// A value-only view: no live-game binding, tool callback, or record-store write.
struct TileReplayView: View {
    let replay: TileReplay
    @Environment(\.dismiss) private var dismiss
    @State private var step: Int
    @State private var before = false

    init(replay: TileReplay) {
        self.replay = replay
        _step = State(initialValue: replay.turningPoints.first ?? replay.actionCount)
    }

    private var frame: TileReplay.Frame { replay.frames[step] }
    private var previous: TileGame { replay.frames[max(0, step - 1)].game }
    private var boardGame: TileGame { before ? previous : frame.game }
    private var picked: TileGame.Tile? {
        guard case .pick(let id) = frame.action else { return nil }
        return (previous.board + previous.parked).first { $0.id == id }
    }
    private var actionTitle: String {
        switch frame.action {
        case .pick: return "取牌"
        case .undo: return "使用撤回"
        case .moveOut: return "使用移出"
        case .shuffle: return "使用洗牌"
        case nil: return "开局"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 8)
            GeometryReader { area in
                ScrollView {
                    VStack(spacing: 14) {
                        facts
                        Picker("对比这一步", selection: $before) {
                            Text("操作前").tag(true)
                            Text("操作后").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .disabled(step == 0)
                        .accessibilityIdentifier("tiles.replay.comparison")
                        board(in: CGSize(width: min(area.size.width - 32, 528),
                                         height: max(180, min(430, area.size.height - 230))))
                        trays
                        milestones
                        Text("金框标记所取的牌，绿框标记这一步新露出的牌。槽位紧张不代表这一步一定走错。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("这里只回看操作。关闭后回到原结算，首局结果不变。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                }
            }
            controls.padding(.horizontal, 16).padding(.vertical, 8)
                .background(TileTheme.panel)
        }
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .background(TileStarfield().ignoresSafeArea())
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onChange(of: step) { _ in before = false }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("逐步复盘").font(.title2.bold())
                Text("第 \(step) / \(replay.actionCount) 步 · \(actionTitle)")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("tiles.replay.step")
            }
            Spacer()
            Button("关闭") { dismiss() }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("tiles.replay.close")
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let picked {
                    TileFace(kind: picked.kind, side: 36)
                    Text("取出\(TileTheme.names[picked.kind % TileTheme.names.count])")
                } else {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(TileTheme.mint)
                    Text(actionTitle)
                }
                Spacer()
                Text("槽位 \(previous.waiting) → \(frame.game.waiting)/7")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(frame.game.waiting >= 5 ? TileTheme.gold : TileTheme.mint)
            }
            Text(step == 0 ? "回看自己这一局的操作" : "消除 \(frame.clearedChange) 张 · 新增 \(frame.exposedIDs.count) 张可取牌")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(TileTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private func board(in size: CGSize) -> some View {
        let game = boardGame
        let unit = max(1, min(size.width / CGFloat(TileGame.width), size.height / CGFloat(max(1, game.height))))
        let side = max(1, unit * CGFloat(TileGame.size) - 1)
        let free = game.freeIDs
        let tiles = game.board.sorted { ($0.z, $0.y, $0.x) < ($1.z, $1.y, $1.x) }
        return ZStack(alignment: .topLeading) {
            ForEach(tiles) { tile in
                let selected = before && picked?.id == tile.id
                let exposed = !before && frame.exposedIDs.contains(tile.id)
                TileFace(kind: tile.kind, side: side, covered: !free.contains(tile.id))
                    .overlay(RoundedRectangle(cornerRadius: side * 0.2)
                        .strokeBorder(selected ? TileTheme.gold : exposed ? TileTheme.mint : .clear, lineWidth: 2))
                    .position(x: (CGFloat(tile.x) + 2) * unit, y: (CGFloat(tile.y) + 2) * unit)
            }
        }
        .frame(width: unit * CGFloat(TileGame.width), height: unit * CGFloat(game.height))
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tiles.replay.board")
    }

    private var trays: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !boardGame.parked.isEmpty {
                HStack {
                    Text("移出区").font(.caption)
                    ForEach(boardGame.parked) { tile in TileFace(kind: tile.kind, side: 32) }
                }
            }
            HStack {
                Text(before ? "操作前的收集槽" : "操作后的收集槽")
                Spacer()
                Text("\(boardGame.waiting)/7").monospacedDigit()
                    .accessibilityIdentifier("tiles.replay.trayCount")
            }
            .font(.caption).foregroundStyle(.secondary)
            GeometryReader { area in
                let side = min(52, max(1, (area.size.width - 36) / 7))
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { index in
                        if index < boardGame.tray.count {
                            let tile = boardGame.tray[index]
                            TileFace(kind: tile.kind, side: side)
                                .overlay(RoundedRectangle(cornerRadius: side * 0.2)
                                    .strokeBorder(picked?.id == tile.id ? TileTheme.gold : .clear, lineWidth: 2))
                        } else {
                            RoundedRectangle(cornerRadius: side * 0.2).fill(.white.opacity(0.06))
                                .frame(width: side, height: side)
                        }
                    }
                }
            }
            .frame(height: 52)
        }
        .padding(12)
        .background(TileTheme.panel, in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { Double(step) }, set: { step = Int($0) }),
                   in: 0...Double(max(1, replay.actionCount)), step: 1)
                .disabled(replay.actionCount == 0)
                .tint(TileTheme.mint)
                .accessibilityLabel("复盘步数")
            HStack {
                Button { step = max(0, step - 1) } label: {
                    Label("上一步", systemImage: "chevron.left")
                }
                .disabled(step == 0).accessibilityIdentifier("tiles.replay.previous")
                Spacer()
                Button { step = min(replay.actionCount, step + 1) } label: {
                    Label("下一步", systemImage: "chevron.right")
                }
                .disabled(step == replay.actionCount).accessibilityIdentifier("tiles.replay.next")
            }
            .buttonStyle(.bordered).frame(minHeight: 44)
        }
    }
    @ViewBuilder private var milestones: some View {
        if !replay.turningPoints.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(replay.turningPoints, id: \.self) { index in
                        let state = replay.frames[index].game
                        Button("第 \(index) 步 · \(state.waiting)/7") { step = index }
                            .buttonStyle(.bordered)
                            .tint(step == index ? TileTheme.gold : TileTheme.mint)
                    }
                }
            }
            .accessibilityLabel("槽位紧张或使用道具的步骤")
        }
    }
}
