import SwiftUI

/// 设置 › 接口字段查看：网站数据接口返回了哪些字段，看有没有排班顺序号、轮次这类字段。
/// 人名只留姓、长数字只留前三位，可以放心截图。
struct APIFieldsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var syncing = false

    var body: some View {
        List {
            Section {
                Text("App 同步时会读网站背后的数据接口。这里列出接口每张表里有哪些字段，每个字段举几个例子。名字像「顺序、序号、轮次、排序」的字段标了 ★，可能就是网站排班用的顺序。人名只留姓，手机号、工号这类长数字只留前三位，可以截图发给别人看。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if store.apiFields.isEmpty {
                Section {
                    EmptyState(icon: "tablecells", title: "还没有接口数据",
                               message: "同步一次后再来看。网站要是没有数据接口（只能读网页），这里会一直是空的。")
                    Button {
                        syncing = true
                        Task { @MainActor in
                            _ = await store.sync(userInitiated: true, source: "接口字段查看")
                            syncing = false
                        }
                    } label: {
                        Label(syncing ? "正在同步…" : "现在同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(syncing || !store.canSync)
                }
            } else {
                let suspects = store.apiFields.flatMap { t in t.fields.filter(\.looksLikeOrder).map { (t.path, $0) } }
                Section {
                    if suspects.isEmpty {
                        Label("没看到像顺序号的字段：网站多半是在服务器上按规则排的，接口里只给结果", systemImage: "info.circle")
                    } else {
                        ForEach(Array(suspects.enumerated()), id: \.offset) { _, item in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("★ \(item.1.name)").font(.subheadline.weight(.semibold))
                                Text("例：\(item.1.samples.joined(separator: " / "))（\(item.1.distinct) 种）")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(item.0).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    Text("可能是顺序的字段")
                }
                ForEach(Array(store.apiFields.enumerated()), id: \.offset) { _, table in
                    Section {
                        ForEach(table.fields, id: \.name) { field in
                            VStack(alignment: .leading, spacing: 2) {
                                Text((field.looksLikeOrder ? "★ " : "") + field.name)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(field.looksLikeOrder ? DS.Palette.accent : Color.primary)
                                Text(field.samples.isEmpty ? "（都是空的）" : field.samples.joined(separator: " / ") + "（\(field.distinct) 种）")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("\(table.path) · \(table.rows) 条")
                    }
                }
                if let date = store.apiFieldsDate {
                    Section {
                        Text("来自 \(date.formatted(date: .abbreviated, time: .shortened)) 的同步")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .appList()
        .navigationTitle("接口字段查看")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = APIFieldInspector.text(store.apiFields)
                    ToastCenter.shared.show("已复制", style: .success)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .disabled(store.apiFields.isEmpty)
                .accessibilityLabel("复制")
            }
        }
    }
}
