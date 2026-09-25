import SwiftUI

/// A readable roadmap first, with the Horizon artwork used as atmosphere rather than
/// navigation. Every checkpoint remains reachable with scroll, tap, keyboard and VoiceOver.
struct HorizonJourneyView: View {
    private struct Snapshot {
        let stops: [ProgressCalculator.JourneyStop]
        let reached: [ProgressCalculator.JourneyStop]
        let upcoming: [ProgressCalculator.JourneyStop]
        let next: ProgressCalculator.JourneyStop?
        let elapsed: TimeInterval
        let progressToNext: Double
    }

    let streakStart: Date
    let nicotineType: NicotineType
    let isActive: Bool
    let onOpenRescue: () -> Void
    let onOpenCoach: () -> Void

    @State private var now = Date()
    @State private var expandedHours: Set<Int> = []
    @State private var showReachedMilestones = false
    @State private var showAllUpcoming = false
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AppStorage("journeyLastSeenCheckpointHours") private var lastSeenCheckpointHours = 0
    @State private var newlyReachedHours: Int?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var journeySnapshot: Snapshot {
        let stops = ProgressCalculator.journey(streakStart: streakStart, nicotineType: nicotineType, now: now)
        return Snapshot(
            stops: stops,
            reached: stops.filter(\.isReached),
            upcoming: stops.filter { !$0.isReached && !$0.isNext },
            next: stops.first(where: \.isNext),
            elapsed: max(0, now.timeIntervalSince(streakStart)),
            progressToNext: ProgressCalculator.progressToNextStop(streakStart: streakStart, now: now)
        )
    }

    var body: some View {
        let snapshot = journeySnapshot
        let visibleUpcoming = showAllUpcoming ? snapshot.upcoming : Array(snapshot.upcoming.prefix(3))
        ScrollView {
            LazyVStack(alignment: .leading, spacing: HorizonLayout.section) {
                hero(snapshot)
                if let nextStop = snapshot.next {
                    nextMilestoneCard(nextStop, progressToNext: snapshot.progressToNext)
                } else {
                    beyondRoadmapCard
                }

                if !snapshot.reached.isEmpty {
                    DisclosureGroup(isExpanded: reachedGroupExpansion) {
                        LazyVStack(spacing: HorizonLayout.compact) {
                            ForEach(snapshot.reached) { stop in
                                milestoneRow(stop)
                            }
                        }
                        .padding(.top, HorizonLayout.compact)
                    } label: {
                        Label(reachedSummaryLabel(count: snapshot.reached.count), systemImage: "checkmark.circle.fill")
                            .font(HorizonType.body(.subheadline).weight(.semibold))
                            .accessibilityIdentifier("journeyReachedSummary")
                    }
                    .tint(.white)
                    .padding(HorizonLayout.control)
                    .background(HorizonTheme.forest, in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
                }

                LazyVStack(spacing: HorizonLayout.compact) {
                    ForEach(visibleUpcoming) { stop in
                        milestoneRow(stop)
                    }
                }

                if snapshot.upcoming.count > 3 {
                    Button(showAllUpcoming ? "Show fewer checkpoints" : "Show all \(snapshot.upcoming.count) upcoming checkpoints") {
                        showAllUpcoming.toggle()
                    }
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(HorizonTheme.accentText)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("journeyShowAll")
                }

                DisclosureGroup {
                    Text("Timelines describe common patterns, not a personal medical prediction. If symptoms concern you, contact a qualified healthcare professional.")
                        .font(HorizonType.body(.footnote))
                        .foregroundStyle(HorizonTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, HorizonLayout.tight)
                } label: {
                    Label("About these timelines", systemImage: "info.circle")
                        .font(HorizonType.body(.footnote).weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("journeyTimelineDisclosure")
                }
                .tint(.white)
                .padding(.vertical, HorizonLayout.compact)
            }
            .padding(.horizontal, HorizonLayout.section)
            .padding(.top, HorizonLayout.control)
            .padding(.bottom, HorizonLayout.journeyTabClearance)
        }
        .insideHorizonWorld(.reading)
        .preferredColorScheme(.dark)
        .task(id: isActive && !reduceMotion && !isLowPowerMode) {
            guard isActive, !reduceMotion, !isLowPowerMode else { return }
            now = .now
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-expand-journey") {
                let testingStops = ProgressCalculator.journey(streakStart: streakStart, nicotineType: nicotineType, now: now)
                expandedHours = Set(testingStops.map { $0.milestone.hours })
                showReachedMilestones = true
                showAllUpcoming = true
            }
            while !Task.isCancelled {
                now = .now
                // Only the distance to the next checkpoint sets the tick rate, so read
                // that directly rather than materializing the whole roadmap to find it.
                let elapsedHours = max(0, now.timeIntervalSince(streakStart)) / 3_600
                let nextHours = ProgressCalculator.milestones.first { Double($0.hours) > elapsedHours }?.hours
                let remaining = nextHours.map { Double($0) * 3_600 - elapsedHours * 3_600 } ?? 86_400
                let refreshEvery: TimeInterval = remaining < 48 * 3_600 ? 60 : (remaining < 60 * 86_400 ? 3_600 : 86_400)
                try? await Task.sleep(for: .seconds(refreshEvery))
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            now = .now
        }
        .onAppear {
            PerformanceSignposts.journeyAppeared()
            surfaceNewlyReachedCheckpoint(snapshot)
        }
    }

    /// Opening the roadmap just after a checkpoint flipped should show the moment,
    /// not a bigger count in a collapsed list. Closing the reached group clears the
    /// badge — that collapse is the natural "seen it" gesture.
    private var reachedGroupExpansion: Binding<Bool> {
        Binding(
            get: { showReachedMilestones },
            set: { isExpanded in
                showReachedMilestones = isExpanded
                if !isExpanded { newlyReachedHours = nil }
            }
        )
    }

    private func reachedSummaryLabel(count: Int) -> String {
        let base = "\(count) checkpoint\(count == 1 ? "" : "s") reached"
        return newlyReachedHours == nil ? base : "\(base) — including a new one"
    }

    /// Takes the snapshot `body` already built. Recomputing it here rebuilt the whole
    /// roadmap a second time on every appearance.
    private func surfaceNewlyReachedCheckpoint(_ snapshot: Snapshot) {
        guard let newest = snapshot.reached.last?.milestone.hours,
              newest > lastSeenCheckpointHours else { return }
        newlyReachedHours = newest
        showReachedMilestones = true
        lastSeenCheckpointHours = newest
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func hero(_ snapshot: Snapshot) -> some View {
        VStack(alignment: .leading, spacing: HorizonLayout.compact) {
            HStack(alignment: .firstTextBaseline) {
                Text(JourneyFormatter.elapsedHeadline(snapshot.elapsed))
                    .font(HorizonType.display(30))
                    .fontWidth(.condensed)
                Spacer(minLength: HorizonLayout.control)
                Text("\(snapshot.reached.count) of \(snapshot.stops.count) checkpoints reached")
                    .font(HorizonType.body(.caption))
                    .foregroundStyle(HorizonTheme.secondaryText)
                    .multilineTextAlignment(.trailing)
            }
            ProgressView(value: Double(snapshot.reached.count), total: Double(snapshot.stops.count))
                .tint(HorizonTheme.accentText)
                .accessibilityHidden(true)
        }
        .padding(HorizonLayout.content)
        .frame(maxWidth: .infinity)
        .background(HorizonTheme.strongSurface, in: RoundedRectangle(cornerRadius: HorizonLayout.panelRadius, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: HorizonLayout.panelRadius).strokeBorder(HorizonTheme.border, lineWidth: HorizonLayout.hairline) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your journey. \(JourneyFormatter.elapsedHeadline(snapshot.elapsed)). \(snapshot.reached.count) of \(snapshot.stops.count) checkpoints reached")
        .accessibilityIdentifier("journeySummary")
    }

    private func nextMilestoneCard(_ stop: ProgressCalculator.JourneyStop, progressToNext: Double) -> some View {
        VStack(alignment: .leading, spacing: HorizonLayout.compact) {
            HStack {
                Label("UP NEXT", systemImage: "location.fill")
                    .font(HorizonType.body(.caption).weight(.bold))
                    .tracking(1.5)
                Spacer()
                if case let .next(remaining) = stop.state {
                    Text(JourneyFormatter.countdown(remaining))
                        .font(HorizonType.body(.caption).weight(.bold).monospacedDigit())
                }
            }
            .foregroundStyle(HorizonTheme.cobalt)
            Text(stop.milestone.title)
                .font(HorizonType.body(.headline).weight(.bold))
                .foregroundStyle(HorizonTheme.paperInk)
            Text(stop.milestone.detail)
                .font(HorizonType.body(.subheadline))
                .foregroundStyle(HorizonTheme.paperInk)
                .lineLimit(2)
            ProgressView(value: progressToNext)
                .tint(HorizonTheme.accent)
                .accessibilityHidden(true)
        }
        .padding(HorizonLayout.content)
        .background(HorizonTheme.paper, in: RoundedRectangle(cornerRadius: HorizonLayout.panelRadius))
        .overlay { RoundedRectangle(cornerRadius: HorizonLayout.panelRadius).strokeBorder(HorizonTheme.accent, lineWidth: HorizonLayout.emphasisBorder) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("journeyNextMilestone")
    }

    private func milestoneRow(_ stop: ProgressCalculator.JourneyStop) -> some View {
        JourneyMilestoneRow(
            stop: stop,
            now: now,
            isNewlyReached: stop.milestone.hours == newlyReachedHours,
            expanded: Binding(
                get: { expandedHours.contains(stop.milestone.hours) },
                set: { isExpanded in
                    var transaction = Transaction()
                    transaction.animation = reduceMotion ? nil : .easeInOut(duration: 0.18)
                    withTransaction(transaction) {
                        if isExpanded {
                            expandedHours.insert(stop.milestone.hours)
                        } else {
                            expandedHours.remove(stop.milestone.hours)
                        }
                    }
                }
            ),
            onOpenRescue: onOpenRescue
        )
        .id(stop.milestone.hours)
    }

    private var beyondRoadmapCard: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.control) {
            Text("THE ROAD CONTINUES")
                .font(HorizonType.body(.caption).weight(.bold))
                .tracking(1.5)
                .foregroundStyle(HorizonTheme.accentText)
            Text("You reached every mapped checkpoint.")
                .font(HorizonType.body(.title2).weight(.bold))
            Text("Recovery does not stop at two months. Keep noticing patterns, protecting the routines that work, and ask Coach for a plan when the next stretch feels uncertain.")
                .font(HorizonType.body(.subheadline))
                .foregroundStyle(HorizonTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button("Plan the next stretch", systemImage: "message.fill", action: onOpenCoach)
                .buttonStyle(HorizonPrimaryButtonStyle())
        }
        .padding(HorizonLayout.content)
        .background(HorizonTheme.forest, in: RoundedRectangle(cornerRadius: HorizonLayout.panelRadius))
        .overlay { RoundedRectangle(cornerRadius: HorizonLayout.panelRadius).strokeBorder(HorizonTheme.border, lineWidth: HorizonLayout.hairline) }
        .accessibilityIdentifier("journeyBeyondRoadmap")
    }
}

private struct JourneyMilestoneRow: View {
    let stop: ProgressCalculator.JourneyStop
    let now: Date
    let isNewlyReached: Bool
    @Binding var expanded: Bool
    let onOpenRescue: () -> Void

    private var status: String {
        switch stop.state {
        case let .reached(date): "Reached \(JourneyFormatter.reachedText(date, now: now))"
        case let .next(remaining): "Next · \(JourneyFormatter.countdown(remaining))"
        case let .upcoming(remaining): JourneyFormatter.countdown(remaining)
        }
    }

    private var icon: String {
        switch stop.state {
        case .reached: "checkmark.circle.fill"
        case .next: "location.circle.fill"
        case .upcoming: "circle"
        }
    }

    private var tint: Color {
        stop.isReached ? .white : (stop.isNext ? HorizonTheme.accentText : .white.opacity(0.90))
    }

    private var rowSurface: Color {
        switch stop.state {
        case .reached: HorizonTheme.forest
        case .next: HorizonTheme.plum
        case .upcoming: HorizonTheme.deepCobalt
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: HorizonLayout.control) {
                Text("Why this matters")
                    .font(HorizonType.body(.caption).weight(.bold))
                    .foregroundStyle(tint)
                Text(stop.milestone.celebration)
                    .font(HorizonType.body(.headline))
                    .foregroundStyle(.white)
                Text("What to expect")
                    .font(HorizonType.body(.caption).weight(.bold))
                    .foregroundStyle(tint)
                Text(stop.milestone.whatToExpect)
                if !stop.isReached && stop.milestone.hours <= 48 {
                    Button("Open Rescue now", systemImage: "wind", action: onOpenRescue)
                        .buttonStyle(HorizonPrimaryButtonStyle())
                        .accessibilityHint("Starts the guided breathing reset")
                }
            }
            .font(HorizonType.body(.subheadline))
            // Expanded guidance is long-form reading content, so it uses full contrast.
            .foregroundStyle(.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(HorizonLayout.control)
            .background(
                HorizonTheme.readingSurface,
                in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius, style: .continuous)
            )
            .padding(.top, HorizonLayout.control)
        } label: {
            HStack(alignment: .top, spacing: HorizonLayout.control) {
                Image(systemName: icon)
                    .font(HorizonType.body())
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: HorizonLayout.tight) {
                    HStack(spacing: HorizonLayout.compact) {
                        Text(stop.milestone.title)
                            .font(HorizonType.body(.headline))
                            .foregroundStyle(.white)
                        if isNewlyReached {
                            Text("NEW")
                                .font(HorizonType.body(.caption2).weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(HorizonTheme.deepCobalt)
                                .padding(.horizontal, HorizonLayout.compact)
                                .padding(.vertical, HorizonLayout.micro)
                                .background(HorizonTheme.accentText, in: Capsule())
                                .accessibilityHidden(true)
                        }
                    }
                    if !stop.isReached {
                        Text(stop.milestone.detail)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.86))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityHidden(true)
                    }
                    Text(status)
                        .font(HorizonType.body(.caption).weight(.semibold))
                        .foregroundStyle(tint)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(isNewlyReached ? "Newly reached. " : "")\(stop.milestone.title). \(stop.milestone.detail). \(status)")
        }
        .tint(tint)
        .padding(.horizontal, HorizonLayout.control)
        .padding(.vertical, HorizonLayout.control)
        .background(rowSurface, in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
        .overlay { RoundedRectangle(cornerRadius: HorizonLayout.controlRadius).strokeBorder(stop.isNext ? HorizonTheme.accent : HorizonTheme.border, lineWidth: HorizonLayout.hairline) }
        .overlay(alignment: .leading) {
            Capsule()
                .fill(tint)
                .frame(width: 4)
                .padding(.vertical, HorizonLayout.section)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journeyMilestone_\(stop.milestone.hours)")
        .accessibilityHint("\(stop.milestone.detail). \(expanded ? "Collapses milestone details" : "Shows milestone details")")
    }
}

/// Duration wording, kept separate from the views so it is unit-testable.
enum JourneyFormatter {
    /// Which unit a duration is best said in, and how to say it. Three copies of this
    /// minute → hour → day → month → year ladder used to sit side by side, one per
    /// wording, so a threshold could be corrected in one and left wrong in the others.
    enum Unit {
        case minute, hour, day, month, year

        var abbreviation: String {
            switch self {
            case .minute: "m"
            case .hour: "h"
            case .day: "d"
            case .month: "mo"
            case .year: "y"
            }
        }

        var noun: String {
            switch self {
            case .minute: "minute"
            case .hour: "hour"
            case .day: "day"
            case .month: "month"
            case .year: "year"
            }
        }
    }

    /// How to land on a whole number of the chosen unit.
    ///
    /// A countdown rounds to the nearest — "in 5d" for 4.6 days away reads correctly.
    /// Elapsed time floors: saying "5d ago" about 4.6 days would credit somebody with
    /// time they have not actually been nicotine-free, which is the one thing this app
    /// must never do.
    enum Rounding { case nearest, down }

    /// The single ladder. Sub-hour durations round up to one minute so nothing ever
    /// reads as "0".
    static func scaled(_ interval: TimeInterval, rounding: Rounding = .nearest) -> (value: Int, unit: Unit) {
        func whole(_ value: Double) -> Int {
            Int(rounding == .nearest ? value.rounded() : value.rounded(.down))
        }
        let minutes = Int(interval / 60)
        if minutes < 60 { return (max(1, minutes), .minute) }
        let hours = Int(interval / 3_600)
        if hours < 48 { return (hours, .hour) }
        let days = whole(interval / 86_400)
        if days < 60 { return (days, .day) }
        let months = whole(interval / (86_400 * 30.44))
        if months < 24 { return (months, .month) }
        return (whole(interval / (86_400 * 365.25)), .year)
    }

    /// Compact countdown for a trailing label: "in 9h", "in 3d".
    static func countdown(_ remaining: TimeInterval) -> String {
        let scaled = scaled(remaining)
        return "in \(scaled.value)\(scaled.unit.abbreviation)"
    }

    /// Same information said the way a person would, for VoiceOver.
    static func spokenCountdown(_ remaining: TimeInterval) -> String {
        let scaled = scaled(remaining)
        return "\(scaled.value) \(scaled.unit.noun)\(scaled.value == 1 ? "" : "s")"
    }

    /// "Passed 2d ago" — the point of a reached mark is evidence that time moved, so
    /// it carries the elapsed distance rather than a bare "Reached".
    static func reachedText(_ date: Date, now: Date = .now) -> String {
        let scaled = scaled(max(0, now.timeIntervalSince(date)), rounding: .down)
        // Within the hour the exact count is noise: it was reached, and that is recent.
        guard scaled.unit != .minute else { return "just now" }
        return "\(scaled.value)\(scaled.unit.abbreviation) ago"
    }

    /// The hero line: "1 day, 23 hours in".
    static func elapsedHeadline(_ elapsed: TimeInterval) -> String {
        let days = Int(elapsed / 86_400)
        let hours = Int(elapsed.truncatingRemainder(dividingBy: 86_400) / 3_600)
        let minutes = Int(elapsed.truncatingRemainder(dividingBy: 3_600) / 60)
        if days > 0 {
            if hours == 0 { return "\(days) day\(days == 1 ? "" : "s") in" }
            return "\(days) day\(days == 1 ? "" : "s"), \(hours) hour\(hours == 1 ? "" : "s") in"
        }
        if hours > 0 {
            return "\(hours) hour\(hours == 1 ? "" : "s"), \(minutes) minute\(minutes == 1 ? "" : "s") in"
        }
        return "\(minutes) minute\(minutes == 1 ? "" : "s") in"
    }
}
