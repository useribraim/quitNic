import SwiftData
import SwiftUI

struct ProgressView: View {
    @Environment(\.modelContext) private var context
    let plan: QuitPlan
    @Query(sort: \CravingCheckIn.occurredAt, order: .reverse) private var checkIns: [CravingCheckIn]
    @State private var serverProgress: ProgressResponse?
    var body: some View {
        NavigationStack {
            List {
                if let serverProgress {
                    Section("Synced summary") {
                        LabeledContent("Money saved", value: serverProgress.moneySaved.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")))
                        LabeledContent("Units avoided", value: serverProgress.avoidedUnits.formatted())
                    }
                }
                Section("Milestones") {
                    ForEach([(24, "First day"), (168, "First week"), (720, "First month"), (2160, "Three months")], id: \.0) { hours, title in
                        Label(title, systemImage: Date().timeIntervalSince(plan.quitDate) >= Double(hours * 3600) ? "checkmark.seal.fill" : "circle").foregroundStyle(Date().timeIntervalSince(plan.quitDate) >= Double(hours * 3600) ? .green : .secondary)
                    }
                }
                Section("Craving history") {
                    if checkIns.isEmpty { ContentUnavailableView("No check-ins yet", systemImage: "waveform.path.ecg", description: Text("Your craving history will appear here.")) }
                    ForEach(checkIns) { item in VStack(alignment: .leading) { HStack { Text(item.trigger).font(.headline); Spacer(); Text("\(item.intensity)/10") }; Text(item.copingAction).foregroundStyle(.secondary); Text(item.occurredAt, style: .relative).font(.caption) } }
                }
            }.navigationTitle("Progress").task { await loadProgress() }
        }
    }

    private func loadProgress() async {
        serverProgress = ResponseCache.get(ProgressResponse.self, key: "progress", context: context)
        guard KeychainStore.readToken() != nil else { return }
        if let fresh = try? await APIClient.shared.progress() {
            serverProgress = fresh
            try? ResponseCache.put(fresh, key: "progress", lifetime: 300, context: context)
        }
    }
}
