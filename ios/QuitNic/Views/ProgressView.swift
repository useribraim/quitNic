import Charts
import SwiftData
import SwiftUI

struct ProgressView: View {
    @Environment(\.modelContext) private var context
    let plan: QuitPlan
    @Query(sort: \CravingCheckIn.occurredAt, order: .reverse) private var checkIns: [CravingCheckIn]
    @Query(sort: \RescueSession.startedAt, order: .reverse) private var sessions: [RescueSession]
    @State private var serverProgress: ProgressResponse?

    private var days: Double { max(0, Date().timeIntervalSince(plan.quitDate) / 86_400) }
    private var resisted: Int { checkIns.filter(\.resisted).count }
    private var resistanceRate: Int { checkIns.isEmpty ? 0 : Int((Double(resisted) / Double(checkIns.count) * 100).rounded()) }
    private var average: Int { checkIns.isEmpty ? 0 : Int((Double(checkIns.map(\.intensity).reduce(0, +)) / Double(checkIns.count)).rounded()) }
    private var moneySaved: Double { serverProgress?.moneySaved ?? days * Double(plan.dailyConsumption) * plan.unitCost }
    private var avoided: Double { serverProgress?.avoidedUnits ?? days * Double(plan.dailyConsumption) }
    private var trend: [TrendPoint] {
        let grouped = Dictionary(grouping: checkIns) { Calendar.current.startOfDay(for: $0.occurredAt) }
        return grouped.keys.sorted().suffix(7).map { date in
            let values = grouped[date, default: []].map(\.intensity)
            return TrendPoint(date: date, intensity: Int((Double(values.reduce(0, +)) / Double(values.count)).rounded()))
        }
    }
    private var triggers: [TriggerPoint] {
        Dictionary(grouping: checkIns, by: \.trigger).map { TriggerPoint(trigger: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }.prefix(5).map { $0 }
    }
    private var helpful: [HelpPoint] {
        Dictionary(grouping: sessions.filter { $0.endingIntensity != nil }, by: \.intervention).map { key, values in
            let reduction = values.map { max(0, $0.startingIntensity - ($0.endingIntensity ?? $0.startingIntensity)) }
                .reduce(0, +) / max(1, values.count)
            return HelpPoint(name: key, reduction: reduction, count: values.count)
        }.sorted { $0.reduction > $1.reduction }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOUR PATTERN LAB").font(.caption.weight(.bold)).tracking(1.4).foregroundStyle(QuitNicTheme.teal)
                        Text(checkIns.isEmpty ? "Your progress starts here" : "Notice what is changing")
                            .font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(QuitNicTheme.ink)
                        Text("Small observations become useful patterns when you look back at them together.")
                            .foregroundStyle(QuitNicTheme.secondaryInk)
                    }.accessibilityElement(children: .combine)

                    card("Your snapshot", icon: "sparkles") {
                        HStack { metric(moneySaved.formatted(.currency(code: "EUR")), "Money saved", "eurosign.circle.fill", QuitNicTheme.teal); metric(avoided.formatted(.number.precision(.fractionLength(0))), "Units avoided", "leaf.fill", .green) }
                        HStack { metric("\(resistanceRate)%", "Cravings resisted", "checkmark.shield.fill", .orange); metric("\(average)/10", "Average intensity", "waveform.path.ecg", .pink) }
                    }

                    card("Intensity trend", icon: "chart.line.uptrend.xyaxis") {
                        if trend.count < 2 {
                            TrendPreview(recordedCount: trend.count)
                        } else {
                            Text("Your recorded craving intensity over time.")
                                .font(.caption)
                                .foregroundStyle(QuitNicTheme.secondaryInk)
                            Chart { ForEach(trend) { point in
                                LineMark(x: .value("Date", point.date), y: .value("Intensity", point.intensity)).foregroundStyle(QuitNicTheme.teal)
                                PointMark(x: .value("Date", point.date), y: .value("Intensity", point.intensity)).foregroundStyle(QuitNicTheme.teal)
                            }}.chartYScale(domain: 1...10).frame(height: 150)
                        }
                    }

                    card("Common triggers", icon: "circle.grid.2x2.fill") {
                        Text("Where your cravings most often begin.").font(.caption).foregroundStyle(QuitNicTheme.secondaryInk)
                        if triggers.isEmpty { placeholder("Choose a trigger during Rescue to start mapping your patterns.") } else {
                            Chart { ForEach(triggers) { item in
                                BarMark(x: .value("Check-ins", item.count), y: .value("Trigger", item.trigger)).foregroundStyle(QuitNicTheme.teal.gradient)
                            }}.frame(height: CGFloat(max(140, triggers.count * 34)))
                        }
                    }

                    card("What helped", icon: "hands.sparkles.fill") {
                        Text(helpful.isEmpty ? "Finish a Rescue session to measure what works for you." : "Your strongest coping tools so far.").font(.caption).foregroundStyle(QuitNicTheme.secondaryInk)
                        if helpful.isEmpty { placeholder("QuitNic will show your strongest coping tools here.") } else {
                            ForEach(helpful) { item in
                                HStack { Image(systemName: "arrow.down.right.circle.fill").foregroundStyle(QuitNicTheme.teal); Text(item.name).font(.subheadline.weight(.medium)); Spacer(); Text("-\(item.reduction) pts · \(item.count) sessions").font(.caption).foregroundStyle(QuitNicTheme.secondaryInk) }
                            }
                        }
                    }

                    card("Recent check-ins", icon: "clock.arrow.circlepath") {
                        if checkIns.isEmpty { placeholder("Your recent observations will appear here.") } else {
                            ForEach(checkIns.prefix(5)) { item in
                                HStack { VStack(alignment: .leading, spacing: 3) { Text(item.trigger).font(.subheadline.weight(.semibold)); Text("\(item.copingAction) · \(item.occurredAt, style: .relative)").font(.caption).foregroundStyle(QuitNicTheme.secondaryInk) }; Spacer(); Text("\(item.intensity)/10").foregroundStyle(QuitNicTheme.teal) }
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 28)
            }.background(QuitNicTheme.warmBackground.ignoresSafeArea()).navigationTitle("Progress").task { await loadProgress() }
        }
    }

    @ViewBuilder private func card<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Label(title, systemImage: icon).font(.headline).foregroundStyle(QuitNicTheme.teal); content() }.quitNicCard()
    }
    private func metric(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View { VStack(alignment: .leading, spacing: 5) { Image(systemName: icon).foregroundStyle(tint); Text(value).font(.system(.title3, design: .rounded, weight: .bold)); Text(label).font(.caption).foregroundStyle(QuitNicTheme.secondaryInk) }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4) }
    private func placeholder(_ text: String) -> some View { Text(text).font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk).fixedSize(horizontal: false, vertical: true).padding(.vertical, 4) }
    private func loadProgress() async { serverProgress = ResponseCache.get(ProgressResponse.self, key: "progress", context: context); guard KeychainStore.readToken() != nil else { return }; if let fresh = try? await APIClient.shared.progress() { serverProgress = fresh; try? ResponseCache.put(fresh, key: "progress", lifetime: 300, context: context) } }
}

private struct TrendPreview: View {
    let recordedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(0..<4, id: \.self) { index in
                    VStack(spacing: 6) {
                        Circle()
                            .fill(index < recordedCount ? QuitNicTheme.teal : QuitNicTheme.teal.opacity(0.18))
                            .frame(width: 10, height: 10)
                        Capsule()
                            .fill(QuitNicTheme.teal.opacity(index < recordedCount ? 0.45 : 0.12))
                            .frame(height: [48, 76, 38, 62][index])
                    }
                    .frame(maxWidth: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 96)
            .padding(.horizontal, 10)
            Text(recordedCount == 0
                 ? "Your first Rescue check-in creates the baseline. One more unlocks your trend."
                 : "One more Rescue check-in unlocks your intensity trend.")
                .font(.subheadline)
                .foregroundStyle(QuitNicTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recordedCount == 0
                            ? "Intensity trend preview. Your first Rescue check-in creates the baseline."
                            : "Intensity trend preview. One more Rescue check-in unlocks the trend.")
    }
}

private struct TrendPoint: Identifiable { let date: Date; let intensity: Int; var id: Date { date } }
private struct TriggerPoint: Identifiable { let trigger: String; let count: Int; var id: String { trigger } }
private struct HelpPoint: Identifiable { let name: String; let reduction: Int; let count: Int; var id: String { name } }
