import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(TrainingLibrary.self) private var library
    private var records: [PelvicSnapshot] { library.records }
    private var squatTotals: [String: Int] { SquatProgress.totals(library.squats.map(\.day)) }
    private var selectedSquats: [SquatSnapshot] { library.squats.filter { $0.dayKey == ProgressCalculator.dayKey(for: selectedDate) } }
    @State private var month = Date.now
    @State private var selectedDate = Date.now
    private let calendar = Calendar.current
    private var completedDays: Set<String> { ProgressCalculator.completedDays(records.map(\.trainingDay)) }
    private var selectedRecords: [PelvicSnapshot] { records.filter { $0.dayKey == ProgressCalculator.dayKey(for: selectedDate) } }
    private var monthStart: Date { calendar.dateInterval(of: .month, for: month)?.start ?? month }
    private var monthDates: [Date] {
        (calendar.range(of: .day, in: .month, for: month) ?? 1..<2).compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: monthStart)
        }
    }
    private var leadingBlanks: Int { (calendar.component(.weekday, from: monthStart) + 5) % 7 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Card {
                        LabeledContent("盆底肌训练日", value: "\(completedDays.count) 天")
                        LabeledContent("深蹲累计次数", value: "\(squatTotals.values.reduce(0, +)) 个")
                        LabeledContent("深蹲达标天数", value: "\(squatTotals.values.filter { $0 >= 50 }.count) 天")
                        LabeledContent("有效训练时长", value: durationText(records.reduce(0) { $0 + $1.activeDuration } + library.squats.reduce(0) { $0 + $1.activeDuration }))
                        Text("盆底肌训练日表示当天完成过完整训练，自定节奏的每日组数目标在今天页查看；深蹲累计 50 个达标。时长不含深蹲组间休息。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Card {
                        HStack {
                            Button { moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                                .accessibilityLabel("上个月")
                            Spacer()
                            Text(month, format: .dateTime.year().month()).font(.headline)
                            Spacer()
                            Button { moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                                .accessibilityLabel("下个月")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 8) {
                            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) {
                                Text($0).font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 44) }
                            ForEach(monthDates, id: \.self) { date in
                                let key = ProgressCalculator.dayKey(for: date)
                                let selected = calendar.isDate(date, inSameDayAs: selectedDate)
                                let complete = completedDays.contains(key)
                                let squatComplete = (squatTotals[key] ?? 0) >= 50
                                Button { selectedDate = date } label: {
                                    VStack(spacing: 3) {
                                        Text("\(calendar.component(.day, from: date))").font(.subheadline.monospacedDigit())
                                        HStack(spacing: 4) {
                                            Circle().fill(complete ? (selected ? Color.white : Theme.teal) : .clear).frame(width: 5, height: 5)
                                            RoundedRectangle(cornerRadius: 1).fill(squatComplete ? (selected ? Color.white : Theme.squat) : .clear).frame(width: 5, height: 5)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(selected ? .white : Theme.ink)
                                    .background(selected ? Theme.teal : .clear, in: RoundedRectangle(cornerRadius: 12))
                                }
                                .accessibilityLabel("\(date.formatted(date: .abbreviated, time: .omitted))，\(complete ? "盆底肌有完整训练" : "盆底肌无完整训练")，\(squatComplete ? "深蹲已达标" : "深蹲未达标")")
                            }
                        }
                        HStack(spacing: 16) {
                            Label("盆底肌完成过训练", systemImage: "circle.fill").foregroundStyle(Theme.teal)
                            Label("深蹲 50 个", systemImage: "square.fill").foregroundStyle(Theme.squat)
                        }.font(.caption)
                    }
                    HStack {
                        Text(selectedDate, format: .dateTime.month().day()).font(.headline)
                        Spacer()
                        Button("回到今天") { month = .now; selectedDate = .now }.font(.subheadline)
                    }
                    if selectedRecords.contains(where: { $0.course.isPersonal }) {
                        Text("自定节奏：完成 \(selectedRecords.filter { $0.course.isPersonal && $0.isCompleted }.count) 组，每组 10 次")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if selectedRecords.isEmpty && selectedSquats.isEmpty {
                        ContentUnavailableView("这一天没有记录", systemImage: "leaf", description: Text("从今天开始，慢慢建立自己的节奏。"))
                    } else {
                        ForEach(selectedRecords) { record in
                            NavigationLink { RecordDetailView(record: record) } label: {
                                Card {
                                    HStack {
                                        Label("盆底肌 · " + record.stageName, systemImage: record.isCompleted ? "checkmark.circle.fill" : "pause.circle")
                                            .font(.headline).foregroundStyle(Theme.teal)
                                        Spacer()
                                        Text(record.statusTitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(record.startedAt, format: .dateTime.hour().minute())
                                        Spacer()
                                        Text(durationText(record.activeDuration))
                                        Image(systemName: "chevron.right")
                                    }.font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                        ForEach(selectedSquats) { record in
                            NavigationLink { SquatRecordDetailView(record: record) } label: {
                                Card {
                                    HStack {
                                        Label("深蹲 · \(record.confirmed) 个", systemImage: "figure.strengthtraining.functional")
                                            .font(.headline).foregroundStyle(Theme.squat)
                                        Spacer()
                                        Text(record.statusTitle).font(.caption).foregroundStyle(.secondary)
                                    }
                                    HStack {
                                        Text(record.startedAt, format: .dateTime.hour().minute())
                                        Spacer()
                                        Text(durationText(record.activeDuration))
                                        Image(systemName: "chevron.right")
                                    }.font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                }.padding(24)
            }.background(Theme.background).navigationTitle("训练记录")
        }
    }

    private func moveMonth(_ offset: Int) {
        if let next = calendar.date(byAdding: .month, value: offset, to: monthStart) {
            month = next
            selectedDate = next
        }
    }
}

struct RecordDetailView: View {
    let record: PelvicSnapshot
    @Environment(TrainingLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        List {
            Section("本次练习") {
                LabeledContent("开始时间", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("阶段", value: record.stageName)
                LabeledContent("节奏", value: "收缩 \(Int(record.contraction)) 秒 / 放松 \(Int(record.relaxation)) 秒")
                LabeledContent("完成次数", value: "\(record.completedRepetitions) / \(record.targetRepetitions)")
                LabeledContent("有效时长", value: durationText(record.activeDuration))
                LabeledContent("状态", value: record.statusTitle)
                LabeledContent("感受", value: record.feedback ?? "未填写")
            }
            if record.status == "interrupted" && record.endedAt == nil {
                Section { Text("上次练习意外结束，仅保留最近保存的次数和时长。未计入达标天数。") }
            }
            Section {
                Button("删除这条记录", role: .destructive) { confirmDelete = true }
            } footer: { Text("删除后会重新计算训练天数和阶段进度，当前选定阶段保持不变。") }
        }
        .navigationTitle("训练详情").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("删除这条训练记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                Task {
                    do { try await library.delete(id: record.id, squat: false); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .alert("删除失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好的", role: .cancel) { }
        } message: { Text(error ?? "") }
    }
}

struct SquatRecordDetailView: View {
    let record: SquatSnapshot
    @Environment(TrainingLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false
    @State private var error: String?
    var body: some View {
        List {
            Section("本次深蹲") {
                LabeledContent("开始时间", value: record.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("实际确认", value: "\(record.confirmed) 个")
                LabeledContent("节奏带练", value: "\(record.guidedRepetitions) 个")
                LabeledContent("计划分组", value: record.plan.sets.map(String.init).joined(separator: " + "))
                LabeledContent("各组确认", value: record.confirmedSets.isEmpty ? "尚未确认" : record.confirmedSets.map(String.init).joined(separator: " + "))
                LabeledContent("节奏", value: "下蹲 \(Int(record.plan.down)) 秒 / 起身 \(Int(record.plan.up)) 秒")
                LabeledContent("组间休息", value: "\(Int(record.plan.rest)) 秒")
                LabeledContent("有效时长", value: durationText(record.activeDuration))
                LabeledContent("状态", value: record.statusTitle)
            }
            if record.status == "interrupted" && record.endedAt == nil {
                Text("上次练习意外结束。仅已保存的确认次数计入每日目标，未确认的部分没有自动计入。")
            }
            Section {
                Button("删除这条记录", role: .destructive) { confirmDelete = true }
            } footer: { Text("删除后重新计算深蹲次数和达标天数，不影响盆底肌进度。") }
        }
        .navigationTitle("深蹲详情").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("删除这条深蹲记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                Task {
                    do { try await library.delete(id: record.id, squat: true); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            }
        }
        .alert("删除失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好的", role: .cancel) { }
        } message: { Text(error ?? "") }
    }
}
