import ReplayKit
import SwiftUI
import WebKit

/// Unified WUMIND Project & Autonomous Agent OS Workspace.
/// Consolidates ALL autonomous agents onto ONE shared task ledger, ONE approval gate queue,
/// and ONE project-centric artifact graph (NEVER 7 disconnected menus).
struct WuMindAgentWorkspaceView: View {
    @ObservedObject private var coordinator = WuMindAgentCoordinator.shared
    @State private var selectedSection: WorkspaceTab = .projects
    @State private var exportedDeliverables: (docx: URL, xlsx: URL)? = nil
    @State private var exportedQuoteXLSX: URL? = nil
    @State private var exportedMiniAppURL: URL? = nil
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: DS.Space.m) {
                headerBanner

                Picker("工作台分区", selection: $selectedSection) {
                    ForEach(WorkspaceTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

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
        .navigationTitle("项目与智能体总控")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            DutySecondaryBanner(
                title: "WUMIND 项目与共享任务底座",
                subtitle: "模型负责判断、程序负责执行：后台监测、跨应用写入、局部修订、看屏指导、个人教材、手机开发验收与自学习流程共用同一套任务记录与审批边界。",
                icon: "cpu.fill",
                color: .indigo,
                badge: "\(coordinator.taskRuns.count) 条记录"
            )
            HStack(spacing: DS.Space.xs) {
                statChip("待审批", "\(coordinator.pendingApprovalRuns.count)",
                         tint: coordinator.pendingApprovalRuns.isEmpty ? DS.Palette.success : DS.Palette.warning)
                statChip("项目数", "\(coordinator.projects.count)", tint: DS.Palette.accent)
                statChip("监测中", "\(coordinator.monitorSubscriptions.filter { !$0.paused }.count)", tint: DS.Palette.info)
                statChip("自学习流程", "\(coordinator.taughtWorkflows.count)", tint: .purple)
            }
        }
        .card()
        .accessibilityIdentifier("wumind.agentOS.header")
    }

    private func statChip(_ title: String, _ value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
    }

    // MARK: - Tab 1: Projects, Background Monitor & Cross-App Quote Writer

    private var projectsAndDeliverablesSection: some View {
        VStack(spacing: DS.Space.m) {
            // 1. Background Monitor + Chained Partial Revision Card
            if let sub = coordinator.monitorSubscriptions.first, let project = coordinator.projects.first {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "招投标项目管家（后台监测 → 局部修订）", icon: "bell.and.waves.left.and.right.fill", color: .indigo) {
                        Chip(text: sub.paused ? "已暂停" : "后台监测中", color: sub.paused ? .secondary : DS.Palette.success)
                    }
                    Text(project.title).font(.subheadline.weight(.bold))
                    Text("监测目标：\(sub.title)（每 \(sub.intervalMinutes) 分钟 + 事件触发 · 哈希去重免打扰）")
                        .font(.caption).foregroundStyle(.secondary)

                    HStack(spacing: DS.Space.xs) {
                        Button {
                            Task { await coordinator.runChainedTenderAmendmentDemo() }
                        } label: {
                            Label("演练捕获更正→局部修订", systemImage: "bolt.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(DS.Palette.accent, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(.white)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("agentOS.chainedMonitor.run")

                        Button {
                            coordinator.toggleMonitorPause(id: sub.id)
                        } label: {
                            Label(sub.paused ? "恢复" : "暂停", systemImage: sub.paused ? "play.fill" : "pause.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    // Chapters with Human-Edit protection badges
                    VStack(alignment: .leading, spacing: 6) {
                        Text("章节依赖与人工修改保护（v\(project.revisionHistory.count + 1)）")
                            .font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        ForEach(project.chapters) { ch in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(ch.title).font(.caption.weight(.semibold))
                                    Spacer()
                                    if ch.humanEdited {
                                        Chip(text: "人工精修·禁止覆盖", color: DS.Palette.warning)
                                    } else {
                                        Chip(text: "v\(ch.revision) · \(ch.lastUpdatedReason)", color: DS.Palette.info)
                                    }
                                }
                                Text(ch.body).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            .padding(9)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        }
                    }

                    // Real editable .docx + .xlsx export buttons
                    HStack(spacing: DS.Space.xs) {
                        Button {
                            if let pair = coordinator.exportProjectDeliverables(projectID: project.id) {
                                exportedDeliverables = (docx: pair.docxURL, xlsx: pair.xlsxURL)
                                coordinator.lastActionBanner = "已生成可编辑 Word (.docx) + Excel 响应矩阵 (.xlsx)"
                            }
                        } label: {
                            Label("导出 Word + Excel 成品", systemImage: "doc.richtext")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        .buttonStyle(.plain)

                        if let pair = exportedDeliverables {
                            ShareLink(items: [pair.docx, pair.xlsx]) {
                                Label("分享", systemImage: "square.and.arrow.up")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 9)
                                    .background(DS.Palette.success.opacity(0.14), in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                    .foregroundStyle(DS.Palette.success)
                            }
                        }
                    }
                }
                .card()
            }

            // 2. Cross-App Folder Quote Comparison → Real .xlsx Write
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "跨应用执行：报价单 → 真实写入 Excel 比价表", icon: "tablecells.badge.ellipsis", color: DS.Palette.success) {
                    Chip(text: "幂等防重", color: DS.Palette.success)
                }
                Text("读取授权文件夹报价单，自动折算含税到岸价、标注缺失交期，真实写入可编辑 .xlsx，并在覆盖原文件与对外发送前强制审批确认。")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: DS.Space.xs) {
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
                            .background(DS.Palette.success, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .foregroundStyle(.white)
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
                    CardTitle(title: "待你确认的操作边界", icon: "hand.raised.fill", color: DS.Palette.warning) {
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
                                HStack(spacing: DS.Space.xs) {
                                    Button {
                                        coordinator.decideApproval(taskRunID: run.id, approved: true)
                                    } label: {
                                        Text("确认执行")
                                            .font(.caption.weight(.bold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 8)
                                            .background(DS.Palette.accent, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                            .foregroundStyle(.white)
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
                .card(tint: DS.Palette.warning)
            }

            // Resumable Loops & Graphs DAG (shared across Duty, Short-Drama & Mobile Game — no new menu)
            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "可恢复任务图（Loops & Graphs）", icon: "point.3.connected.trianglepath.dotted", color: .indigo) {
                    Chip(text: "\(coordinator.taskGraphs.count) 张图", color: .indigo)
                }
                Text("单步出错仅重试该步；真依赖才等待；断联不阻断已确认结果；恢复连接仅补跑缺失节点。")
                    .font(.caption).foregroundStyle(.secondary)

                HStack(spacing: DS.Space.xs) {
                    Button {
                        Task { await coordinator.runDutyGraphDisconnectLeaveDemo() }
                    } label: {
                        Label("1. 断开请假源执行", systemImage: "wifi.slash")
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
                        Label("2. 恢复仅补跑请假", systemImage: "arrow.clockwise.circle.fill")
                            .font(.caption.weight(.bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(DS.Palette.accent, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("agentOS.graph.resumeLeave")
                }

                HStack(spacing: DS.Space.xs) {
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
                                    Text(node.title).font(.caption2.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    Text("\(node.status.chineseLabel) · 执行\(node.executionCount)次")
                                        .font(.caption2.weight(.bold).monospacedDigit())
                                        .foregroundStyle(
                                            node.status == .completed || node.status == .cachedUnchanged ? DS.Palette.success
                                            : (node.status == .unconnectedOrUnauthorized || node.status == .awaitingApproval ? DS.Palette.warning : DS.Palette.danger)
                                        )
                                }
                                Text("输入：\(node.inputSummary)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                Text("来源：\(node.sourceLabel)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .padding(8)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                        }
                    }
                }
            }
            .card()

            VStack(alignment: .leading, spacing: DS.Space.s) {
                CardTitle(title: "统一任务审计记录（全智能体共用）", icon: "list.bullet.clipboard.fill", color: DS.Palette.accent)
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
                                .font(.caption2).foregroundStyle(.secondary)
                            ForEach(run.steps.prefix(4)) { step in
                                Text("  \(step.index). [\(step.toolName)] \(step.outputSummary.isEmpty ? (step.errorMessage ?? step.title) : step.outputSummary)")
                                    .font(.caption2)
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
                CardTitle(title: "实时看屏指导智能体（ReplayKit）", icon: "rectangle.inset.filled.and.person.filled", color: .blue) {
                    Chip(text: coordinator.liveScreenSession?.isSharing == true ? "共享中" : "待开启",
                         color: coordinator.liveScreenSession?.isSharing == true ? DS.Palette.success : .secondary)
                }
                TextField("描述你要排障的问题（例如：这个模型为什么连不上？）", text: $screenQuestion)
                    .textFieldStyle(DSFieldStyle())
                HStack(spacing: DS.Space.xs) {
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
                            .font(.caption2)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(DS.Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                    }
                }
                Text("注：在 WUMIND 之外的外部 App 持续录屏广播需在 App Store Connect 为 Broadcast Upload Extension 配置独立签名文件；当前已内置完整 ReplayKit 会话管理、跨页指导状态机与一键停止共享。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .card()

            // 2. Interactive Shareable Mini-App Artifact (WKWebView + Live Rule Edit + Sanitized Share)
            if let appIdx = coordinator.miniApps.indices.first {
                let miniApp = coordinator.miniApps[appIdx]
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "一句话生成可分享小工具", icon: "wand.and.stars.inverse", color: .purple) {
                        Chip(text: "脱敏直享", color: .purple)
                    }
                    Text(miniApp.title).font(.subheadline.weight(.bold))
                    InteractiveMiniAppWebView(html: miniApp.htmlContent)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous).strokeBorder(DS.Palette.hairline, lineWidth: 1))

                    HStack(spacing: DS.Space.xs) {
                        Button {
                            var copy = coordinator.miniApps[appIdx]
                            let nextRate = copy.tiers[1].annualDiscountRate > 0.80 ? 0.75 : 0.85
                            WuMindMiniAppArtifactEngine.updateTierRule(artifact: &copy, tierID: "pro", newAnnualDiscountRate: nextRate)
                            coordinator.miniApps[appIdx] = copy
                            coordinator.lastActionBanner = "已修改专业版年付折扣为 \(Int(nextRate * 100)) 折，页面实时重算完成"
                        } label: {
                            Label("改一条规则并实时重算", systemImage: "slider.horizontal.3")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(DS.Palette.accentSoft, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(DS.Palette.accent)
                        }
                        .buttonStyle(.plain)

                        Button {
                            exportedMiniAppURL = coordinator.exportSanitizedMiniAppURL(artifactID: miniApp.id)
                            coordinator.lastActionBanner = "已脱敏导出（已校验 0 密钥、0 原始客户表泄漏）"
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
                }
                .card()
            }

            // 3. Personal Textbook (Playable Audio + Quiz + Jump Back to Source)
            if let course = coordinator.studyCourses.first {
                VStack(alignment: .leading, spacing: DS.Space.s) {
                    CardTitle(title: "个人教材智能体（可听讲解 + 溯源刷题）", icon: "headphones.circle.fill", color: .orange)
                    if let seg = course.audioSegments.first {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(seg.title).font(.subheadline.weight(.semibold))
                                Text("约 \(seg.estimatedSeconds) 秒 · 可听讲稿").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                coordinator.speakAudioSegment(seg)
                            } label: {
                                Label(coordinator.isSpeakingLesson ? "停止朗读" : "播放讲解", systemImage: coordinator.isSpeakingLesson ? "stop.fill" : "play.fill")
                                    .font(.caption.weight(.bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.orange, in: Capsule())
                                    .foregroundStyle(.white)
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
                                    .font(.caption2)
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
                                Text("出处：\(fb.sourceCitation) — \(fb.sourceExcerpt)").font(.caption2).foregroundStyle(.secondary)
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
                    CardTitle(title: "手机开发与测试验收智能体", icon: "hammer.circle.fill", color: .teal) {
                        Chip(text: dev.verifiedFixed ? "同测修前FAIL→修后PASS" : "未通过", color: dev.verifiedFixed ? DS.Palette.success : DS.Palette.danger)
                    }
                    Text(dev.bugSummary).font(.subheadline.weight(.semibold))
                    Text("修前失败：\(dev.preFixEvidence.testIdentifier) → \(dev.preFixEvidence.logSnippet)")
                        .font(.caption2).foregroundStyle(DS.Palette.danger)
                    Text("修后通过：\(dev.postFixEvidence.testIdentifier) → \(dev.postFixEvidence.logSnippet)")
                        .font(.caption2).foregroundStyle(DS.Palette.success)
                    Text("PR 草稿状态：\(dev.draftPRCreated ? "已确认创建 Draft PR（不自动合并/不发版）" : "等待用户审批确认")")
                        .font(.caption2).foregroundStyle(.secondary)
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
                                Text("参数：\(wf.rules[rIdx].parameter)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }

                    HStack(spacing: DS.Space.xs) {
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
                            Label("1. 陌生样本试跑", systemImage: "play.fill")
                                .font(.caption.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Color.purple, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                .foregroundStyle(.white)
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
                                .font(.caption2).foregroundStyle(.secondary)
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
                                Label("2. 验收通过 · 批量执行剩余项", systemImage: "checkmark.circle.fill")
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(DS.Palette.success, in: RoundedRectangle(cornerRadius: DS.Radius.m, style: .continuous))
                                    .foregroundStyle(.white)
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
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != html {
            context.coordinator.lastLoadedHTML = html
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }
}
