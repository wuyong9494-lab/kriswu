import SwiftUI

// MARK: - 1. Native LaTeX Display Math Card (Zero-WebView, 60 FPS)

struct WuMindMathBlockView: View {
    let latex: String
    let pretty: String
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopy: (String) -> Void

    @State private var showRaw = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("公式", systemImage: "function")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.indigo)
                Spacer()
                Button {
                    showRaw.toggle()
                } label: {
                    Text(showRaw ? "排版" : "源码")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Button {
                    onCopy(latex)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                if showRaw {
                    Text(latex)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                } else {
                    Text(pretty)
                        .font(.system(size: 16.5, weight: .medium, design: .serif))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.24), lineWidth: 1)
        )
        .accessibilityIdentifier("wumind.rich.math")
    }
}

// MARK: - 2. Native Mermaid Diagram Renderer (Flowchart / Sequence / Pie — Offline & 60 FPS)

struct WuMindMermaidDiagramView: View {
    let source: String
    let diagram: WuMindMermaidDiagram
    let elevatedSurface: Color
    let subtleBorder: Color
    let onCopy: (String) -> Void

    @State private var showSource = false
    @State private var expandedFullScreen = false

    private var badgeTitle: String {
        switch diagram {
        case .flowchart(let dir, _, _): return dir == .leftRight ? "Mermaid 流程图（横向）" : "Mermaid 流程图"
        case .sequence: return "Mermaid 时序图"
        case .pie(let title, _): return "Mermaid 占比图 · \(title)"
        case .unsupported: return "Mermaid 图表源码"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Label(badgeTitle, systemImage: "point.3.connected.trianglepath.dotted")
                    .font(DS.Font.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                Button {
                    showSource.toggle()
                } label: {
                    Text(showSource ? "图形" : "源码")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                if !showSource {
                    Button {
                        expandedFullScreen = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(DS.Font.caption.weight(.semibold))
                            .foregroundStyle(DS.Palette.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("全屏查看图表")
                    .accessibilityIdentifier("wumind.rich.diagram.expand")
                }
                Button {
                    onCopy(source)
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(DS.Font.caption)
                        .foregroundStyle(DS.Palette.accent)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, DS.Space.xxs)
            .background(DS.Palette.surfaceSunken)

            if showSource {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(source)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(12)
                }
            } else {
                diagramBody
                    .padding(12)
            }
        }
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(subtleBorder, lineWidth: 1)
        )
        .sheet(isPresented: $expandedFullScreen) {
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    diagramBody
                        .padding(DS.Space.m)
                }
                .appBackground()
                .navigationTitle(badgeTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { expandedFullScreen = false }
                    }
                }
            }
        }
        .accessibilityIdentifier("wumind.rich.mermaid")
    }

    @ViewBuilder
    private var diagramBody: some View {
        switch diagram {
        case .flowchart(let dir, let nodes, let edges):
            WuMindFlowchartView(direction: dir, nodes: nodes, edges: edges)
        case .sequence(let actors, let messages):
            WuMindSequenceDiagramView(actors: actors, messages: messages)
        case .pie(_, let slices):
            WuMindPieDiagramView(slices: slices)
        case .unsupported:
            ScrollView(.horizontal, showsIndicators: false) {
                Text(source)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct WuMindFlowchartView: View {
    let direction: WuMindMermaidDiagram.Direction
    let nodes: [WuMindMermaidDiagram.FlowNode]
    let edges: [WuMindMermaidDiagram.FlowEdge]

    private var groupedLayers: [[WuMindMermaidDiagram.FlowNode]] {
        let maxLayer = nodes.map(\.layer).max() ?? 0
        return (0...maxLayer).compactMap { layer in
            let row = nodes.filter { $0.layer == layer }
            return row.isEmpty ? nil : row
        }
    }

    var body: some View {
        let layers = groupedLayers
        let boxW: CGFloat = 128
        let boxH: CGFloat = 46
        let hGap: CGFloat = 24
        let vGap: CGFloat = 42

        let maxBreadth = max(1, layers.map(\.count).max() ?? 1)
        let canvasW: CGFloat = direction == .leftRight
            ? CGFloat(layers.count) * (boxW + hGap) + 24
            : max(260, CGFloat(maxBreadth) * (boxW + hGap) + 24)
        let canvasH: CGFloat = direction == .leftRight
            ? max(140, CGFloat(maxBreadth) * (boxH + vGap) + 24)
            : CGFloat(layers.count) * (boxH + vGap) + 24

        let centers: [String: CGPoint] = {
            var map: [String: CGPoint] = [:]
            for (li, layerNodes) in layers.enumerated() {
                for (ni, node) in layerNodes.enumerated() {
                    if direction == .leftRight {
                        let x = 12 + boxW / 2 + CGFloat(li) * (boxW + hGap)
                        let totalH = CGFloat(layerNodes.count) * boxH + CGFloat(max(0, layerNodes.count - 1)) * vGap
                        let startY = (canvasH - totalH) / 2 + boxH / 2
                        let y = startY + CGFloat(ni) * (boxH + vGap)
                        map[node.id] = CGPoint(x: x, y: y)
                    } else {
                        let y = 12 + boxH / 2 + CGFloat(li) * (boxH + vGap)
                        let totalW = CGFloat(layerNodes.count) * boxW + CGFloat(max(0, layerNodes.count - 1)) * hGap
                        let startX = (canvasW - totalW) / 2 + boxW / 2
                        let x = startX + CGFloat(ni) * (boxW + hGap)
                        map[node.id] = CGPoint(x: x, y: y)
                    }
                }
            }
            return map
        }()

        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for edge in edges {
                        guard let from = centers[edge.from], let to = centers[edge.to] else { continue }
                        let start: CGPoint
                        let end: CGPoint
                        if direction == .leftRight {
                            start = CGPoint(x: from.x + boxW / 2, y: from.y)
                            end = CGPoint(x: to.x - boxW / 2, y: to.y)
                        } else {
                            start = CGPoint(x: from.x, y: from.y + boxH / 2)
                            end = CGPoint(x: to.x, y: to.y - boxH / 2)
                        }
                        var path = Path()
                        path.move(to: start)
                        let midX = (start.x + end.x) / 2
                        let midY = (start.y + end.y) / 2
                        if direction == .leftRight {
                            path.addCurve(to: end, control1: CGPoint(x: midX, y: start.y), control2: CGPoint(x: midX, y: end.y))
                        } else {
                            path.addCurve(to: end, control1: CGPoint(x: start.x, y: midY), control2: CGPoint(x: end.x, y: midY))
                        }
                        let style = StrokeStyle(lineWidth: 1.6, dash: edge.dashed ? [5, 4] : [])
                        context.stroke(path, with: .color(.teal.opacity(0.75)), style: style)

                        // Arrowhead
                        let angle = atan2(end.y - start.y, end.x - start.x)
                        var arrow = Path()
                        let sz: CGFloat = 6.5
                        arrow.move(to: end)
                        arrow.addLine(to: CGPoint(x: end.x - sz * cos(angle - 0.5), y: end.y - sz * sin(angle - 0.5)))
                        arrow.addLine(to: CGPoint(x: end.x - sz * cos(angle + 0.5), y: end.y - sz * sin(angle + 0.5)))
                        arrow.closeSubpath()
                        context.fill(arrow, with: .color(.teal))
                    }
                }
                .frame(width: canvasW, height: canvasH)

                ForEach(edges) { edge in
                    if let label = edge.label, !label.isEmpty,
                       let from = centers[edge.from], let to = centers[edge.to] {
                        Text(label)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .position(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
                    }
                }

                ForEach(nodes) { node in
                    if let pt = centers[node.id] {
                        nodeCard(node)
                            .frame(width: boxW, height: boxH)
                            .position(pt)
                    }
                }
            }
            .frame(width: canvasW, height: canvasH)
        }
    }

    private func nodeCard(_ node: WuMindMermaidDiagram.FlowNode) -> some View {
        let radius: CGFloat = {
            switch node.shape {
            case .circle: return 23
            case .rounded: return 14
            case .diamond: return 6
            case .rect: return 9
            }
        }()
        let tint: Color = node.shape == .diamond ? .orange : (node.shape == .circle ? .purple : .indigo)
        return Text(node.label)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(0.45), lineWidth: 1.2)
            )
    }
}

private struct WuMindSequenceDiagramView: View {
    let actors: [String]
    let messages: [WuMindMermaidDiagram.SequenceMessage]

    var body: some View {
        let colW: CGFloat = 104
        let topH: CGFloat = 38
        let rowH: CGFloat = 42
        let canvasW = max(260, CGFloat(actors.count) * colW + 24)
        let canvasH = topH + CGFloat(max(1, messages.count)) * rowH + 20

        ScrollView(.horizontal, showsIndicators: false) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for idx in actors.indices {
                        let x = 12 + colW * (CGFloat(idx) + 0.5)
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: topH))
                        line.addLine(to: CGPoint(x: x, y: canvasH - 8))
                        context.stroke(line, with: .color(.secondary.opacity(0.32)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    for (mi, msg) in messages.enumerated() {
                        guard let fi = actors.firstIndex(of: msg.from),
                              let ti = actors.firstIndex(of: msg.to) else { continue }
                        let x1 = 12 + colW * (CGFloat(fi) + 0.5)
                        let x2 = 12 + colW * (CGFloat(ti) + 0.5)
                        let y = topH + 22 + CGFloat(mi) * rowH
                        var arrowLine = Path()
                        arrowLine.move(to: CGPoint(x: x1, y: y))
                        arrowLine.addLine(to: CGPoint(x: x2, y: y))
                        context.stroke(arrowLine, with: .color(.indigo), style: StrokeStyle(lineWidth: 1.6, dash: msg.dashed ? [5, 3] : []))
                        let dir: CGFloat = x2 >= x1 ? 1 : -1
                        var head = Path()
                        head.move(to: CGPoint(x: x2, y: y))
                        head.addLine(to: CGPoint(x: x2 - dir * 7, y: y - 4))
                        head.addLine(to: CGPoint(x: x2 - dir * 7, y: y + 4))
                        head.closeSubpath()
                        context.fill(head, with: .color(.indigo))
                    }
                }
                .frame(width: canvasW, height: canvasH)

                ForEach(Array(actors.enumerated()), id: \.offset) { idx, name in
                    Text(name)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .position(x: 12 + colW * (CGFloat(idx) + 0.5), y: 18)
                }

                ForEach(Array(messages.enumerated()), id: \.element.id) { mi, msg in
                    if let fi = actors.firstIndex(of: msg.from),
                       let ti = actors.firstIndex(of: msg.to),
                       !msg.label.isEmpty {
                        let x1 = 12 + colW * (CGFloat(fi) + 0.5)
                        let x2 = 12 + colW * (CGFloat(ti) + 0.5)
                        let y = topH + 10 + CGFloat(mi) * rowH
                        Text(msg.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .position(x: (x1 + x2) / 2, y: y)
                    }
                }
            }
            .frame(width: canvasW, height: canvasH)
        }
    }
}

private struct WuMindPieDiagramView: View {
    let slices: [WuMindMermaidDiagram.PieSlice]

    private let palette: [Color] = [.indigo, .teal, .orange, .purple, .blue, .green, .pink, .yellow]

    var body: some View {
        let total = max(0.0001, slices.reduce(0) { $0 + $1.value })
        HStack(spacing: 16) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = min(size.width, size.height) / 2 - 4
                var startAngle = Angle.degrees(-90)
                for (idx, slice) in slices.enumerated() {
                    let sweep = Angle.degrees(360.0 * (slice.value / total))
                    var path = Path()
                    path.move(to: center)
                    path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: startAngle + sweep, clockwise: false)
                    path.closeSubpath()
                    context.fill(path, with: .color(palette[idx % palette.count]))
                    startAngle += sweep
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(slices.enumerated()), id: \.element.id) { idx, slice in
                    let pct = (slice.value / total) * 100
                    HStack(spacing: 6) {
                        Circle()
                            .fill(palette[idx % palette.count])
                            .frame(width: 8, height: 8)
                        Text(slice.label)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(String(format: "%.1f%%", pct))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - 3. Flagship Editorial Markdown Table Card (Scrollable, Zebra-Striped, 60 FPS)

struct WuMindMarkdownTableView: View {
    let headers: [String]
    let rows: [[String]]
    let elevatedSurface: Color
    let subtleBorder: Color

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                        tableCell(header, isHeader: true)
                            .frame(minWidth: 104, maxWidth: 220, alignment: .leading)
                        if idx < headers.count - 1 {
                            Rectangle()
                                .fill(subtleBorder)
                                .frame(width: 0.8)
                        }
                    }
                }
                .background(Color.indigo.opacity(0.11))

                ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                    Rectangle()
                        .fill(subtleBorder)
                        .frame(height: 0.8)
                    HStack(spacing: 0) {
                        ForEach(Array(headers.indices), id: \.self) { colIdx in
                            let val = colIdx < row.count ? row[colIdx] : ""
                            tableCell(val, isHeader: false)
                                .frame(minWidth: 104, maxWidth: 220, alignment: .leading)
                            if colIdx < headers.count - 1 {
                                Rectangle()
                                    .fill(subtleBorder)
                                    .frame(width: 0.8)
                            }
                        }
                    }
                    .background(rowIdx.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.05))
                }
            }
        }
        .background(elevatedSurface, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(subtleBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .accessibilityIdentifier("wumind.rich.table")
    }

    private func tableCell(_ raw: String, isHeader: Bool) -> some View {
        Group {
            if let attr = try? AttributedString(markdown: raw, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                Text(attr)
            } else {
                Text(raw)
            }
        }
        .font(isHeader ? .caption.weight(.bold) : .footnote)
        .foregroundStyle(isHeader ? Color.primary : Color.primary.opacity(0.92))
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 11)
        .padding(.vertical, isHeader ? 9 : 8)
    }
}

