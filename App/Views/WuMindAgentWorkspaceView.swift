import ReplayKit
import SwiftUI
import WebKit

/// Unified WUMIND Project & Autonomous Agent OS Workspace.
/// Consolidates ALL autonomous agents onto ONE shared task ledger, ONE approval gate queue,
/// and ONE project-centric artifact graph (NEVER 7 disconnected menus).
struct WuMindAgentWorkspaceView: View {
    @ObservedObject private var coordinator = WuMindAgentCoordinator.shared
    @Environment(\.horizontalSizeClass) private var widthClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedSection: WorkspaceTab = .projects
    @State private var exportedDeliverables: (docx: URL, xlsx: URL)? = nil
    @State private var exportedQuoteXLSX: URL? = nil
    @State private var exportedMiniAppURL: URL? = nil
    @State private var selectedWebAppIndex: Int = 0
    @State private var exportedWorkflowURL: URL? = nil
    @State private var quizFeedback: WuMindPersonalTextbookEngine.AnswerFeedback? = nil
    @State private var pilotResult: WuMindTeachOnceWorkflowEngine.PilotRunResult? = nil
    @State private var batchResult: WuMindTeachOnceWorkflowEngine.BatchRunResult? = nil
    @State private var screenQuestion = "这个模型为什么连不上？"

    enum WorkspaceTab: String, CaseIterable, Identifiable {
        case projects = "项目与交付"
        case tasks = "任务与审批"
        case agents = "看屏·教材·工具"
        case teachOnce = "教一次流程"
        var id: String { rawValue }
    }

    private var compactControls: Bool { widthClass == .compact || typeSize.isAccessibilitySize }

    private var actionLayout: AnyLayout {
        compactControls
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: DS.Space.s))
    }

    private var sectionPicker: some View {
        Picker("工作台分区", selection: $selectedSection) {
            ForEach(WorkspaceTab.allCases) { tab in Text(tab.rawValue).tag(tab) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DS.Space.m) {
                if typeSize.isAccessibilitySize {
                    LabeledContent("工作区") { sectionPicker.pickerStyle(.menu) }
                } else if widthClass == .compact {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                        ForEach(WorkspaceTab.allCases) { tab in
                            Button {
                                selectedSection = tab
                            } label: {
                                Text(tab.rawValue)
                                    .font(DS.Font.callout)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(tab == selectedSection ? DS.Palette.accentSoft : .clear,
                                                in: RoundedRectangle(cornerRadius: DS.Radius.m))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(tab == selectedSection ? .isSelected : [])
                        }
                    }
                } else {
                    sectionPicker.pickerStyle(.segmented)
                }
                headerBanner
                if let banner = coordinator.lastActionBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DS.Palette.success)
                        Text(banner)
                            .font(.caption.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .background(DS.Palette.success.opacity(0.10), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                }

                switch selectedSection {
                case .projects:
                    projectsAndDeliverablesSection
                case .tasks:
                    unifiedTasksAndApprovalsSection
                case .agents:
                    liveAndCreativeAgentsSection
                case .teachOnce:
                    teachOnceWorkflowSection
                }
            }
            .padding(.horizontal, DS.Space.m)
            .padding(.top, DS.Space.s)
            .padding(.bottom, DS.Space.xl)
            .frame(maxWidth: DS.readableWidth)
            .frame(maxWidth: .infinity)
        }
        .appBackground()
        .navigationTitle("项目与智能体")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerBanner: some View {
        DisclosureGroup("工作区概况") {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                LabeledContent("项目", value: "\(coordinator.projects.count)")
                LabeledContent("待审批", value: "\(coordinator.pendingApprovalRuns.count)")
                LabeledContent("监测中", value: "\(coordinator.monitorSubscriptions.filter { !$0.paused }.count)")
                LabeledContent("已有流程", value: "\(coordinator.taughtWorkflows.count)")
            }
            .font(DS.Font.caption)
            .padding(.top, DS.Space.s)
        }
        .accessibilityIdentifier("wumind.agentOS.header")
    }

    // MARK: - Tab 1: Projects, Background Monitor & Cross-App Quote Writer

    private var projectsAndDeliverablesSection: some View {
        VStack(spacing: DS.Space.m) {
            // 1. Background Monitor + Chained Partial Revision Card
            if let sub = coordinator.monitorSubscriptions.first, let project = coordinator.projects.first {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    Text(project.title)
                        .font(DS.Font.title)
                        .fixedSize(horizontal: false, vertical: true)
                    LabeledContent("修订版本", value: "v\(project.revisionHistory.count + 1)")
                        .font(DS.Font.caption)
                    AppPrimaryCTA(title: "导出 Word 与 Excel", icon: "doc.richtext") {
                        if let pair = coordinator.exportProjectDeliverables(projectID: project.id) {
                            exportedDeliverables = (docx: pair.docxURL, xlsx: pair.xlsxURL)
                            coordinator.lastActionBanner = "已生成 Word 文档与 Excel 响应矩阵。"
                        }
                    }
                    if let pair = exportedDeliverables {
                        ShareLink(items: [pair.docx, pair.xlsx]) {
                            Label("分享项目文件", systemImage: "square.and.arrow.up")
                                .frame(minHeight: 44)
                        }
                    }

                    Divider()
                    LabeledContent("招投标监测", value: sub.paused ? "已暂停" : "监测中")
                    Text("\(sub.title) · 每 \(sub.intervalMinutes) 分钟检查，也响应事件更新。")
                        .font(DS.Font.caption).foregroundStyle(.secondary)
                    actionLayout {
                        Button {
                            Task { await coordinator.runChainedTenderAmendmentDemo() }
                        } label: {
                            Label("演练更正与修订", systemImage: "arrow.triangle.2.circlepath")
                                .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("agentOS.chainedMonitor.run")

                        Button(sub.paused ? "恢复监测" : "暂停监测") { coordinator.toggleMonitorPause(id: sub.id) }
                            .frame(minHeight: 44)
                    }

                    Divider()
                    DisclosureGroup("项目章节（\(project.chapters.count)）") {
                        VStack(alignment: .leading, spacing: DS.Space.m) {
                            ForEach(project.chapters) { chapter in
                                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                                    Text(chapter.title).font(DS.Font.headline)
                                    Text(chapter.humanEdited ? "已保护人工修改" : "v\(chapter.revision) · \(chapter.lastUpdatedReason)")
                                        .font(DS.Font.caption).foregroundStyle(.secondary)
                                    Text(chapter.body).font(DS.Font.body)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, DS.Space.s)
                    }
                }
                .card()
            }

            // 2. Cross-App Folder Quote Comparison → Real .xlsx Write
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "报价比价表", icon: "tablecells.badge.ellipsis", color: DS.Palette.success) {
                    Chip(text: "幂等防重", color: DS.Palette.success)
                }
                Text("使用三份示例报价生成可编辑的 Excel 比价表。")
                    .font(.caption).foregroundStyle(.secondary)

                actionLayout {
                    Button {
                        let sampleQuotes: [WuMindCrossAppQuoteEngine.QuoteFileInput] = [
                            .init(fileName: "星辰测控报价.csv", content: "供应商：星辰测控\n标的物：S频段功放\n未税价：42000\n运费：600\n交期：10天"),
                            .init(fileName: "北极光电子报价.csv", content: "供应商：北极光电子\n标的物：S频段功放\n含税价：46800\n运费：0\n交期：7天"),
                            .init(fileName: "瀚海航天报价.csv", content: "供应商：瀚海航天\n标的物：S频段功放\n含税价：45900\n运费：500"),
                        ]
                        exportedQuoteXLSX = coordinator.runCrossAppQuoteComparison(files: sampleQuotes, approveOverwrite: true)
                    } label: {
                        Label("提取报价并写入 .xlsx", systemImage: "arrow.down.doc.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .buttonStyle(.plain)

                    if let xlsx = exportedQuoteXLSX {
                        ShareLink(item: xlsx) {
                            Label("分享比价表", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        }
                    }
                }

                if let state = coordinator.quoteComparisons.first, !state.recommendationPreview.isEmpty {
                    Text(state.recommendationPreview)
                        .font(.caption)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                }
            }
            .card()
        }
    }

    // MARK: - Tab 2: Unified Task Runs & Approval Gates

    private var unifiedTasksAndApprovalsSection: some View {
        VStack(spacing: DS.Space.m) {
            if !coordinator.pendingApprovalRuns.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "待审批任务", icon: "hand.raised.fill", color: DS.Palette.warning) {
                        Chip(text: "\(coordinator.pendingApprovalRuns.count) 项待批", color: DS.Palette.warning)
                    }
                    ForEach(coordinator.pendingApprovalRuns) { run in
                        if let gate = run.pendingApproval {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Chip(text: gate.actionKind.rawValue, color: DS.Palette.warning)
                                    Text(gate.title).font(.subheadline.weight(.bold))
                                }
                                Text("目标：\(gate.targetResource)").font(.caption).foregroundStyle(.secondary)
                                Text(gate.previewText).font(.caption).fixedSize(horizontal: false, vertical: true)
                                actionLayout {
                                    Button {
                                        coordinator.decideApproval(taskRunID: run.id, approved: true)
                                    } label: {
                                        Text("确认执行")
                                            .font(.caption.weight(.bold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                            .foregroundStyle(DS.Palette.accent)
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        coordinator.decideApproval(taskRunID: run.id, approved: false)
                                    } label: {
                                        Text("拒绝")
                                            .font(.caption.weight(.semibold))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(DS.Palette.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                            .foregroundStyle(DS.Palette.danger)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(10)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        }
                    }
                }
                .card()
            }

            // Resumable Loops & Graphs DAG (shared across Duty, Short-Drama & Mobile Game — no new menu)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "可恢复任务", icon: "point.3.connected.trianglepath.dotted", color: .indigo) {
                    Chip(text: "\(coordinator.taskGraphs.count) 张图", color: .indigo)
                }
                Text("单步出错仅重试该步；真依赖才等待；断联不阻断已确认结果；恢复连接仅补跑缺失节点。")
                    .font(.caption).foregroundStyle(.secondary)

                actionLayout {
                    Button {
                        Task { await coordinator.runDutyGraphDisconnectLeaveDemo() }
                    } label: {
                        Label("断开请假来源", systemImage: "wifi.slash")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DS.Palette.warning.opacity(0.16), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .foregroundStyle(DS.Palette.warning)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("agentOS.graph.disconnectLeave")

                    Button {
                        Task { await coordinator.resumeDutyGraphReconnectLeaveDemo() }
                    } label: {
                        Label("恢复请假来源", systemImage: "arrow.clockwise.circle.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .foregroundStyle(DS.Palette.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("agentOS.graph.resumeLeave")
                }

                actionLayout {
                    Button {
                        Task { await coordinator.runShortDramaShot3RedoGraphDemo() }
                    } label: {
                        Label("短剧仅重做第3镜", systemImage: "film")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Task { await coordinator.runMobileGameLevel2FixGraphDemo() }
                    } label: {
                        Label("游戏仅修第2关", systemImage: "gamecontroller")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                if let latestGraph = coordinator.taskGraphs.first {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(latestGraph.title).font(.caption.weight(.bold))
                            Spacer()
                            Text("第 \(latestGraph.runGeneration) 轮")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        ForEach(latestGraph.nodes) { node in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(node.title).font(DS.Font.caption.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    Text("\(node.status.chineseLabel) · 执行\(node.executionCount)次")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(
                                            node.status == .completed || node.status == .cachedUnchanged ? DS.Palette.success
                                            : (node.status == .unconnectedOrUnauthorized || node.status == .awaitingApproval ? DS.Palette.warning : DS.Palette.danger)
                                        )
                                }
                                Text("输入：\(node.inputSummary)").font(DS.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                                Text("来源：\(node.sourceLabel)").font(DS.Font.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(8)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                        }
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "任务记录", icon: "list.bullet.clipboard.fill", color: DS.Palette.accent)
                if coordinator.taskRuns.isEmpty {
                    EmptyState(icon: "tray", title: "暂无任务执行记录", message: "发起值班查询、后台监测、跨应用写入、局部修订或看屏指导后，每一步都将统一记录在此。")
                } else {
                    ForEach(coordinator.taskRuns.prefix(15)) { run in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Chip(text: run.kind.chineseTitle, color: DS.Palette.accent)
                                Text(run.title).font(.caption.weight(.bold)).lineLimit(1)
                                Spacer()
                                Text(run.status.chineseLabel)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(run.status == .completed ? DS.Palette.success : (run.status == .failed ? DS.Palette.danger : DS.Palette.warning))
                            }
                            Text("引擎：\(run.activeModelLabel) · 边界：\(run.dataBoundary.chineseLabel)")
                                .font(DS.Font.caption).foregroundStyle(.secondary)
                            ForEach(run.steps.prefix(4)) { step in
                                Text("  \(step.index). [\(step.toolName)] \(step.outputSummary.isEmpty ? (step.errorMessage ?? step.title) : step.outputSummary)")
                                    .font(DS.Font.caption)
                                    .foregroundStyle(step.status == .failed ? DS.Palette.danger : .secondary)
                                    .lineLimit(2)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }
                }
            }
            .card()
        }
    }

    // MARK: - Tab 3: Live Screen Guide, Personal Textbook, Mobile Dev Verify & Interactive Mini-App

    private var liveAndCreativeAgentsSection: some View {
        VStack(spacing: DS.Space.m) {
            // 1. Live Screen Guidance (ReplayKit)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "屏幕指导", icon: "rectangle.inset.filled.and.person.filled", color: .blue) {
                    Chip(text: coordinator.liveScreenSession?.isSharing == true ? "共享中" : "待开启",
                         color: coordinator.liveScreenSession?.isSharing == true ? DS.Palette.success : .secondary)
                }
                TextField("描述你要排障的问题（例如：这个模型为什么连不上？）", text: $screenQuestion)
                    .textFieldStyle(DSFieldStyle())
                actionLayout {
                    if coordinator.liveScreenSession?.isSharing == true {
                        Button {
                            coordinator.stopLiveScreenGuide()
                        } label: {
                            Label("停止共享", systemImage: "stop.circle.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(DS.Palette.danger, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            coordinator.startLiveScreenGuide(question: screenQuestion)
                        } label: {
                            Label("开启连续看屏指导", systemImage: "play.circle.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.blue, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                    }
                    SystemBroadcastButton()
                        .frame(width: 44, height: 36)
                }
                if let session = coordinator.liveScreenSession, !session.instructions.isEmpty {
                    ForEach(session.instructions.suffix(3)) { ins in
                        Text("第 \(ins.stepNumber) 步 [\(ins.appName)·\(ins.pageTitle)]：\(ins.detectedIssue) → \(ins.nextAction)")
                            .font(DS.Font.caption)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                    }
                }
                Text("注：在 WUMIND 之外的外部 App 持续录屏广播需在 App Store Connect 为 Broadcast Upload Extension 配置独立签名文件；当前已内置完整 ReplayKit 会话管理、跨页指导状态机与一键停止共享。")
                    .font(DS.Font.caption).foregroundStyle(.secondary)
            }
            .card()

            // 2. Unified Mobile-First Shareable Web App ("生成 → 试用 → 分享 → 添加到主屏幕")
            if !coordinator.shareableWebApps.isEmpty {
                let safeIdx = min(selectedWebAppIndex, coordinator.shareableWebApps.count - 1)
                let webApp = coordinator.shareableWebApps[safeIdx]
                let pub = WuMindShareableWebAppEngine.publishSanitizedSharePackage(app: webApp)
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "可分享的小工具与游戏", icon: "wand.and.stars.inverse", color: .purple) {
                        Chip(text: "v\(webApp.version) · 只读脱敏", color: .purple)
                    }

                    Picker("验收样例", selection: $selectedWebAppIndex) {
                        ForEach(Array(coordinator.shareableWebApps.enumerated()), id: \.element.id) { idx, item in
                            Text(item.shortTitle).tag(idx)
                        }
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(webApp.title).font(.subheadline.weight(.bold))
                        Text("同链接：\(webApp.publicShareURL)").font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                        Text(webApp.ruleChangeSummary).font(DS.Font.caption).foregroundStyle(.secondary)
                    }

                    InteractiveMiniAppWebView(html: pub.shareableHTML)
                        .frame(height: 290)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).strokeBorder(DS.Palette.hairline, lineWidth: 1))

                    actionLayout {
                        Button {
                            coordinator.upgradeShareableWebAppRules(appID: webApp.id)
                        } label: {
                            Label("作者改规则升 v\(webApp.version + 1)", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            exportedMiniAppURL = coordinator.exportSanitizedShareableWebAppURL(appID: webApp.id)
                        } label: {
                            Label("生成脱敏分享页", systemImage: "lock.shield")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if let url = exportedMiniAppURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .padding(8)
                                    .background(DS.Palette.success.opacity(0.14), in: Circle())
                                    .foregroundStyle(DS.Palette.success)
                            }
                        }
                    }

                    Text("权限分离：分享链接仅开放使用（\(pub.permission.chineseLabel)），作者编辑令牌、原报价表、密钥与聊天记录绝不外发。支持微信内直开及 Safari 添加到主屏幕，与原生 iOS TestFlight / Android APK 打包分开。")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .card()
            }

            // 3. Personal Textbook (Playable Audio + Quiz + Jump Back to Source)
            if let course = coordinator.studyCourses.first {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "个人教材", icon: "headphones.circle.fill", color: .orange)
                    if let seg = course.audioSegments.first {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(seg.title).font(.subheadline.weight(.semibold))
                                Text("约 \(seg.estimatedSeconds) 秒 · 可听讲稿").font(DS.Font.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                coordinator.speakAudioSegment(seg)
                            } label: {
                                Label(coordinator.isSpeakingLesson ? "停止朗读" : "播放讲解", systemImage: coordinator.isSpeakingLesson ? "stop.fill" : "play.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(DS.Palette.surfaceSunken, in: Capsule())
                                    .foregroundStyle(DS.Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let firstQ = WuMindPersonalTextbookEngine.nextPracticeQueue(for: course).first {
                        Text("薄弱优先题：\(firstQ.prompt)").font(.caption.weight(.semibold))
                        ForEach(Array(firstQ.options.enumerated()), id: \.offset) { idx, opt in
                            Button {
                                quizFeedback = coordinator.submitTextbookAnswer(courseID: course.id, questionID: firstQ.id, optionIndex: idx)
                            } label: {
                                Text("\(idx + 1). \(opt)")
                                    .font(DS.Font.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        if let fb = quizFeedback {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(fb.isCorrect ? "回答正确（薄弱权重已下调）" : "回答错误 · 已跳回原文并提高薄弱权重：")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(fb.isCorrect ? DS.Palette.success : DS.Palette.warning)
                                Text("出处：\(fb.sourceCitation) — \(fb.sourceExcerpt)").font(DS.Font.caption).foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                        }
                    }
                }
                .card()
            }

            // 4. Mobile Dev & Verification Agent
            if let dev = coordinator.devVerifications.first {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "开发与测试记录", icon: "hammer.circle.fill", color: .teal) {
                        Chip(text: dev.verifiedFixed ? "同测修前FAIL→修后PASS" : "未通过", color: dev.verifiedFixed ? DS.Palette.success : DS.Palette.danger)
                    }
                    Text(dev.bugSummary).font(.subheadline.weight(.semibold))
                    Text("修前失败：\(dev.preFixEvidence.testIdentifier) → \(dev.preFixEvidence.logSnippet)")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.danger)
                    Text("修后通过：\(dev.postFixEvidence.testIdentifier) → \(dev.postFixEvidence.logSnippet)")
                        .font(DS.Font.caption).foregroundStyle(DS.Palette.success)
                    Text("PR 草稿状态：\(dev.draftPRCreated ? "已确认创建 Draft PR（不自动合并/不发版）" : "等待用户审批确认")")
                        .font(DS.Font.caption).foregroundStyle(.secondary)
                }
                .card()
            }
        }
    }

    // MARK: - Tab 4: Teach-Once → Pilot → Batch → Sanitized Workflow Share

    private var teachOnceWorkflowSection: some View {
        VStack(spacing: DS.Space.m) {
            if let wfIdx = coordinator.taughtWorkflows.indices.first {
                let wf = coordinator.taughtWorkflows[wfIdx]
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: wf.name, icon: "sparkles.rectangle.stack.fill", color: .purple) {
                        Chip(text: "可编辑规则", color: .purple)
                    }
                    Text(wf.description).font(.caption).foregroundStyle(.secondary)

                    ForEach(wf.rules.indices, id: \.self) { rIdx in
                        Toggle(isOn: Binding(
                            get: { coordinator.taughtWorkflows[wfIdx].rules[rIdx].enabled },
                            set: { coordinator.taughtWorkflows[wfIdx].rules[rIdx].enabled = $0; coordinator.saveToDisk() }
                        )) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(wf.rules[rIdx].title).font(.caption.weight(.semibold))
                                Text("参数：\(wf.rules[rIdx].parameter)").font(DS.Font.caption).foregroundStyle(.secondary)
                            }
                        }
                    }

                    actionLayout {
                        Button {
                            let unseen = WuMindCrossAppQuoteEngine.QuoteFileInput(
                                fileName: "陌生供应商_丙华报价.txt",
                                content: "供应商：丙华科技\n标的物：测控服务器\n未税价：10200\n运费：200"
                            )
                            let res = WuMindTeachOnceWorkflowEngine.runPilotOnUnseenSample(
                                workflow: coordinator.taughtWorkflows[wfIdx],
                                unseenSample: unseen,
                                totalBatchCount: 5
                            )
                            pilotResult = res
                            coordinator.upsertTaskRun(res.taskRun)
                            coordinator.lastActionBanner = "陌生样本试跑完成：请验明规则与预计费用（¥\(String(format: "%.2f", res.projectedRemainingCostYuan))）后再批跑"
                        } label: {
                            Label("用新样本试跑", systemImage: "play.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            exportedWorkflowURL = coordinator.exportSanitizedWorkflowURL(workflowID: wf.id)
                            coordinator.lastActionBanner = "已导出脱敏流程包（不含原报价、密钥与历史）"
                        } label: {
                            Label("脱敏分享流程", systemImage: "lock.doc")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if let url = exportedWorkflowURL {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .padding(8)
                                    .background(DS.Palette.success.opacity(0.14), in: Circle())
                                    .foregroundStyle(DS.Palette.success)
                            }
                        }
                    }

                    if let pilot = pilotResult {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("试跑验收结果：\(pilot.sampleResult.supplier) → 折合含税到岸价 ¥\(String(format: "%.2f", pilot.sampleResult.normalizedLandedTotalYuan)) · 缺失：\(pilot.sampleResult.missingFields.isEmpty ? "无" : pilot.sampleResult.missingFields.joined(separator: "、"))")
                                .font(.caption)
                            Text("剩余 \(pilot.remainingItemCount) 份预计花费：¥\(String(format: "%.2f", pilot.projectedRemainingCostYuan))")
                                .font(DS.Font.caption).foregroundStyle(.secondary)
                            Button {
                                let rest: [WuMindCrossAppQuoteEngine.QuoteFileInput] = [
                                    .init(fileName: "丁创报价.txt", content: "供应商：丁创\n未税价：9900\n运费：400\n交期：6天"),
                                    .init(fileName: "戊云报价.txt", content: "供应商：戊云\n含税价：11400\n运费：0\n交期：5天"),
                                ]
                                let res = WuMindTeachOnceWorkflowEngine.executeApprovedBatch(
                                    workflow: coordinator.taughtWorkflows[wfIdx],
                                    pilot: pilot,
                                    remainingSamples: rest,
                                    approved: true
                                )
                                batchResult = res
                                coordinator.upsertTaskRun(res.taskRun)
                                coordinator.lastActionBanner = "已确认并幂等批量处理完成（共 \(res.allResults.count) 份）"
                            } label: {
                                Label("确认结果并执行剩余项", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                    .foregroundStyle(DS.Palette.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(10)
                        .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                    }

                    if let batch = batchResult {
                        Text("批量执行完成：共 \(batch.allResults.count) 份已核对，均无重复写入。")
                            .font(.caption).foregroundStyle(DS.Palette.success)
                    }
                }
                .card()
            }
        }
    }
}

/// Native ReplayKit System Broadcast Picker button for cross-app screen sharing start/stop.
private struct SystemBroadcastButton: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 44, height: 36))
        picker.showsMicrophoneButton = false
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

/// Sandboxed interactive WKWebView rendering user-generated single-file HTML mini-apps live on device.
private struct InteractiveMiniAppWebView: UIViewRepresentable {
    let html: String
    var baseURL: URL? = URL(string: "https://app.wumind.ai")

    final class Coordinator {
        var lastLoadedHTML: String = ""
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        context.coordinator.lastLoadedHTML = html
        webView.loadHTMLString(html, baseURL: baseURL)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != html {
            context.coordinator.lastLoadedHTML = html
            uiView.loadHTMLString(html, baseURL: baseURL)
        }
    }
}
