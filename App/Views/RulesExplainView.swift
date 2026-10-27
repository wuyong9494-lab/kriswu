import SwiftUI

/// 规则说明：App 里所有「怎么算」用大白话列出来；例子的结果是按现在的规则当场算的，和各页面算的一样
struct RulesExplainView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let sections = RuleBook.sections(rules: store.settings.workloadRules, saturdayIsWorkday: store.settings.saturdayIsWorkday)
        List {
            Section {
                Text("工作量、找人换班、待休、遥测推算、周会问题都按下面这些规则算，规则只有这一份。觉得哪条不对，截图告诉我。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.rules) { rule in
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text(rule.text).font(.subheadline)
                            if !rule.examples.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(rule.examples, id: \.self) { example in
                                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                                            Text(example.label).foregroundStyle(.secondary)
                                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                                            Text(RuleBook.actual(example, matcher: store.matcher, rules: store.settings.workloadRules))
                                                .fontWeight(.medium)
                                        }
                                        .font(.caption)
                                    }
                                }
                                .padding(.leading, DS.Space.xs)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            if store.canEdit {
                Section {
                    NavigationLink("改工作量规则") { WorkloadRulesView() }
                } footer: {
                    Text("工作量里能改的几条（周六算不算工作日、没排岗位算不算上班等）在这里改，改完上面跟着变。")
                }
            }
        }
        .appList()
        .navigationTitle("规则说明")
        .navigationBarTitleDisplayMode(.inline)
    }
}
