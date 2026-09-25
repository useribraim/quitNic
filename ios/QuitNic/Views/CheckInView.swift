import SwiftData
import SwiftUI
import UIKit

enum CheckInStartMode: String, Identifiable, Codable {
    case rescue
    case quickLog
    var id: String { rawValue }
}

/// A craving is the one moment where the right move is to lose ground on purpose.
///
/// The camera retreats from earned depth to the whole valley, holds there while the
/// breathing runs, and comes home. Whatever is happening is one pixel wide and
/// somewhere near the middle. Nothing is asked until it is over: the previous flow
/// collected a trigger and an intensity rating first, which is asking someone
/// mid-craving to fill in a form.
struct CheckInView: View {
    private enum Step: String, Codable {
        case breathe, reflect, complete, quickLog
    }

    private enum Outcome: String, Codable {
        case resisted, usedNicotine
    }

    private struct Draft: Codable {
        let mode: CheckInStartMode
        let step: Step
        let startingIntensity: Double
        let endingIntensity: Double
        let selectedTrigger: String?
        let customTrigger: String
        let outcome: Outcome?
        let selectedCopingAction: String?
        let startedAt: Date
    }

    private struct RecentLogPreset {
        let intensity: Double
        let trigger: String?
        let outcome: Outcome?
        let copingAction: String?

        var summary: String {
            let triggerText = trigger ?? "No trigger"
            let outcomeText = outcome == .usedNicotine ? "used nicotine" : "moved through"
            return "\(triggerText) · \(Int(intensity))/10 · \(outcomeText)"
        }
    }

    /// The shape of the pull-back, in seconds. Six seconds to travel the whole chain
    /// so it reads as falling away rather than scrolling; ten to come back, because
    /// returning should not feel like being dropped.
    private struct Timing {
        let pullBack: Double
        let hold: Double
        let returning: Double
        var total: Double { pullBack + hold + returning }

        static let full = Timing(pullBack: 6, hold: 104, returning: 10)
        /// Same sequence, same order, fast enough for a UI test to sit through — but
        /// not so fast that the breathing screen is gone before the test can assert
        /// nothing is being asked on it.
        static let uiTesting = Timing(pullBack: 1.5, hold: 2, returning: 1.5)
    }

    /// Where the world stands for this streak — what Rescue retreats from and returns to.
    let earnedDepth: Double
    private let startMode: CheckInStartMode

    private let triggers = ["Stress", "Coffee", "Social", "Boredom", "After a meal", "Other"]
    private let quickCopingActions = ["Changed scene", "Drank water", "Took a short walk", "Reached out"]
    private let intervention = "Two-minute breathing reset"
    /// One inhale plus one exhale. The warmth animation and the spoken instruction are
    /// both driven from this so they cannot drift apart.
    private let breathPhaseSeconds = 4.0

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .breathe
    /// Asked retrospectively. People are bad at rating a thing they are inside of, so
    /// "how bad was it" after the fact is more honest than a slider mid-craving.
    @State private var startingIntensity = 5.0
    @State private var endingIntensity = 5.0
    @State private var selectedTrigger: String?
    @State private var customTrigger = ""
    @State private var outcome: Outcome?
    @State private var selectedCopingAction: String?
    @State private var showCopingActions = false
    @State private var recentTriggers: [String] = []
    @State private var showAllTriggers = false
    @State private var startedAt = Date()
    /// Fixed when the cover opens. Rescue runs for two minutes, so the light must not
    /// re-read the wall clock on every animation frame of the pull-back.
    @State private var openedAt = Date()
    @State private var depth: Double
    @State private var warmth: Double = 0
    @State private var inhaling = false
    @State private var breathingLabelVisible = false
    @State private var resetElapsed = 0
    // Held so a mis-tapped "I used nicotine" can be undone from the completion screen
    // before it quietly resets a streak the person actually kept.
    @State private var savedCheckIn: CravingCheckIn?
    @State private var savedSession: RescueSession?
    @State private var didUndo = false
    /// True when this entry skipped the breathing reset entirely. Kept separate from
    /// `Step` because it changes what gets saved (no `RescueSession`, since nothing was
    /// actually measured) and what the completion screen honestly says.
    @State private var isQuickLog = false
    @State private var isSaving = false
    @State private var recentPreset: RecentLogPreset?
    @State private var showExitChoices = false
    @State private var didRestoreDraft = false
    // A full-screen cover is destroyed between openings. Write the small, local-only
    // draft synchronously at the user's explicit "Keep for later" boundary so it
    // survives both dismissal and process death.
    private static let draftStorageKey = "checkInDraftV1"

    init(earnedDepth: Double, startMode: CheckInStartMode = .rescue) {
        self.earnedDepth = earnedDepth
        self.startMode = startMode
        _depth = State(initialValue: earnedDepth)
        _step = State(initialValue: startMode == .quickLog ? .quickLog : .breathe)
        _isQuickLog = State(initialValue: startMode == .quickLog)
    }

    private var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("-ui-testing-reset")
    }

    private var timing: Timing { isUITesting ? .uiTesting : .full }

    var body: some View {
        ZStack {
            ZoomWorldView(depth: depth, date: openedAt, warmth: warmth)

            switch step {
            case .breathe: breatheView
            case .reflect: questionsView
            case .complete: questionsView
            case .quickLog: questionsView
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if startMode == .quickLog { PerformanceSignposts.quickLogAppeared() }
        }
        .onChange(of: step) { _, newStep in
            if newStep == .quickLog { PerformanceSignposts.quickLogAppeared() }
        }
        // No identifier on this container: an identifier set on a parent is inherited by
        // every top-level element beneath it, which silently replaced the quick-log
        // button's own identifier and made it unfindable. Screens are identified by the
        // elements actually on them.
        // Plain `.task`, not `.task(id:)`: keying it on a value the sequence itself
        // mutates re-created the task mid-flight.
        .task {
            restoreDraftIfAvailable()
            guard step == .breathe else { return }
            await runPullBack()
        }
        .onChange(of: draftFingerprint) { _, _ in persistDraftIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persistDraftIfNeeded() }
        }
        .interactiveDismissDisabled(hasMeaningfulDraft)
        .confirmationDialog("Leave this unfinished log?", isPresented: $showExitChoices, titleVisibility: .visible) {
            Button("Keep for later") {
                persistDraftIfNeeded()
                dismiss()
            }
            Button("Discard log", role: .destructive) {
                clearStoredDraft()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep it and QuitNic will restore these answers the next time you open this flow.")
        }
        .task(id: isQuickLog) {
            guard isQuickLog else { return }
            loadRecentPreset()
        }
    }

    // MARK: - The pull-back

    /// The reset stays quiet, but it never traps somebody who arrived by mistake.
    private var breatheView: some View {
        RescueBreathingView(
            inhaling: inhaling,
            breathingLabelVisible: breathingLabelVisible,
            reduceMotion: reduceMotion,
            onClose: requestExit,
            onQuickLog: beginQuickLog,
            onContinue: finishResetEarly
        )
    }

    @MainActor private func runPullBack() async {
        startedAt = .now
        let impact = UIImpactFeedbackGenerator(style: .soft)
        impact.impactOccurred()

        // Reduce Motion cuts: the world still shows the correct depth, it just never
        // animates to it.
        if reduceMotion {
            depth = 0
        } else {
            withAnimation(.easeOut(duration: timing.pullBack)) { depth = 0 }
        }
        guard await sleep(timing.pullBack) else { return }

        // Breathing runs on the light axis, not depth — warmth rises on the inhale and
        // cools on the exhale, so the world itself is doing the breathing.
        withAnimation(.easeInOut(duration: 0.6)) { breathingLabelVisible = true }
        // Imperceptible outward drift, so the camera never visibly stops.
        if !reduceMotion {
            withAnimation(.linear(duration: timing.hold)) { depth = -0.15 }
        }

        let holdEnds = Date().addingTimeInterval(timing.hold)
        let phase = isUITesting ? timing.hold / 2 : breathPhaseSeconds
        while Date() < holdEnds {
            inhaling.toggle()
            if reduceMotion {
                warmth = inhaling ? 1 : 0
            } else {
                withAnimation(.easeInOut(duration: phase)) { warmth = inhaling ? 1 : 0 }
            }
            impact.impactOccurred(intensity: 0.55)
            guard await sleep(phase) else { return }
        }

        withAnimation(.easeInOut(duration: 0.6)) {
            breathingLabelVisible = false
            warmth = 0
        }
        // You come home.
        if reduceMotion {
            depth = earnedDepth
        } else {
            withAnimation(.easeInOut(duration: timing.returning)) { depth = earnedDepth }
        }
        guard await sleep(timing.returning) else { return }

        // Derive from the clock rather than counting ticks, so time spent with the app
        // suspended or the screen locked does not stretch the recorded session.
        resetElapsed = min(Int(timing.total.rounded()), max(0, Int(Date().timeIntervalSince(startedAt))))
        endingIntensity = startingIntensity
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.5)) { step = .reflect }
    }

    /// Returns false when the wait was cut short. Cancellation must stop the sequence,
    /// not be swallowed — a `try?` here made every sleep return instantly once the task
    /// was cancelled, so the whole two minutes ran to completion in one frame and the
    /// questions appeared immediately.
    private func sleep(_ seconds: Double) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            return step == .breathe
        } catch {
            return false
        }
    }

    private func finishResetEarly() {
        guard step == .breathe else { return }
        resetElapsed = max(0, Int(Date().timeIntervalSince(startedAt)))
        endingIntensity = startingIntensity
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.easeInOut(duration: 0.3)) { step = .reflect }
    }

    // MARK: - Afterwards

    /// Everything that used to be asked first. A sheet rather than the world, because
    /// this part genuinely is a form and pretending otherwise would make it harder to
    /// fill in.
    private var questionsView: some View {
        NavigationStack {
            ZStack {
                HorizonBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: HorizonLayout.roomy) {
                        if didRestoreDraft {
                            Label("Unfinished log restored", systemImage: "arrow.counterclockwise")
                                .font(HorizonType.body(.caption).weight(.semibold))
                                .foregroundStyle(HorizonTheme.accentText)
                                .accessibilityIdentifier("restoredCheckInDraft")
                        }
                        switch step {
                        case .reflect: reflectionView
                        case .complete: completionView
                        case .quickLog: quickLogView
                        case .breathe: EmptyView()
                        }
                    }
                    .padding(.horizontal, HorizonLayout.section)
                    .padding(.vertical, HorizonLayout.content)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(step == .quickLog ? "Quick log" : (step == .complete ? "Saved" : "Rescue"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { HorizonCloseButton(action: requestExit) }
            }
            .safeAreaInset(edge: .bottom) {
                if step == .quickLog { quickLogSaveBar }
            }
        }
        .transition(.opacity)
    }

    private var quickLogView: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.section) {
            if let recentPreset {
                Button {
                    apply(recentPreset)
                } label: {
                    HStack(spacing: HorizonLayout.control) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(HorizonType.body())
                        VStack(alignment: .leading, spacing: HorizonLayout.micro) {
                            Text("Use last details")
                                .font(HorizonType.body(.headline))
                            Text(recentPreset.summary)
                                .font(HorizonType.body(.caption))
                                .foregroundStyle(HorizonTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.down")
                            .foregroundStyle(HorizonTheme.accentText)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, HorizonLayout.control)
                    .padding(.vertical, HorizonLayout.compact)
                    .background(HorizonTheme.forest.opacity(0.72), in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Prefills this log; you can review everything before saving")
                .accessibilityIdentifier("useLastLogDetailsButton")
            }

            IntensityControl(title: "Craving intensity", value: $startingIntensity)
                .horizonCard()

            triggerPicker(optional: true)

            outcomePicker(title: "What happened?")

            Button {
                showCopingActions.toggle()
            } label: {
                HStack {
                    Label(selectedCopingAction ?? "Add what helped · Optional", systemImage: "plus.circle")
                        .font(HorizonType.body(.subheadline).weight(.semibold))
                    Spacer()
                    Image(systemName: showCopingActions ? "chevron.up" : "chevron.down")
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(HorizonTheme.accentText)
            .accessibilityIdentifier("addCopingActionButton")

            if showCopingActions {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: HorizonLayout.compact)], spacing: HorizonLayout.compact) {
                    ForEach(quickCopingActions, id: \.self) { action in
                        TriggerChip(title: action, isSelected: selectedCopingAction == action) {
                            selectedCopingAction = selectedCopingAction == action ? nil : action
                        }
                        .accessibilityIdentifier("copingAction_\(action)")
                        .accessibilityValue(selectedCopingAction == action ? "Selected" : "Not selected")
                    }
                }
            }

        }
    }

    private var quickLogSaveBar: some View {
        Button("Save") { save() }
            .buttonStyle(HorizonPrimaryButtonStyle())
            .disabled(outcome == nil || isSaving)
            .opacity(outcome == nil || isSaving ? 0.45 : 1)
            .accessibilityIdentifier("saveQuickLogButton")
            .padding(.horizontal, HorizonLayout.section)
            .padding(.vertical, HorizonLayout.compact)
            .background(HorizonTheme.deepCobalt.opacity(0.98))
    }

    private var reflectionView: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.roomy) {
            VStack(alignment: .leading, spacing: HorizonLayout.compact) {
                Text("How do you feel now?")
                    .font(HorizonType.body(.title2).weight(.bold))
                Text("There’s no wrong result. Honest feedback makes future support more useful.")
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Asked in this order on purpose: recalling the peak first gives the "now"
            // rating something to sit against.
            IntensityControl(title: "How bad was it?", value: $startingIntensity)
                .horizonCard()
            IntensityControl(title: "Intensity now", value: $endingIntensity)
                .horizonCard()

            triggerPicker(optional: false)

            outcomePicker(title: "What happened?")

            Button("Save result") { save() }
                .buttonStyle(HorizonPrimaryButtonStyle())
                .disabled(outcome == nil || isSaving)
                .opacity(outcome == nil || isSaving ? 0.45 : 1)
                .accessibilityIdentifier("saveRescueButton")
        }
    }

    private func triggerPicker(optional: Bool) -> some View {
        VStack(alignment: .leading, spacing: HorizonLayout.content) {
            HStack(alignment: .firstTextBaseline) {
                Text("What triggered it?")
                    .font(HorizonType.body(.headline))
                Spacer()
                if optional {
                    Text("Optional")
                        .font(HorizonType.body(.caption).weight(.semibold))
                        .foregroundStyle(HorizonTheme.secondaryText)
                }
            }
            FlowLayout(spacing: HorizonLayout.control) {
                ForEach(optional && !showAllTriggers ? compactTriggers : triggers, id: \.self) { trigger in
                    TriggerChip(title: trigger, isSelected: selectedTrigger == trigger) {
                        selectedTrigger = selectedTrigger == trigger ? nil : trigger
                    }
                }
                if optional {
                    Button(showAllTriggers ? "Fewer" : "More") {
                        showAllTriggers.toggle()
                    }
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(HorizonTheme.accentText)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("moreTriggersButton")
                }
            }
            if selectedTrigger == "Other" {
                TextField("Describe the trigger", text: $customTrigger)
                    .textInputAutocapitalization(.sentences)
                    .padding(HorizonLayout.control)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
                    .accessibilityIdentifier("customTriggerField")
            }
        }
        .horizonCard()
    }

    private func outcomePicker(title: String) -> some View {
        VStack(alignment: .leading, spacing: HorizonLayout.control) {
            Text(title)
                .font(HorizonType.body(.headline))
            OutcomeChoice(
                title: "I resisted the craving",
                detail: "You did not use nicotine this time.",
                isSelected: outcome == .resisted
            ) {
                outcome = .resisted
            }
            OutcomeChoice(
                title: "I used nicotine",
                detail: "No judgement. This helps keep your progress honest.",
                isSelected: outcome == .usedNicotine
            ) {
                outcome = .usedNicotine
            }
        }
        .horizonCard()
    }

    private var completionView: some View {
        VStack(spacing: HorizonLayout.roomy) {
            ZStack {
                Circle()
                    .fill(HorizonTheme.accentText.opacity(0.24))
                    .frame(width: 132, height: 132)
                Image(systemName: resisted ? "checkmark" : "heart.fill")
                    .font(HorizonType.display(48).weight(.bold))
                    .foregroundStyle(HorizonTheme.accentText)
            }
            .accessibilityHidden(true)

            VStack(spacing: HorizonLayout.compact) {
                Text(isQuickLog ? "Logged." : "You moved through it.")
                    .font(HorizonType.body(.title).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(completionMessage)
                    .foregroundStyle(HorizonTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // A quick log never measured a "before" and "after" — there was no reset in
            // between to compare across. Showing this comparison would imply an effect
            // that was never observed.
            if !isQuickLog {
                HStack(spacing: HorizonLayout.control) {
                    OutcomeMetric(value: "\(Int(startingIntensity))", label: "Before")
                    Image(systemName: "arrow.right")
                        .foregroundStyle(HorizonTheme.accentText)
                        .accessibilityHidden(true)
                    OutcomeMetric(value: "\(Int(endingIntensity))", label: "After")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Intensity changed from \(Int(startingIntensity)) to \(Int(endingIntensity))")
            }

            if usedNicotine == true && !didUndo {
                VStack(spacing: HorizonLayout.compact) {
                    Text("This reset your nicotine-free timer.")
                        .font(HorizonType.body(.caption))
                        .foregroundStyle(HorizonTheme.secondaryText)
                    Button {
                        undoSlip()
                    } label: {
                        Label("Undo — I didn’t actually slip", systemImage: "arrow.uturn.backward")
                            .font(HorizonType.body(.subheadline).weight(.semibold))
                            .foregroundStyle(HorizonTheme.accentText)
                            .padding(.horizontal, HorizonLayout.content)
                            .padding(.vertical, HorizonLayout.control)
                            .background(HorizonTheme.accent.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("undoSlipButton")
                    .accessibilityHint("Removes this slip and restores your streak")
                }
                .transition(.opacity)
            } else if didUndo {
                Label("Slip removed. Your streak is intact.", systemImage: "checkmark.circle.fill")
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(HorizonTheme.accentText)
            }

            Button("Done") { dismiss() }
                .buttonStyle(HorizonPrimaryButtonStyle())
                .accessibilityHint("Returns to Today with your progress updated")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, HorizonLayout.spacious)
        .animation(.easeInOut(duration: 0.2), value: didUndo)
    }

    private var completionMessage: String {
        if isQuickLog {
            return resisted
                ? "That craving is now part of your pattern history, no reset required. Naming it is what makes the data useful."
                : "Thank you for being honest — that is what keeps this useful. A reset is still one tap away next time."
        }
        let change = Int(startingIntensity) - Int(endingIntensity)
        if change > 0 { return "The intensity dropped by \(change) point\(change == 1 ? "" : "s"). That result is now part of your personal pattern history." }
        if change == 0 { return "You stayed with the feeling and recorded what happened. That still builds useful evidence." }
        return "Some waves get stronger before they pass. You recorded it honestly, and you can choose another support step now."
    }

    private func beginQuickLog() {
        PerformanceSignposts.quickLogRequested()
        isQuickLog = true
        startingIntensity = 5
        endingIntensity = 5
        selectedTrigger = nil
        customTrigger = ""
        outcome = nil
        selectedCopingAction = nil
        // Stop the sequence where it stands rather than snapping home: somebody taking
        // this exit is leaving, not arriving.
        withAnimation(.easeInOut(duration: 0.4)) { step = .quickLog }
    }

    private var hasMeaningfulDraft: Bool {
        switch step {
        case .reflect: true
        case .quickLog:
            startingIntensity != 5
                || selectedTrigger != nil
                || !customTrigger.isEmpty
                || outcome != nil
                || selectedCopingAction != nil
        case .breathe, .complete: false
        }
    }

    private var draftFingerprint: String {
        [
            step.rawValue,
            String(startingIntensity),
            String(endingIntensity),
            selectedTrigger ?? "",
            customTrigger,
            outcome?.rawValue ?? "",
            selectedCopingAction ?? ""
        ].joined(separator: "|")
    }

    private func requestExit() {
        if hasMeaningfulDraft {
            showExitChoices = true
        } else {
            dismiss()
        }
    }

    private func persistDraftIfNeeded() {
        guard hasMeaningfulDraft else {
            if step == .complete { clearStoredDraft() }
            return
        }
        let draft = Draft(
            mode: isQuickLog ? .quickLog : .rescue,
            step: step,
            startingIntensity: startingIntensity,
            endingIntensity: endingIntensity,
            selectedTrigger: selectedTrigger,
            customTrigger: customTrigger,
            outcome: outcome,
            selectedCopingAction: selectedCopingAction,
            startedAt: startedAt
        )
        guard let data = try? JSONEncoder().encode(draft) else { return }
        UserDefaults.standard.set(data.base64EncodedString(), forKey: Self.draftStorageKey)
    }

    private func restoreDraftIfAvailable() {
        guard !didRestoreDraft,
              let storedDraft = UserDefaults.standard.string(forKey: Self.draftStorageKey),
              let data = Data(base64Encoded: storedDraft),
              let draft = try? JSONDecoder().decode(Draft.self, from: data),
              draft.step == .quickLog || draft.step == .reflect else { return }
        didRestoreDraft = true
        step = draft.step
        isQuickLog = draft.mode == .quickLog
        startingIntensity = draft.startingIntensity
        endingIntensity = draft.endingIntensity
        selectedTrigger = draft.selectedTrigger
        customTrigger = draft.customTrigger
        outcome = draft.outcome
        selectedCopingAction = draft.selectedCopingAction
        startedAt = draft.startedAt
        depth = earnedDepth
    }

    private func clearStoredDraft() {
        UserDefaults.standard.removeObject(forKey: Self.draftStorageKey)
        didRestoreDraft = false
    }

    private func loadRecentPreset() {
        var descriptor = FetchDescriptor<CravingCheckIn>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 12
        let recent = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        recentTriggers = recent.compactMap { checkIn in
            guard checkIn.trigger != "Not specified", seen.insert(checkIn.trigger).inserted else { return nil }
            return checkIn.trigger
        }
        guard let latest = recent.first else { return }
        let knownTrigger = latest.trigger == "Not specified" ? nil : latest.trigger
        let previousOutcome: Outcome?
        switch latest.usedNicotine {
        case .some(true): previousOutcome = .usedNicotine
        case .some(false): previousOutcome = .resisted
        case .none: previousOutcome = nil
        }
        recentPreset = RecentLogPreset(
            intensity: Double(latest.intensity),
            trigger: knownTrigger,
            outcome: previousOutcome,
            copingAction: latest.copingAction == "Quick log" ? nil : latest.copingAction
        )
    }

    private func apply(_ preset: RecentLogPreset) {
        startingIntensity = min(10, max(1, preset.intensity))
        endingIntensity = startingIntensity
        outcome = preset.outcome
        selectedCopingAction = preset.copingAction
        if let trigger = preset.trigger {
            if triggers.contains(trigger) {
                selectedTrigger = trigger
                customTrigger = ""
            } else {
                selectedTrigger = "Other"
                customTrigger = trigger
            }
        } else {
            selectedTrigger = nil
            customTrigger = ""
        }
    }

    private var compactTriggers: [String] {
        var choices: [String] = []
        for trigger in recentTriggers + ["Stress", "Coffee", "Boredom"] where !choices.contains(trigger) {
            choices.append(trigger)
            if choices.count == 3 { break }
        }
        return choices
    }

    private func save() {
        guard !isSaving, outcome != nil else { return }
        isSaving = true
        clearStoredDraft()
        let completedAt = Date()
        let trigger: String
        if selectedTrigger == "Other" {
            let trimmed = customTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
            trigger = trimmed.isEmpty ? "Other" : trimmed
        } else {
            trigger = selectedTrigger ?? "Not specified"
        }
        // A quick log never ran the breathing reset, so there is nothing to measure —
        // no RescueSession, no claimed "after" intensity, no duration. Writing one here
        // would silently count as a zero-effect reset in "Rescue effectiveness", which
        // specifically reports on how the guided breathing is working.
        let copingAction = isQuickLog ? (selectedCopingAction ?? "Quick log") : intervention
        var session: RescueSession?
        if !isQuickLog {
            let newSession = RescueSession(
                startingIntensity: Int(startingIntensity),
                endingIntensity: Int(endingIntensity),
                trigger: trigger,
                intervention: intervention,
                startedAt: startedAt,
                completedAt: completedAt,
                resisted: resisted,
                durationSeconds: min(Int(timing.total.rounded()), max(0, resetElapsed))
            )
            context.insert(newSession)
            session = newSession
        }
        let checkIn = CravingCheckIn(
            intensity: Int(startingIntensity),
            trigger: trigger,
            copingAction: copingAction,
            note: isQuickLog ? nil : "Intensity after reset: \(Int(endingIntensity))/10",
            resisted: resisted,
            usedNicotine: usedNicotine,
            occurredAt: startedAt
        )
        context.insert(checkIn)
        savedSession = session
        savedCheckIn = checkIn
        didUndo = false
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Give a recorded slip a moment to be undone before it is pushed to the server.
        if usedNicotine == true {
            Task {
                try? await OutboxService.enqueue(checkIn: checkIn, context: context)
                // Undo can beat utility-priority encoding. Remove a late operation too.
                if didUndo { OutboxService.cancelPendingCheckIn(id: checkIn.id, context: context) }
            }
            step = .complete
            refreshMilestoneNotifications()
            // A new streak re-earns its own celebrations rather than instantly replaying
            // whichever one the previous streak had already reached.
            clearMilestoneAcknowledgements()
            Task {
                try? await Task.sleep(for: .seconds(6))
                if !didUndo { await OutboxService.flush(context: context) }
            }
        } else {
            Task {
                try? await OutboxService.enqueue(checkIn: checkIn, context: context)
                await OutboxService.flush(context: context)
            }
            if isQuickLog {
                dismiss()
            } else {
                step = .complete
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    dismiss()
                }
            }
        }
    }

    private func undoSlip() {
        guard let checkIn = savedCheckIn else { return }
        OutboxService.cancelPendingCheckIn(id: checkIn.id, context: context)
        if let session = savedSession { context.delete(session) }
        context.delete(checkIn)
        try? context.save()
        savedCheckIn = nil
        savedSession = nil
        didUndo = true
        outcome = .resisted
        refreshMilestoneNotifications()
        // Silently restore acknowledgements for whatever the reverted streak had already
        // passed, so undo does not immediately replay a celebration the person already saw.
        backfillMilestoneAcknowledgements()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Recompute milestone pings from the current streak start. Called after a slip or an
    /// undo, since both move the streak while the app is already in the foreground.
    private func refreshMilestoneNotifications() {
        guard let plan = currentPlan() else { return }
        let streakStart = ProgressCalculator.streakStart(quitDate: plan.quitDate, context: context)
        Task { await NotificationService.refreshMilestones(streakStart: streakStart, nicotineType: plan.nicotineTypeValue) }
    }

    private func clearMilestoneAcknowledgements() {
        guard let acknowledgements = try? context.fetch(FetchDescriptor<MilestoneAcknowledgement>()) else { return }
        acknowledgements.forEach(context.delete)
        try? context.save()
    }

    private func backfillMilestoneAcknowledgements() {
        guard let plan = currentPlan() else { return }
        MilestoneAcknowledgement.backfill(
            streakStart: ProgressCalculator.streakStart(quitDate: plan.quitDate, context: context),
            context: context
        )
    }

    private func currentPlan() -> QuitPlan? {
        var descriptor = FetchDescriptor<QuitPlan>()
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}

private extension CheckInView {
    var resisted: Bool { outcome == .resisted }
    var usedNicotine: Bool? {
        switch outcome {
        case .resisted: false
        case .usedNicotine: true
        case nil: nil
        }
    }
}
