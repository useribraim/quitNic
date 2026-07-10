import SwiftUI

struct DashboardView: View {
    let plan: QuitPlan
    @State private var now = Date()
    private var progress: LocalProgress { ProgressCalculator.calculate(plan: plan, now: now) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(progress.seconds == 0 ? "Your quit begins soon" : "You’re building momentum").font(.title.bold())
                    Text(plan.motivation).font(.headline).foregroundStyle(.secondary)
                    TimelineCard(seconds: progress.seconds)
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        MetricCard(title: "Money saved", value: progress.moneySaved.formatted(.currency(code: Locale.current.currency?.identifier ?? "EUR")), icon: "eurosign.circle")
                        MetricCard(title: "Units avoided", value: progress.avoidedUnits.formatted(.number.precision(.fractionLength(0))), icon: "leaf")
                        MetricCard(title: "Current streak", value: "\(progress.streakDays) days", icon: "flame")
                        MetricCard(title: "Next milestone", value: progress.nextMilestone ?? "Three months+", icon: "flag.checkered")
                    }
                }.padding()
            }.navigationTitle("Today")
        }.task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); now = .now } }
    }
}

private struct TimelineCard: View {
    let seconds: Int
    var body: some View {
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
        VStack(alignment: .leading) { Text("Nicotine-free time").font(.caption).foregroundStyle(.secondary); Text("\(days)d  \(hours)h  \(minutes)m").font(.system(.largeTitle, design: .rounded).bold()) }
            .frame(maxWidth: .infinity, alignment: .leading).padding().background(.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 18))
    }
}
private struct MetricCard: View {
    let title: String, value: String, icon: String
    var body: some View { VStack(alignment: .leading, spacing: 8) { Image(systemName: icon).foregroundStyle(.green); Text(value).font(.headline); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, minHeight: 90, alignment: .leading).padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 16)).accessibilityElement(children: .combine) }
}

