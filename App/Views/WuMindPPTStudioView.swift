import SwiftUI
import UIKit

/// Flagship WUMIND AI PPT Studio — generates executive slide decks with ANY configured WUMIND model,
/// renders live 16:9 swipeable slides across 4 themes, and exports crisp native 1920×1080 PDF slide decks
/// ready for Keynote / PowerPoint / WPS / WeChat sharing.
@MainActor
struct WuMindPPTStudioView: View {
    private struct TemplateStarter: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let prompt: String
        let icon: String
        let accent: Color
    }

    private static let starters: [TemplateStarter] = [
        .init(
            title: "季度经营复盘",
            subtitle: "核心指标 · 瓶颈 · 下季目标",
            prompt: "请制作一份 Q4 部门核心业务复盘与明年 Q1 增长规划 PPT，包含核心成果指标、问题拆解、降本增效举措与里程碑时间线",
            icon: "chart.line.uptrend.xyaxis",
            accent: .blue
        ),
        .init(
            title: "技术架构汇报",
            subtitle: "痛点 · 方案对比 · 演进路线",
            prompt: "请制作一份高可用云原生架构升级方案汇报 PPT，包含当前系统痛点、新架构分层设计、安全合规保障、性能指标预期与分阶段上线计划",
            icon: "cpu.fill",
            accent: .indigo
        ),
        .init(
            title: "项目招投标述标",
            subtitle: "优势 · 交付保障 · 售后承诺",
            prompt: "请制作一份智慧运维平台项目述标演示 PPT，突出团队资质、核心技术方案亮点、实施交付排期、应急响应 SLA 与服务保障体系",
            icon: "doc.richtext.fill",
            accent: .purple
        ),
        .init(
            title: "年度工作述职",
            subtitle: "亮点 · 成长 · 新年规划",
            prompt: "请制作一份个人年度工作总结与述职报告 PPT，结构清晰展示年度重点任务完成情况、创新突破、团队协同价值与明年成长目标",
            icon: "person.text.rectangle.fill",
            accent: .teal
        ),
    ]

    @ObservedObject private var store = WuMindStore.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var topicPrompt = ""
    @State private var theme: WuMindPPTTheme = .midnightTech
    @State private var slideCount = 8
    @State private var generating = false
    @State private var liveStreamingChars = 0
    @State private var deck: WuMindPPTDeck?
    @State private var selectedSlideIndex = 0
    @State private var exportedPDFURL: URL?
    @State private var errorMessage: String?
    @State private var generateTask: Task<Void, Never>?
    @FocusState private var promptFocused: Bool

    private var isDark: Bool { colorScheme == .dark }
    private var canvasBg: Color {
        isDark ? Color(red: 0.03, green: 0.035, blue: 0.055) : Color(red: 0.955, green: 0.96, blue: 0.98)
    }
    private var cardBg: Color {
        isDark ? Color(red: 0.095, green: 0.105, blue: 0.142) : Color.white
    }
    private var cardBorder: Color {
        isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.07)
    }
    private var activeModelLabel: String {
        store.channel == .managed ? store.managedSelectedModelID : store.selectedModelName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controlStrip

                if let errorMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        Text(errorMessage).font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.13), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if generating {
                    generatingCard
                }

                if let currentDeck = deck {
                    deckPreviewSection(currentDeck)
                } else if !generating {
                    starterSection
                }

                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(canvasBg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingComposer
        }
        .navigationTitle("AI 写 PPT 工坊")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            generateTask?.cancel()
        }
    }

    private var controlStrip: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.indigo)
                    Text("模型：\(activeModelLabel)")
                        .font(.caption.weight(.bold))
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))

                Menu {
                    ForEach([6, 8, 10, 15], id: \.self) { count in
                        Button("\(count) 页") { slideCount = count }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption2.weight(.bold))
                        Text("\(slideCount) 页")
                            .font(.caption.weight(.bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                }
                .tint(.primary)
            }

            // 4-theme full-width bar (zero horizontal scroll)
            HStack(spacing: 6) {
                ForEach(WuMindPPTTheme.allCases) { item in
                    let selected = theme == item
                    Button {
                        Haptics.tap()
                        theme = item
                        if var updated = deck {
                            updated.theme = item
                            deck = updated
                            exportedPDFURL = Self.renderPDF(deck: updated)
                        }
                    } label: {
                        Text(item.title)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                selected ? themeAccent(item).opacity(0.20) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .foregroundStyle(selected ? themeAccent(item) : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(cardBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            .accessibilityIdentifier("ai.ppt.theme")
        }
    }

    private var starterSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .pink, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 58, height: 58)
                        .shadow(color: .orange.opacity(0.32), radius: 14, y: 6)
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                }
                Text("一句话生成高管级 16:9 PPT")
                    .font(.title3.weight(.bold))
                Text("自动规划封面、核心指标页、双栏对比页与口播备注，一键导出 1920×1080 演示 PDF / Markdown 大纲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            Text("常用汇报模板")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Self.starters) { starter in
                    Button {
                        Haptics.tap()
                        topicPrompt = starter.prompt
                        promptFocused = true
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: starter.icon)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(starter.accent)
                            Spacer(minLength: 4)
                            Text(starter.title)
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(starter.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                        .padding(12)
                        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var generatingCard: some View {
        HStack(spacing: 12) {
            ProgressView().tint(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("正在编排 \(slideCount) 页高管级幻灯片…")
                    .font(.subheadline.weight(.bold))
                Text("模型：\(activeModelLabel) · 已输出 \(liveStreamingChars) 字符")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("取消") {
                generateTask?.cancel()
                generating = false
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.red)
        }
        .padding(14)
        .background(cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.orange.opacity(0.32), lineWidth: 1))
    }

    private func deckPreviewSection(_ currentDeck: WuMindPPTDeck) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentDeck.title)
                        .font(.headline.weight(.bold))
                    Text("\(currentDeck.slides.count) 页 · \(currentDeck.theme.title) · 左右滑动预览")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(min(selectedSlideIndex + 1, currentDeck.slides.count)) / \(currentDeck.slides.count)")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(cardBg, in: Capsule())
                    .overlay(Capsule().strokeBorder(cardBorder, lineWidth: 1))
            }

            // 16:9 Interactive Swipeable Slide Stage
            TabView(selection: $selectedSlideIndex) {
                ForEach(Array(currentDeck.slides.enumerated()), id: \.offset) { idx, slide in
                    slideCanvas(slide: slide, deck: currentDeck, index: idx + 1, total: currentDeck.slides.count)
                        .tag(idx)
                        .padding(.horizontal, 2)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .shadow(color: .black.opacity(isDark ? 0.42 : 0.14), radius: 14, y: 6)

            // Action bar: Export 16:9 PDF + Copy Markdown Outline
            HStack(spacing: 10) {
                if let pdfURL = exportedPDFURL {
                    ShareLink(item: pdfURL) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.fill")
                            Text("导出 16:9 演示 PDF")
                                .font(.caption.weight(.bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            LinearGradient(colors: [.orange, .pink], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                        )
                        .foregroundStyle(.white)
                    }
                }

                Button {
                    UIPasteboard.general.string = WuMindPPTEngine.exportMarkdownOutline(currentDeck)
                    Haptics.success()
                    ToastCenter.shared.show("已复制全部 PPT 大纲 Markdown", style: .success)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc")
                        Text("复制大纲")
                            .font(.caption.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(cardBg, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }

            // Speaker Notes for active slide
            if currentDeck.slides.indices.contains(selectedSlideIndex) {
                let slide = currentDeck.slides[selectedSlideIndex]
                VStack(alignment: .leading, spacing: 6) {
                    Label("第 \(slide.id) 页演讲备注与配图建议", systemImage: "text.bubble.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                    if !slide.speakerNotes.isEmpty {
                        Text(slide.speakerNotes)
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("围绕本页核心要点展开说明即可。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !slide.visualHint.isEmpty {
                        Text("建议配图：\(slide.visualHint)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(cardBg, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            }
        }
    }

    private func slideCanvas(slide: WuMindPPTDeck.Slide, deck: WuMindPPTDeck, index: Int, total: Int) -> some View {
        let palette = slidePalette(deck.theme)
        return ZStack(alignment: .topLeading) {
            LinearGradient(colors: [palette.bgStart, palette.bgEnd], startPoint: .topLeading, endPoint: .bottomTrailing)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: 24, height: 4)
                    Spacer()
                    Text("\(index) / \(total)")
                        .font(.system(size: 10, weight: .bold).monospacedDigit())
                        .foregroundStyle(palette.subText)
                }

                if slide.layout == .cover {
                    Spacer(minLength: 4)
                    Text(slide.title)
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)
                    Text(deck.subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.subText)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                } else {
                    Text(slide.title)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)

                    HStack(alignment: .top, spacing: 10) {
                        if let metric = slide.highlightMetric, !metric.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(metric)
                                    .font(.title3.weight(.black))
                                    .foregroundStyle(palette.accent)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                if let label = slide.highlightLabel, !label.isEmpty {
                                    Text(label)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(palette.subText)
                                        .lineLimit(2)
                                }
                            }
                            .padding(8)
                            .frame(width: 96, alignment: .leading)
                            .background(palette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(slide.bullets.prefix(4).enumerated()), id: \.offset) { _, bullet in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(palette.accent)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 5)
                                    Text(bullet)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(palette.primaryText.opacity(0.92))
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.accent.opacity(0.28), lineWidth: 1))
    }

    private var floatingComposer: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("输入 PPT 主题、汇报对象或粘贴素材要点…", text: $topicPrompt, axis: .vertical)
                    .lineLimit(1...4)
                    .font(.subheadline)
                    .focused($promptFocused)
                    .submitLabel(.done)
                    .padding(.vertical, 8)
                    .padding(.leading, 8)
                    .accessibilityIdentifier("ai.ppt.prompt")

                Button {
                    startGenerateDeck()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                !generating && !topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                                    : LinearGradient(colors: [Color.secondary.opacity(0.28), Color.secondary.opacity(0.28)], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: 38, height: 38)
                        if generating {
                            ProgressView().tint(.white).controlSize(.small)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(generating || topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("ai.ppt.generate")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(isDark ? 0.35 : 0.10), radius: 14, y: 4)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 8)
        }
        .background(
            LinearGradient(
                colors: [canvasBg.opacity(0), canvasBg.opacity(0.92), canvasBg],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func startGenerateDeck() {
        let trimmed = topicPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        promptFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        errorMessage = nil
        generating = true
        liveStreamingChars = 0
        let chosenTheme = theme
        let chosenCount = slideCount

        generateTask?.cancel()
        generateTask = Task {
            do {
                let sys = WuMindPPTEngine.systemPrompt(slideCount: chosenCount, theme: chosenTheme)
                let res = try await store.runStatelessChat(
                    messages: [AIProviderMessage(role: .user, text: trimmed)],
                    systemPrompt: sys,
                    deepThinking: false,
                    onAnswerDelta: { partial in
                        self.liveStreamingChars = partial.count
                    }
                )
                try Task.checkCancellation()
                let built = WuMindPPTEngine.parseDeck(from: res.answer, fallbackTopic: String(trimmed.prefix(24)), theme: chosenTheme)
                deck = built
                selectedSlideIndex = 0
                exportedPDFURL = Self.renderPDF(deck: built)
                Haptics.success()
            } catch is CancellationError {
                // Cancelled cleanly
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                Haptics.warning()
            }
            generating = false
        }
    }

    private func themeAccent(_ t: WuMindPPTTheme) -> Color {
        switch t {
        case .midnightTech: return .cyan
        case .executiveBlue: return .blue
        case .minimalIvory: return .indigo
        case .easternInk: return .teal
        }
    }

    private struct SlidePalette {
        let bgStart: Color
        let bgEnd: Color
        let primaryText: Color
        let subText: Color
        let accent: Color
        let uiBgStart: UIColor
        let uiBgEnd: UIColor
        let uiText: UIColor
        let uiSubText: UIColor
        let uiAccent: UIColor
    }

    private func slidePalette(_ t: WuMindPPTTheme) -> SlidePalette {
        Self.palette(for: t)
    }

    private static func palette(for t: WuMindPPTTheme) -> SlidePalette {
        switch t {
        case .midnightTech:
            return .init(
                bgStart: Color(red: 0.05, green: 0.07, blue: 0.14),
                bgEnd: Color(red: 0.11, green: 0.12, blue: 0.25),
                primaryText: .white,
                subText: Color.white.opacity(0.70),
                accent: Color(red: 0.25, green: 0.80, blue: 0.98),
                uiBgStart: UIColor(red: 0.05, green: 0.07, blue: 0.14, alpha: 1),
                uiBgEnd: UIColor(red: 0.11, green: 0.12, blue: 0.25, alpha: 1),
                uiText: .white,
                uiSubText: UIColor.white.withAlphaComponent(0.72),
                uiAccent: UIColor(red: 0.25, green: 0.80, blue: 0.98, alpha: 1)
            )
        case .executiveBlue:
            return .init(
                bgStart: Color(red: 0.06, green: 0.14, blue: 0.30),
                bgEnd: Color(red: 0.10, green: 0.24, blue: 0.48),
                primaryText: .white,
                subText: Color.white.opacity(0.75),
                accent: Color(red: 0.98, green: 0.74, blue: 0.26),
                uiBgStart: UIColor(red: 0.06, green: 0.14, blue: 0.30, alpha: 1),
                uiBgEnd: UIColor(red: 0.10, green: 0.24, blue: 0.48, alpha: 1),
                uiText: .white,
                uiSubText: UIColor.white.withAlphaComponent(0.75),
                uiAccent: UIColor(red: 0.98, green: 0.74, blue: 0.26, alpha: 1)
            )
        case .minimalIvory:
            return .init(
                bgStart: Color(red: 0.985, green: 0.985, blue: 0.975),
                bgEnd: Color(red: 0.94, green: 0.95, blue: 0.97),
                primaryText: Color(red: 0.10, green: 0.12, blue: 0.18),
                subText: Color(red: 0.36, green: 0.40, blue: 0.48),
                accent: Color(red: 0.26, green: 0.36, blue: 0.88),
                uiBgStart: UIColor(red: 0.985, green: 0.985, blue: 0.975, alpha: 1),
                uiBgEnd: UIColor(red: 0.94, green: 0.95, blue: 0.97, alpha: 1),
                uiText: UIColor(red: 0.10, green: 0.12, blue: 0.18, alpha: 1),
                uiSubText: UIColor(red: 0.36, green: 0.40, blue: 0.48, alpha: 1),
                uiAccent: UIColor(red: 0.26, green: 0.36, blue: 0.88, alpha: 1)
            )
        case .easternInk:
            return .init(
                bgStart: Color(red: 0.08, green: 0.13, blue: 0.13),
                bgEnd: Color(red: 0.14, green: 0.22, blue: 0.20),
                primaryText: Color(red: 0.96, green: 0.95, blue: 0.91),
                subText: Color(red: 0.76, green: 0.82, blue: 0.78),
                accent: Color(red: 0.40, green: 0.82, blue: 0.68),
                uiBgStart: UIColor(red: 0.08, green: 0.13, blue: 0.13, alpha: 1),
                uiBgEnd: UIColor(red: 0.14, green: 0.22, blue: 0.20, alpha: 1),
                uiText: UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1),
                uiSubText: UIColor(red: 0.76, green: 0.82, blue: 0.78, alpha: 1),
                uiAccent: UIColor(red: 0.40, green: 0.82, blue: 0.68, alpha: 1)
            )
        }
    }

    /// Renders a crisp 1920×1080 widescreen multi-page PDF presentation using `UIGraphicsPDFRenderer`.
    private static func renderPDF(deck: WuMindPPTDeck) -> URL? {
        let pageRect = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let palette = palette(for: deck.theme)

        let data = renderer.pdfData { ctx in
            let total = deck.slides.count
            for (idx, slide) in deck.slides.enumerated() {
                ctx.beginPage()
                let cg = ctx.cgContext

                // Gradient background
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                if let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: [palette.uiBgStart.cgColor, palette.uiBgEnd.cgColor] as CFArray,
                    locations: [0, 1]
                ) {
                    cg.drawLinearGradient(
                        gradient,
                        start: CGPoint(x: 0, y: 0),
                        end: CGPoint(x: pageRect.width, y: pageRect.height),
                        options: []
                    )
                }

                // Top accent pill
                palette.uiAccent.setFill()
                UIBezierPath(roundedRect: CGRect(x: 110, y: 84, width: 120, height: 14), cornerRadius: 7).fill()

                // Page number top right
                let pageNumAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: 28, weight: .bold),
                    .foregroundColor: palette.uiSubText,
                ]
                let pageLabel = "\(idx + 1) / \(total)"
                (pageLabel as NSString).draw(at: CGPoint(x: 1710, y: 76), withAttributes: pageNumAttrs)

                if slide.layout == .cover {
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 82, weight: .heavy),
                        .foregroundColor: palette.uiText,
                    ]
                    (slide.title as NSString).draw(
                        in: CGRect(x: 110, y: 310, width: 1700, height: 240),
                        withAttributes: titleAttrs
                    )
                    let subAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 38, weight: .medium),
                        .foregroundColor: palette.uiSubText,
                    ]
                    (deck.subtitle as NSString).draw(
                        in: CGRect(x: 110, y: 560, width: 1620, height: 140),
                        withAttributes: subAttrs
                    )
                } else {
                    let titleAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 58, weight: .bold),
                        .foregroundColor: palette.uiText,
                    ]
                    (slide.title as NSString).draw(
                        in: CGRect(x: 110, y: 130, width: 1700, height: 110),
                        withAttributes: titleAttrs
                    )

                    var bulletLeftX: CGFloat = 110
                    if let metric = slide.highlightMetric, !metric.isEmpty {
                        let cardRect = CGRect(x: 110, y: 280, width: 420, height: 280)
                        palette.uiAccent.withAlphaComponent(0.15).setFill()
                        UIBezierPath(roundedRect: cardRect, cornerRadius: 28).fill()
                        let mAttrs: [NSAttributedString.Key: Any] = [
                            .font: UIFont.systemFont(ofSize: 86, weight: .black),
                            .foregroundColor: palette.uiAccent,
                        ]
                        (metric as NSString).draw(in: CGRect(x: 142, y: 325, width: 356, height: 120), withAttributes: mAttrs)
                        if let label = slide.highlightLabel, !label.isEmpty {
                            let lAttrs: [NSAttributedString.Key: Any] = [
                                .font: UIFont.systemFont(ofSize: 30, weight: .semibold),
                                .foregroundColor: palette.uiSubText,
                            ]
                            (label as NSString).draw(in: CGRect(x: 142, y: 455, width: 356, height: 80), withAttributes: lAttrs)
                        }
                        bulletLeftX = 580
                    }

                    let bulletAttrs: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 38, weight: .medium),
                        .foregroundColor: palette.uiText.withAlphaComponent(0.94),
                    ]
                    var y: CGFloat = 290
                    for bullet in slide.bullets.prefix(6) {
                        palette.uiAccent.setFill()
                        UIBezierPath(ovalIn: CGRect(x: bulletLeftX, y: y + 16, width: 16, height: 16)).fill()
                        (bullet as NSString).draw(
                            in: CGRect(x: bulletLeftX + 36, y: y, width: 1810 - bulletLeftX - 36, height: 105),
                            withAttributes: bulletAttrs
                        )
                        y += 112
                    }
                }

                // Subtle footer watermark
                let footAttrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                    .foregroundColor: palette.uiSubText.withAlphaComponent(0.6),
                ]
                ("WUMIND PPT Studio · \(deck.title)" as NSString).draw(at: CGPoint(x: 110, y: 1005), withAttributes: footAttrs)
            }
        }

        let safeTitle = deck.title
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .prefix(24)
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WUMIND_PPT_\(safeTitle.isEmpty ? "Deck" : String(safeTitle)).pdf")
        do {
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }
}
