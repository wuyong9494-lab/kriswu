import SwiftUI

// MARK: - 人员档案

/// 每个人是什么角色（轮组别 / 不轮组别 / 调度 / 领导）、什么时候来、什么时候走。
/// 没建档案的人按排班自动判断；管理员可以一键按自动判断建档，再逐个改。
struct PeopleProfilesView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""

    var body: some View {
        let zh = Locale(identifier: "zh_CN")
        let names = Set(store.roster.keys).union(store.settings.profiles.keys)
            .filter { query.isEmpty || $0.contains(query) }
            .sorted { $0.compare($1, locale: zh) == .orderedAscending }
        let unconfirmed = Set(store.roster.keys).subtracting(store.settings.profiles.keys).count
        List {
            Section {
                LabeledContent("已建档案", value: "\(store.settings.profiles.count) 人")
                LabeledContent("还没确认（按排班认的）", value: "\(unconfirmed) 人")
                if store.canEdit && unconfirmed > 0 {
                    Button {
                        var all = store.settings.profiles
                        for name in store.roster.keys where all[name] == nil {
                            all[name] = PersonProfile(name: name, spans: [RoleSpan(from: nil, role: store.suggestedRole(name))])
                        }
                        store.settings.profiles = all
                        ToastCenter.shared.show("已按排班认出的角色建好 \(unconfirmed) 人的档案", style: .success)
                    } label: {
                        Label("按排班认出的角色给没建档的人建档", systemImage: "person.crop.rectangle.stack")
                    }
                }
                ReadOnlyNotice()
            } footer: {
                Text("角色决定没排岗位的工作日怎么算：轮组别、不轮组别 = 正常上班，算工作量；调度 = 不算；领导 = 不统计。建了档案就按档案算，不再按排班猜。")
            }
            Section {
                if names.isEmpty {
                    AppEmptyStateCard(icon: query.isEmpty ? "person.2" : "magnifyingglass",
                                      title: query.isEmpty ? "还没有人员" : "没有匹配的人员",
                                      message: query.isEmpty ? "同步排班后可在这里查看人员档案。" : "试试其他名字。")
                }
                ForEach(names, id: \.self) { name in
                    NavigationLink {
                        PersonProfileView(name: name)
                    } label: {
                        HStack {
                            Avatar(name: name, size: 30)
                            Text(name)
                            Spacer()
                            let today = DayKey.today
                            if let role = store.settings.profiles[name]?.role(on: today) {
                                Text(role.rawValue).font(DS.Font.caption).foregroundStyle(.secondary)
                            } else {
                                Text("自动：\(store.suggestedRole(name).rawValue)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("duty.profile.row")
                }
            }
        }
        .searchable(text: $query, prompt: "搜名字")
        .appList()
        .navigationTitle("人员档案")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PersonProfileView: View {
    @EnvironmentObject private var store: AppStore
    let name: String
    @State private var newRole: PersonRole = .group
    @State private var fromDay = Date()
    @State private var fromAlways = true

    private var profile: PersonProfile? { store.settings.profiles[name] }

    var body: some View {
        let suggested = store.suggestedRole(name)
        Form {
            Section {
                if let profile {
                    ForEach(Array(profile.spans.enumerated()), id: \.offset) { _, span in
                        LabeledContent(span.from.map { "\($0.dateText) 起" } ?? "一直", value: span.role.rawValue)
                    }
                } else {
                    LabeledContent("还没建档案", value: "按排班认：\(suggested.rawValue)")
                }
            } header: {
                Text("角色")
            } footer: {
                Text("按排班认：看最近三个月，调度占一半以上是调度，组A–E 占一半以上是轮组别，其它是不轮组别。")
            }
            if store.canEdit {
                Section {
                    Picker("改成", selection: $newRole) {
                        ForEach(PersonRole.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("所有日子都按这个算", isOn: $fromAlways)
                    if !fromAlways {
                        DatePicker("从这天起", selection: $fromDay, displayedComponents: .date)
                    }
                    AppPrimaryCTA(title: "保存角色") {
                        var p = profile ?? PersonProfile(name: name, spans: [RoleSpan(from: nil, role: suggested)])
                        p.setRole(newRole, from: fromAlways ? nil : DayKey(date: fromDay, calendar: .app))
                        store.settings.profiles[name] = p
                        ToastCenter.shared.show("已保存", style: .success)
                    }
                } header: {
                    Text("修改角色")
                }
                Section {
                    dateToggle("来的日子（以前不统计）", get: { profile?.joined }) { day in update { $0.joined = day } }
                    dateToggle("走的日子（以后不统计）", get: { profile?.left }) { day in update { $0.left = day } }
                } header: {
                    Text("在岗时间")
                } footer: {
                    Text("没填就看网站上出现的时间：第一次出现前两周、最后一次出现后两个月以外不统计。")
                }
                if profile != nil {
                    Section {
                        ConfirmButton(title: "删除档案，改回按排班认", message: "\(name)的角色、来走日期会删掉，改回按排班认。") {
                            store.settings.profiles[name] = nil
                        }
                    }
                }
            } else {
                Section { ReadOnlyNotice() }
            }
        }
        .appList()
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { newRole = profile?.role(on: .today) ?? suggested }
    }

    private func update(_ change: (inout PersonProfile) -> Void) {
        var p = profile ?? PersonProfile(name: name, spans: [RoleSpan(from: nil, role: store.suggestedRole(name))])
        change(&p)
        store.settings.profiles[name] = p
    }

    @ViewBuilder
    private func dateToggle(_ title: String, get: @escaping () -> DayKey?, set: @escaping (DayKey?) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { get() != nil }, set: { set($0 ? .today : nil) }))
        if let day = get() {
            DatePicker(title, selection: Binding(get: { day.date(calendar: .app, hour: 12) },
                                                 set: { set(DayKey(date: $0, calendar: .app)) }),
                       displayedComponents: .date)
                .labelsHidden()
        }
    }
}

// MARK: - 排班变动历史

/// 每次同步发现网站上谁哪天的岗位变了，都记在这里
struct RosterLogView: View {
    @EnvironmentObject private var store: AppStore
    @State private var query = ""
    var person: String? = nil

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let list = store.rosterLog.reversed().filter { e in
            (person == nil || e.name == person) && (q.isEmpty || e.name.contains(q) || (e.old ?? "").contains(q) || (e.new ?? "").contains(q))
        }
        List {
            if list.isEmpty {
                Section {
                    if q.isEmpty {
                        AppEmptyStateCard(icon: "clock.arrow.circlepath", title: "还没有排班变动", message: "同步发现的排班变化会显示在这里。")
                    } else {
                        AppEmptyStateCard(icon: "magnifyingglass", title: "没有匹配的变动", message: "试试其他名字或岗位。")
                    }
                }
            }
            ForEach(Array(list.prefix(500).enumerated()), id: \.offset) { _, e in
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text("\(e.day.month)/\(e.day.day) · \(e.name)")
                        .font(DS.Font.headline)
                    Text("\(e.old.map(store.matcher.displayName) ?? "没排") → \(e.new.map(store.matcher.displayName) ?? "没排")")
                        .font(DS.Font.body)
                    Text("\(e.at.formatted(date: .abbreviated, time: .shortened)) · \(Provenance(source: e.source, at: e.at).sourceTitle)")
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .searchable(text: $query, prompt: "搜名字、岗位")
        .appList()
        .navigationTitle(person.map { "\($0)的排班变动" } ?? "排班变动历史")
        .navigationBarTitleDisplayMode(.inline)
    }
}
