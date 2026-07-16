import SwiftUI

struct DashboardView: View {
    let plan: QuitPlan
    let onCheckIn: () -> Void
    @State private var now = Date()
    private var progress: LocalProgress { ProgressCalculator.calculate(plan: plan, now: now) }

    private var dayNumber: Int {
        max(1, progress.streakDays + 1)
    }

    private var milestone: MilestonePresentation {
        let milestones = [
            (hours: 24, title: "First day", detail: "A full day choosing your goal"),
            (hours: 168, title: "First week", detail: "Seven days of new routines"),
            (hours: 720, title: "First month", detail: "One month of momentum"),
            (hours: 2160, title: "Three months", detail: "A powerful long-term milestone")
        ]
        let elapsedHours = Double(progress.seconds) / 3_600
        let current = milestones.first { elapsedHours < Double($0.hours) }
            ?? milestones[milestones.count - 1]
        let previousHours = milestones.last { Double($0.hours) <= elapsedHours }?.hours ?? 0
        let span = max(1, current.hours - previousHours)
        let fraction = min(1, max(0, (elapsedHours - Double(previousHours)) / Double(span)))
        let remaining = max(0, current.hours - Int(elapsedHours))
        return MilestonePresentation(
            title: current.title,
            detail: current.detail,
            fraction: fraction,
            remainingText: remaining < 48 ? "\(remaining) hours to go" : "\(Int(ceil(Double(remaining) / 24))) days to go"
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HeaderView(dayNumber: dayNumber, hasStarted: progress.seconds > 0)
                    MotivationCard(motivation: plan.motivation)
                    TimelineCard(seconds: progress.seconds)
                    TodayPlanCard(hour: Calendar.current.component(.hour, from: now))
                    Button(action: onCheckIn) {
                        Label("I need help now", systemImage: "wind.circle.fill")
                    }
                    .buttonStyle(QuitNicPrimaryButtonStyle())
                    .accessibilityHint("Opens the craving check-in screen")
                    LazyVGrid(columns: [.init(.flexible()), .init(.flexible())], spacing: 12) {
                        MetricCard(title: "Money saved", value: progress.moneySaved.formatted(.currency(code: "EUR")), icon: "eurosign.circle.fill", tint: QuitNicTheme.teal)
                        MetricCard(title: "Units avoided", value: progress.avoidedUnits.formatted(.number.precision(.fractionLength(0))), icon: "leaf.fill", tint: .green)
                    }
                    MilestoneCard(milestone: milestone)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
            }
            .background(QuitNicTheme.warmBackground.ignoresSafeArea())
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "leaf.fill")
                        .foregroundStyle(QuitNicTheme.teal)
                        .accessibilityHidden(true)
                }
            }
        }.task { while !Task.isCancelled { try? await Task.sleep(for: .seconds(60)); now = .now } }
    }
}

private struct HeaderView: View {
    let dayNumber: Int
    let hasStarted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hasStarted ? "DAY \(dayNumber)" : "YOUR JOURNEY")
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(QuitNicTheme.teal)
            Text(hasStarted ? "You’re building momentum" : "Your quit begins soon")
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(QuitNicTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(hasStarted ? "Every craving you move through is evidence that you can do this." : "Your plan is ready. Start with one small choice at a time.")
                .font(.subheadline)
                .foregroundStyle(QuitNicTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MotivationCard: View {
    let motivation: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "quote.opening")
                .font(.title3.weight(.semibold))
                .foregroundStyle(QuitNicTheme.teal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("You chose this for")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                Text(motivation)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .quitNicCard()
        .accessibilityElement(children: .combine)
    }
}

private struct TodayPlanCard: View {
    let hour: Int

    private var plan: (title: String, detail: String, icon: String) {
        switch hour {
        case 5..<11:
            ("Protect your morning", "Before your usual first trigger, drink water and take a two-minute walk.", "sunrise.fill")
        case 11..<15:
            ("After lunch plan", "Before acting on an urge, change location for five minutes and let the wave pass.", "fork.knife")
        case 15..<20:
            ("Protect your afternoon", "Keep a simple alternative ready: water, fresh air, or a message to someone supportive.", "figure.walk")
        default:
            ("Ease into tonight", "Set up one small comfort routine now so you do not have to decide during a craving.", "moon.stars.fill")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: plan.icon)
                .font(.headline)
                .foregroundStyle(QuitNicTheme.teal)
                .frame(width: 36, height: 36)
                .background(QuitNicTheme.teal.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR NEXT STEP")
                    .font(.caption.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(QuitNicTheme.teal)
                Text(plan.title).font(.headline)
                Text(plan.detail)
                    .font(.subheadline)
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .quitNicCard()
        .accessibilityElement(children: .combine)
    }
}

private struct TimelineCard: View {
    let seconds: Int
    var body: some View {
        let days = seconds / 86_400, hours = (seconds % 86_400) / 3600, minutes = (seconds % 3600) / 60
        VStack(alignment: .leading, spacing: 10) {
            Label("Nicotine-free time", systemImage: "clock.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("\(days)d  \(hours)h  \(minutes)m")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(
            LinearGradient(colors: [QuitNicTheme.navy, QuitNicTheme.navy.opacity(0.86)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(tint.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(title)
                .font(.caption)
                .foregroundStyle(QuitNicTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity, minHeight: 116, alignment: .leading)
        .quitNicCard()
        .accessibilityElement(children: .combine)
    }
}

private struct MilestonePresentation {
    let title: String
    let detail: String
    let fraction: Double
    let remainingText: String
}

private struct MilestoneCard: View {
    let milestone: MilestonePresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.title2)
                    .foregroundStyle(QuitNicTheme.teal)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Next milestone")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuitNicTheme.secondaryInk)
                    Text(milestone.title)
                        .font(.headline)
                    Text(milestone.detail)
                        .font(.subheadline)
                        .foregroundStyle(QuitNicTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(milestone.remainingText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuitNicTheme.ink)
                    .multilineTextAlignment(.trailing)
            }
            SwiftUI.ProgressView(value: milestone.fraction)
                .tint(QuitNicTheme.teal)
                .accessibilityLabel("Milestone progress")
                .accessibilityValue(milestone.fraction.formatted(.percent.precision(.fractionLength(0))))
        }
        .quitNicCard()
    }
}
