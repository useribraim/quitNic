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
                    Section {
                        Text("Synced summary")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                        LabeledContent("Money saved", value: serverProgress.moneySaved.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")))
                            .foregroundStyle(.primary)
                        LabeledContent("Units avoided", value: serverProgress.avoidedUnits.formatted())
                            .foregroundStyle(.primary)
                    }
                }
                Section {
                    Text("Milestones")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach([(24, "First day"), (168, "First week"), (720, "First month"), (2160, "Three months")], id: \.0) { hours, title in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: Date().timeIntervalSince(plan.quitDate) >= Double(hours * 3600) ? "checkmark.seal.fill" : "circle")
                            Text(title)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                    }
                }
                Section {
                    Text("Craving history")
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if checkIns.isEmpty { ContentUnavailableView("No check-ins yet", systemImage: "waveform.path.ecg", description: Text("Your craving history will appear here.")) }
                    ForEach(checkIns) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.trigger)
                                    .font(.headline)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                Text("\(item.intensity)/10")
                            }
                            Text(item.copingAction)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(item.occurredAt, style: .relative)
                                .font(.caption)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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
