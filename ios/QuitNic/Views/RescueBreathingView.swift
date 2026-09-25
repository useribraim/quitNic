import SwiftUI

/// The quiet first stage of Rescue. Sequencing remains in `CheckInView`; this component
/// owns only the presentation and accessibility contract for breathing, exit, and the
/// explicit Quick Log escape hatch.
struct RescueBreathingView: View {
    let inhaling: Bool
    let breathingLabelVisible: Bool
    let reduceMotion: Bool
    let onClose: () -> Void
    let onQuickLog: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack {
            HStack {
                HorizonCloseButton(action: onClose)
                Spacer()
                Button("Quick log", action: onQuickLog)
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, HorizonLayout.content)
                    .frame(minHeight: 44)
                    .background(.black.opacity(0.48), in: Capsule())
                    .accessibilityIdentifier("quickLogButton")
                    .accessibilityHint("Records a craving without the breathing reset")
            }
            .padding(.horizontal, HorizonLayout.section)
            .padding(.top, HorizonLayout.compact)

            Spacer()

            VStack(spacing: HorizonLayout.content) {
                Text("Breathe.")
                    .font(HorizonType.display(52))
                    .fontWidth(.condensed)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier("rescueBreatheWord")

                Text(inhaling ? "in" : "out")
                    .font(HorizonType.body(.title3))
                    .foregroundStyle(.white.opacity(0.75))
                    .contentTransition(.opacity)
                    .opacity(breathingLabelVisible ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Breathe")
            .accessibilityValue(breathingLabelVisible ? (inhaling ? "Breathe in" : "Breathe out") : "")

            Spacer()

            VStack(spacing: HorizonLayout.control) {
                if reduceMotion {
                    Text("Breathe in for four, then out for four. Animation is off.")
                        .font(HorizonType.body(.footnote))
                        .foregroundStyle(.white.opacity(0.78))
                }
                Button("Continue to check-in", action: onContinue)
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, HorizonLayout.section)
                    .frame(minHeight: 44)
                    .background(.black.opacity(0.48), in: Capsule())
                    .accessibilityHint("Ends the breathing reset and opens reflection")
                    .accessibilityIdentifier("continueRescueButton")
                Text("About two minutes · you can close at any time")
                    .font(HorizonType.body(.footnote))
                    .foregroundStyle(.white.opacity(0.72))
            }
            .padding(.bottom, HorizonLayout.spacious)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}
