import SwiftData
import SwiftUI
import UIKit

struct CheckInView: View {
    private enum Step: Int {
        case welcome, assess, reset, reflect, complete
    }

    private let triggers = ["Stress", "Coffee", "Social", "Boredom", "After a meal", "Other"]
    private let intervention = "Two-minute breathing reset"
    private let fullDuration = 120

    @Environment(\.modelContext) private var context
    @State private var step: Step = .welcome
    @State private var startingIntensity = 5.0
    @State private var endingIntensity = 5.0
    @State private var selectedTrigger: String?
    @State private var resisted = true
    @State private var secondsRemaining = 120
    @State private var startedAt = Date()
    @State private var breathingExpanded = false

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-reset")
    }

    private var sessionDuration: Int {
        isUITesting ? 2 : fullDuration
    }

    var body: some View {
        NavigationStack {
            ZStack {
                QuitNicTheme.warmBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        stepIndicator
                        switch step {
                        case .welcome: welcomeView
                        case .assess: assessmentView
                        case .reset: resetView
                        case .reflect: reflectionView
                        case .complete: completionView
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("Rescue")
            .navigationBarTitleDisplayMode(.large)
            .task(id: step) {
                guard step == .reset else { return }
                await runReset()
            }
        }
    }

    @ViewBuilder private var stepIndicator: some View {
        if step != .welcome && step != .complete {
            VStack(alignment: .leading, spacing: 7) {
                Text("Step \(step.rawValue) of 3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                HStack(spacing: 8) {
                    ForEach(1...3, id: \.self) { index in
                        Capsule()
                            .fill(index <= step.rawValue ? QuitNicTheme.teal : Color.primary.opacity(0.12))
                            .frame(height: 5)
                    }
                    .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .accessibilityElement(children: .combine)
        }
    }

    private var welcomeView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("A craving is a wave.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(QuitNicTheme.ink)
                Text("You don’t have to solve the whole day. Let’s move through the next two minutes together.")
                    .font(.body)
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ZStack {
                Circle()
                    .fill(QuitNicTheme.mint.opacity(0.75))
                    .frame(width: 190, height: 190)
                Circle()
                    .stroke(QuitNicTheme.teal.opacity(0.22), lineWidth: 18)
                    .frame(width: 145, height: 145)
                Image(systemName: "wind")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(QuitNicTheme.teal)
            }
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 13) {
                RescueBenefit(icon: "timer", text: "A guided two-minute reset")
                RescueBenefit(icon: "hand.tap.fill", text: "Gentle breathing and haptic pacing")
                RescueBenefit(icon: "chart.line.downtrend.xyaxis", text: "Track what helps you over time")
            }
            .quitNicCard()

            Button("Start a two-minute reset") {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                step = .assess
            }
            .buttonStyle(QuitNicPrimaryButtonStyle())
            .accessibilityIdentifier("startRescueButton")
        }
    }

    private var assessmentView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("What’s happening right now?")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("A quick snapshot helps QuitNic learn your patterns.")
                    .foregroundStyle(QuitNicTheme.secondaryInk)
            }

            IntensityControl(title: "Craving intensity", value: $startingIntensity)
                .quitNicCard()

            VStack(alignment: .leading, spacing: 14) {
                Text("What triggered it?")
                    .font(.headline)
                FlowLayout(spacing: 10) {
                    ForEach(triggers, id: \.self) { trigger in
                        TriggerChip(title: trigger, isSelected: selectedTrigger == trigger) {
                            selectedTrigger = trigger
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                }
            }
            .quitNicCard()

            Button("Continue") {
                startedAt = .now
                secondsRemaining = sessionDuration
                step = .reset
            }
            .buttonStyle(QuitNicPrimaryButtonStyle())
            .disabled(selectedTrigger == nil)
            .opacity(selectedTrigger == nil ? 0.45 : 1)
            .accessibilityHint(selectedTrigger == nil ? "Select a trigger first" : "Starts the breathing reset")
        }
    }

    private var resetView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Breathing reset")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(breathingExpanded ? "Breathe out slowly" : "Breathe in gently")
                    .font(.headline)
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: .infinity)

            ZStack {
                Circle()
                    .stroke(QuitNicTheme.teal.opacity(0.16), lineWidth: 24)
                    .frame(width: 250, height: 250)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [QuitNicTheme.mint, QuitNicTheme.teal.opacity(0.72)],
                            center: .center,
                            startRadius: 15,
                            endRadius: 120
                        )
                    )
                    .frame(width: 185, height: 185)
                    .scaleEffect(breathingExpanded ? 1.25 : 0.72)
                    .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathingExpanded)
                VStack(spacing: 4) {
                    Text(timeText)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .monospacedDigit()
                    Text("remaining")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(QuitNicTheme.navy)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(secondsRemaining) seconds remaining")
            .onAppear { breathingExpanded = true }

            Text("Let the feeling rise and fall without fighting it. Your only task is the next breath.")
                .multilineTextAlignment(.center)
                .foregroundStyle(QuitNicTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            Button("Finish early") { step = .reflect }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(QuitNicTheme.teal)
                .accessibilityIdentifier("finishRescueEarlyButton")
        }
        .frame(maxWidth: .infinity)
    }

    private var reflectionView: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 8) {
                Text("How do you feel now?")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("There’s no wrong result. Honest feedback makes future support more useful.")
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            IntensityControl(title: "Intensity after reset", value: $endingIntensity)
                .quitNicCard()

            Button {
                resisted.toggle()
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: resisted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(resisted ? QuitNicTheme.teal : QuitNicTheme.secondaryInk)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("I resisted the craving")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Tap to change the outcome")
                            .font(.caption)
                            .foregroundStyle(QuitNicTheme.secondaryInk)
                    }
                    Spacer()
                }
                .quitNicCard()
            }
            .buttonStyle(.plain)
            .accessibilityValue(resisted ? "Selected" : "Not selected")

            Button("Save result") { save() }
                .buttonStyle(QuitNicPrimaryButtonStyle())
                .accessibilityIdentifier("saveRescueButton")
        }
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(QuitNicTheme.mint)
                    .frame(width: 132, height: 132)
                Image(systemName: resisted ? "checkmark" : "heart.fill")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(QuitNicTheme.teal)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("You moved through it.")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(completionMessage)
                    .foregroundStyle(QuitNicTheme.secondaryInk)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                OutcomeMetric(value: "\(Int(startingIntensity))", label: "Before")
                Image(systemName: "arrow.right")
                    .foregroundStyle(QuitNicTheme.teal)
                    .accessibilityHidden(true)
                OutcomeMetric(value: "\(Int(endingIntensity))", label: "After")
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Intensity changed from \(Int(startingIntensity)) to \(Int(endingIntensity))")

            Button("Done") { reset() }
                .buttonStyle(QuitNicPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    private var timeText: String {
        String(format: "%d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private var completionMessage: String {
        let change = Int(startingIntensity) - Int(endingIntensity)
        if change > 0 { return "The intensity dropped by \(change) point\(change == 1 ? "" : "s"). That result is now part of your personal pattern history." }
        if change == 0 { return "You stayed with the feeling and recorded what happened. That still builds useful evidence." }
        return "Some waves get stronger before they pass. You recorded it honestly, and you can choose another support step now."
    }

    @MainActor private func runReset() async {
        let impact = UIImpactFeedbackGenerator(style: .soft)
        while step == .reset && secondsRemaining > 0 {
            if secondsRemaining % 4 == 0 { impact.impactOccurred(intensity: 0.55) }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, step == .reset else { return }
            secondsRemaining -= 1
        }
        if step == .reset {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            step = .reflect
        }
    }

    private func save() {
        let completedAt = Date()
        let duration = max(0, Int(completedAt.timeIntervalSince(startedAt)))
        let trigger = selectedTrigger ?? "Other"
        let session = RescueSession(
            startingIntensity: Int(startingIntensity),
            endingIntensity: Int(endingIntensity),
            trigger: trigger,
            intervention: intervention,
            startedAt: startedAt,
            completedAt: completedAt,
            resisted: resisted,
            durationSeconds: duration
        )
        let checkIn = CravingCheckIn(
            intensity: Int(startingIntensity),
            trigger: trigger,
            copingAction: intervention,
            note: "Intensity after reset: \(Int(endingIntensity))/10",
            resisted: resisted,
            occurredAt: startedAt
        )
        context.insert(session)
        context.insert(checkIn)
        try? OutboxService.enqueue(checkIn: checkIn, context: context)
        try? context.save()
        step = .complete
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await OutboxService.flush(context: context) }
    }

    private func reset() {
        step = .welcome
        startingIntensity = 5
        endingIntensity = 5
        selectedTrigger = nil
        resisted = true
        secondsRemaining = fullDuration
        breathingExpanded = false
    }
}

private struct RescueBenefit: View {
    let icon: String
    let text: String

    var body: some View {
        Label(text, systemImage: icon)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.primary)
            .symbolRenderingMode(.hierarchical)
            .accessibilityElement(children: .combine)
    }
}

private struct IntensityControl: View {
    let title: String
    @Binding var value: Double

    private var descriptor: String {
        switch Int(value) {
        case 1...3: "Mild"
        case 4...6: "Moderate"
        case 7...8: "Strong"
        default: "Very strong"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(descriptor)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(QuitNicTheme.secondaryInk)
                }
                Spacer()
                Text("\(Int(value))")
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(QuitNicTheme.teal)
            }
            Slider(value: $value, in: 1...10, step: 1)
                .tint(QuitNicTheme.teal)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) out of 10, \(descriptor)")
            HStack {
                Text("1").accessibilityHidden(true)
                Spacer()
                Text("10").accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(QuitNicTheme.secondaryInk)
        }
    }
}

private struct TriggerChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if isSelected { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? .white : QuitNicTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                isSelected ? QuitNicTheme.navy : Color.primary.opacity(0.07),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct OutcomeMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(QuitNicTheme.ink)
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(QuitNicTheme.secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .quitNicCard()
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 0
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
