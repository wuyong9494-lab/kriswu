import SwiftUI

/// 全部功能：所有页面按用途排好，能搜（搜名字，也搜「请假」「欠班」这类说法），点了直接打开
struct AllFeaturesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""

    /// 一个功能：名字、一句话说明、搜索用的别的说法、图标、谁能用、打开哪一页
    struct Feature: Identifiable {
        enum Access { case everyone, manager, admin }
        var id: String { title }
        var title: String
        var note: String
        var keywords: String
        var icon: String
        var access: Access = .everyone
        var open: () -> AnyView
    }

    struct FeatureGroup: Identifiable {
        var id: String { title }
        var title: String
        var features: [Feature]
    }

    private func feature<V: View>(_ title: String, _ note: String, _ icon: String, keywords: String = "", access: Feature.Access = .everyone,
                                  @ViewBuilder open: @escaping () -> V) -> Feature {
        Feature(title: title, note: note, keywords: keywords, icon: icon, access: access, open: { AnyView(open()) })
    }

    private var groups: [FeatureGroup] {
        let today = DayKey.today
        return [
            FeatureGroup(title: "排班", features: [
                feature("本周全员", "这一周每个人每天排的什么", "tablecells", keywords: "全员 一周 排班表") { WeekRosterView() },
                feature("按日查看", "某一天全员分工、谁值遥测", "calendar", keywords: "全员 今天 明天 分工") { DayRosterView(day: today) },
                feature("搜索成员", "看某个人的排班、和他都休息的日子", "magnifyingglass", keywords: "同事 找人 一起休") { MemberSearchView() },
                feature("下次遥测", "按排班规律推算每个人下次值遥测", "antenna.radiowaves.left.and.right", keywords: "推算 预测 值班") { DutyForecastView() },
                feature("节假日值班", "节假日谁值班、备班", "flag", keywords: "国庆 春节 假期 备班") { HolidayDutyView() },
                feature("排班预览", "网站还没发布的日子按规律先排一版看看", "calendar.badge.plus", keywords: "预排 以后") { RosterPreviewView() },
                feature("排班变动记录", "网站上的排班什么时候改过", "clock.arrow.circlepath", keywords: "改动 历史 变化") { RosterLogView() },
                feature("换班记录", "全员里谁和谁换了班", "arrow.left.arrow.right", keywords: "对换 调班") { TeamChangesView() },
            ]),
            FeatureGroup(title: "换班和请假", features: [
                feature("找人换班", "那天谁有空替你，一键发请求", "person.2", keywords: "替班 调班 有空") { NextWorkSwapView(today: today) },
                feature("换班账本", "谁欠你班、你欠谁班", "book.closed", keywords: "欠班 还班") { SwapLedgerView() },
                feature("请假规划", "请哪几天假最划算", "calendar.badge.minus", keywords: "休假 年假 连休") { LeavePlannerView() },
                feature("待休变化", "待休天数怎么变过来的", "chart.line.uptrend.xyaxis", keywords: "调休 休息 余额") { RestTrendView() },
            ]),
            FeatureGroup(title: "统计", features: [
                feature("工作量", "这个月每个人上了几天、算不算工作量", "chart.bar", keywords: "上班天数 统计 加班") { WorkloadView() },
                feature("全年统计", "一年的工作量、节假日上班", "calendar.badge.clock", keywords: "年度 一年") { YearStatsView() },
                feature("年度总结", "这一年值了几次遥测、休了几天", "sparkles", keywords: "总结 回顾") { YearSummaryView(year: today.year) },
                feature("均衡分析", "大家的活多活少是不是均衡", "scalemass", keywords: "公平 均衡 多少") { FairnessView() },
                feature("数据核对", "网站数据有没有漏读、对不上", "checkmark.seal", keywords: "核对 检查 漏") { DataCheckView() },
                feature("排班规律", "网站怎么排遥测、推算准不准", "wand.and.stars", keywords: "规律 推法", access: .manager) { SchedulePatternsView() },
            ]),
            FeatureGroup(title: "工作", features: [
                feature("周会问题", "各组提的问题解决了没有", "doc.text.magnifyingglass", keywords: "周会 金山文档 会议 问题") { MeetingIssuesView() },
                feature("我负责的周会问题", "负责人里有我的、还没解决的", "person.crop.circle", keywords: "周会 我的 负责人") { MeetingIssuesView(mineOnly: true) },
                feature("周会各组趋势", "每周各组还挂着几个、解决得快不快", "chart.xyaxis.line", keywords: "周会 趋势 统计 图表") { MeetingTrendView() },
                feature("工作留痕", "拍照、录音、记一笔，按天存", "camera", keywords: "照片 录音 笔记 记录") { WorkLogView() },
                feature("各组工作内容", "组A–组E 各干什么", "list.bullet.rectangle", keywords: "组别 说明 分工") { GroupNotesView() },
                feature("网站公告", "值班网站上的公告", "pin", keywords: "通知 公告") { SiteNoticesView() },
            ]),
            FeatureGroup(title: "设置和帮助", features: [
                feature("规则说明", "工作量、换班、周会都是怎么算的", "text.book.closed", keywords: "规则 怎么算 口径") { RulesExplainView() },
                feature("自检与诊断", "哪条连接不通，出问题先看这里", "stethoscope", keywords: "诊断 故障 同步失败 不通") { DiagnosticsView() },
                feature("自动同步设置向导", "让 App 在后台自己同步", "arrow.triangle.2.circlepath", keywords: "后台 快捷指令 自动化") { AutomationGuideView() },
                feature("身份", "普通用户、管理者、管理员", "person.badge.key", keywords: "角色 管理员 权限") { RoleView() },
                feature("备份与恢复", "换手机、重装前备份", "externaldrive", keywords: "备份 恢复 换手机") { BackupView() },
                feature("今天页的卡片", "调顺序、关掉用不着的卡片", "rectangle.stack", keywords: "首页 排序 隐藏 布局") { TodayLayoutView() },
                feature("工作量规则", "周六算不算工作日、没排岗位算不算上班", "slider.horizontal.3", keywords: "规则 设置 周六", access: .admin) { WorkloadRulesView() },
                feature("人员档案", "谁是调度、谁轮组别、什么时候来走的", "person.text.rectangle", keywords: "档案 角色", access: .admin) { PeopleProfilesView() },
                feature("法定节假日", "补录、改节假日安排", "calendar.badge.exclamationmark", keywords: "放假 调休上班", access: .admin) { HolidaysView() },
                feature("导入排班表", "粘贴或从文件导入", "square.and.arrow.down", keywords: "导入 Excel", access: .admin) { ImportView() },
            ]),
        ]
    }

    private func allowed(_ f: Feature) -> Bool {
        switch f.access {
        case .everyone: return true
        case .manager: return store.role != .user
        case .admin: return store.canEdit
        }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let visible = groups.map { g in
            FeatureGroup(title: g.title, features: g.features.filter { f in
                allowed(f) && (q.isEmpty || [f.title, f.note, f.keywords].contains { $0.localizedCaseInsensitiveContains(q) })
            })
        }.filter { !$0.features.isEmpty }
        List {
            if visible.isEmpty {
                Text("没找到「\(q)」。账号、提醒、微信、显示这些在「设置」页。").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(visible) { group in
                Section(group.title) {
                    ForEach(group.features) { f in
                        NavigationLink {
                            f.open()
                        } label: {
                            HStack(spacing: DS.Space.s) {
                                Image(systemName: f.icon)
                                    .font(.body)
                                    .foregroundStyle(DS.Palette.accent)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(f.title).font(.subheadline.weight(.medium))
                                    Text(f.note).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if q.isEmpty {
                Section {
                    Text("账号与同步、提醒、微信推送、显示这几项在「设置」页。").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .appList()
        .navigationTitle("全部功能")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "搜功能，比如「请假」「欠班」")
    }
}
