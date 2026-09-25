import SwiftData
import SwiftUI
import UIKit

enum DashboardFocusTarget: Hashable {
    case craving
    case settings
}

struct DashboardView: View {
    let plan: QuitPlan
    let lastNicotineUse: Date?
    let isActive: Bool
    @Binding var focusRequest: DashboardFocusTarget?
    let onCheckIn: () -> Void
    let onOpenSettings: () -> Void
    let onEnterJourney: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var checkIns: [CravingCheckIn]
    @Query private var acknowledgements: [MilestoneAcknowledgement]
    @State private var now = Date()
    @State private var showHistory = false
    @State private var undoableCheckInID: UUID?
    @State private var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @AccessibilityFocusState private var accessibilityFocus: DashboardFocusTarget?
    /// The milestone currently resolving in the sky, if any. Milestones are not
    /// screens: crossing one is a depth at which something comes into view, held for
    /// a few seconds. If someone was not looking, they missed it, and that is correct
    /// — the world does not wait for an audience.
    @State private var skyMilestone: Milestone?

    init(
        plan: QuitPlan,
        lastNicotineUse: Date?,
        isActive: Bool = true,
        focusRequest: Binding<DashboardFocusTarget?>,
        onCheckIn: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void = {},
        onEnterJourney: @escaping () -> Void = {}
    ) {
        self.plan = plan
        self.lastNicotineUse = lastNicotineUse
        self.isActive = isActive
        _focusRequest = focusRequest
        self.onCheckIn = onCheckIn
        self.onOpenSettings = onOpenSettings
        self.onEnterJourney = onEnterJourney
        var recentDescriptor = FetchDescriptor<CravingCheckIn>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        recentDescriptor.fetchLimit = 1
        _checkIns = Query(recentDescriptor)
    }

    private var progress: LocalProgress {
        ProgressCalculator.calculate(plan: plan, lastNicotineUse: lastNicotineUse, now: now)
    }

    private var visibleRecentCheckIn: CravingCheckIn? {
        guard let latest = checkIns.first,
              now.timeIntervalSince(latest.occurredAt) < 7 * 86_400 else { return nil }
        return latest
    }

    /// Every milestone already crossed on the current streak, regardless of whether it
    /// has resolved in the sky yet.
    private func crossedMilestones(_ progress: LocalProgress) -> [Milestone] {
        let elapsedHours = Double(progress.seconds) / 3_600
        return ProgressCalculator.milestones(for: plan.nicotineTypeValue)
            .filter { Double($0.hours) <= elapsedHours }
    }

    /// Resolve the most advanced crossed milestone nobody has seen. Only the single
    /// highest one ever shows — if the app was closed for a week and three milestones
    /// passed, the best one resolves and the rest are quietly marked seen.
    private func resolveMilestoneIfCrossed(_ progress: LocalProgress) {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing-suppress-celebrations") else { return }
        guard skyMilestone == nil else { return }
        let acknowledgedHours = Set(acknowledgements.map(\.hours))
        guard let milestone = crossedMilestones(progress)
            .filter({ !acknowledgedHours.contains($0.hours) })
            .max(by: { $0.hours < $1.hours }) else { return }

        skyMilestone = milestone
        Task {
            try? await Task.sleep(for: .seconds(6))
            skyMilestone = nil
            acknowledgeCrossedMilestones(progress)
        }
    }

    private func acknowledgeCrossedMilestones(_ progress: LocalProgress) {
        let acknowledgedHours = Set(acknowledgements.map(\.hours))
        for milestone in crossedMilestones(progress) where !acknowledgedHours.contains(milestone.hours) {
            context.insert(MilestoneAcknowledgement(hours: milestone.hours))
        }
        try? context.save()
    }

    var body: some View {
        // Derived once and passed down. As a computed property this ran again for every
        // reader in the same pass — the headline, the sky caption, the refresh cadence
        // and the crossed-milestone check each rebuilt the whole checkpoint list.
        let progress = progress
        // No NavigationStack: Today pushes nothing, and a hidden navigation bar still
        // shifts the canvas up out of the safe area.
        return HorizonTodayView(
            plan: plan,
            progress: progress,
            now: now,
            skyCaption: skyMilestone?.celebration,
            recentCheckIn: visibleRecentCheckIn,
            canUndoRecentCheckIn: visibleRecentCheckIn?.id == undoableCheckInID,
            accessibilityFocus: $accessibilityFocus,
            onOpenHistory: { showHistory = true },
            onUndoRecentCheckIn: undoRecentCheckIn,
            onCheckIn: onCheckIn,
            onOpenSettings: onOpenSettings,
            onEnterJourney: onEnterJourney
        )
        .toolbarColorScheme(.dark, for: .tabBar)
        // Refresh before sleeping, so returning to Today never shows a minute-stale timer.
        .task(id: isActive && !reduceMotion && !isLowPowerMode) {
            guard isActive, !reduceMotion, !isLowPowerMode else { return }
            resolveMilestoneIfCrossed(progress)
            while !Task.isCancelled {
                now = .now
                let current = ProgressCalculator.calculate(plan: plan, lastNicotineUse: lastNicotineUse, now: now)
                let refreshEvery: TimeInterval = current.seconds < 48 * 3_600
                    ? 60
                    : (current.nextMilestone == nil ? 86_400 : 3_600)
                try? await Task.sleep(for: .seconds(refreshEvery))
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { now = .now } }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            now = .now
        }
        .onChange(of: now) { _, _ in resolveMilestoneIfCrossed(progress) }
        .onChange(of: focusRequest) { _, target in
            guard let target else { return }
            accessibilityFocus = target
            Task { @MainActor in
                await Task.yield()
                focusRequest = nil
            }
        }
        .task(id: checkIns.first?.id) {
            guard let latest = checkIns.first,
                  latest.usedNicotine != true,
                  Date.now.timeIntervalSince(latest.occurredAt) < 10 else {
                undoableCheckInID = nil
                return
            }
            undoableCheckInID = latest.id
            let remaining = max(0, 10 - Date.now.timeIntervalSince(latest.occurredAt))
            try? await Task.sleep(for: .seconds(remaining))
            if !Task.isCancelled { undoableCheckInID = nil }
        }
        .sheet(isPresented: $showHistory) { CheckInHistoryView() }
    }

    private func undoRecentCheckIn() {
        guard let latest = checkIns.first,
              latest.id == undoableCheckInID,
              latest.usedNicotine != true else { return }
        undoableCheckInID = nil
        try? OutboxService.enqueueDeletion(checkInID: latest.id, context: context)
        context.delete(latest)
        try? context.save()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task { await OutboxService.flush(context: context) }
    }
}

private struct HorizonTodayView: View {
    let plan: QuitPlan
    let progress: LocalProgress
    let now: Date
    /// A milestone resolving in the sky, when one has just been crossed.
    let skyCaption: String?
    let recentCheckIn: CravingCheckIn?
    let canUndoRecentCheckIn: Bool
    let accessibilityFocus: AccessibilityFocusState<DashboardFocusTarget?>.Binding
    let onOpenHistory: () -> Void
    let onUndoRecentCheckIn: () -> Void
    let onCheckIn: () -> Void
    let onOpenSettings: () -> Void
    let onEnterJourney: () -> Void

    /// One sentence, not a dashboard. The landscape already carries the emotion; Today
    /// only needs to say how far the person has come.
    private var headline: String {
        if now < plan.quitDate { return "Begins soon" }
        let hours = progress.seconds / 3_600
        if hours < 1 {
            let minutes = max(1, progress.seconds / 60)
            return "\(minutes) min free"
        }
        if hours < 24 {
            return "\(hours) hr free"
        }
        let days = progress.streakDays
        if days < 7 {
            let remainder = hours - days * 24
            return remainder == 0
                ? "\(days) day\(days == 1 ? "" : "s") free"
                : "\(days)d \(remainder)h free"
        }
        return "\(days) days free"
    }

    /// One quiet line in the sky tying Today to the world you can walk into.
    private var nextLandmarkCaption: String? {
        guard now >= plan.quitDate, let next = progress.nextMilestone else { return nil }
        let remaining = Double(next.hours) * 3_600 - Double(progress.seconds)
        guard remaining > 0 else { return nil }
        return "Next · \(next.title) in \(JourneyFormatter.spokenCountdown(remaining))"
    }

    private var headlineSize: CGFloat {
        progress.seconds < 3_600 ? 48 : 54
    }

    var body: some View {
        let savingsText = AppCurrency.formatSavings(progress.moneySaved, code: plan.currencyCode)
        VStack(alignment: .leading, spacing: 0) {
            topBar

            VStack(alignment: .leading, spacing: HorizonLayout.compact) {
                Text(headline)
                    .font(HorizonType.display(headlineSize))
                    .fontWeight(.medium)
                    .minimumScaleFactor(0.62)
                    .lineLimit(1)
                Text("\(savingsText) saved")
                    .font(HorizonType.body(.title3).weight(.medium))
                    .foregroundStyle(.white)
                    .accessibilityLabel("Money saved")
                    .accessibilityValue(savingsText)

                // A crossed milestone briefly replaces the next marker; neither gets a
                // card, border, eyebrow, or second explanatory sentence.
                if let skyCaption {
                    Text(skyCaption)
                        .font(HorizonType.body(.subheadline))
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                        .accessibilityIdentifier("todayMilestoneResolved")
                } else if let nextLandmarkCaption {
                    Button(action: onEnterJourney) {
                        Text(nextLandmarkCaption)
                            .font(HorizonType.body(.subheadline).weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                    .accessibilityHint("Opens Journey at the next checkpoint")
                }
            }
            .frame(maxWidth: 350, alignment: .leading)
            .padding(.top, HorizonLayout.hero)

            Spacer()

            if let recentCheckIn {
                HStack(spacing: HorizonLayout.control) {
                    Button(action: onOpenHistory) {
                        HStack(spacing: HorizonLayout.compact) {
                            Image(systemName: recentCheckIn.usedNicotine == true ? "arrow.counterclockwise" : "checkmark")
                                .font(.caption.weight(.bold))
                                .accessibilityHidden(true)
                            Text(recentCheckIn.usedNicotine == true
                                 ? "Slip · \(recentCheckIn.trigger)"
                                 : "\(recentCheckIn.trigger) · \(recentCheckIn.copingAction)")
                                .font(HorizonType.body(.subheadline).weight(.medium))
                                .lineLimit(1)
                            if !recentCheckIn.synced {
                                Image(systemName: "icloud.slash")
                                    .font(.caption2)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.88))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        (recentCheckIn.usedNicotine == true
                            ? "Latest check-in. Slip logged, timer restarted. \(recentCheckIn.trigger)."
                            : "Latest check-in. \(recentCheckIn.trigger), moved through. Helped: \(recentCheckIn.copingAction).")
                        + (recentCheckIn.synced ? "" : " Saved on this device.")
                    )
                    .accessibilityIdentifier("todayLatestCheckIn")
                    .accessibilityHint("Opens check-in history")

                    if canUndoRecentCheckIn {
                        Button("Undo", action: onUndoRecentCheckIn)
                            .font(HorizonType.body(.subheadline).weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 52, minHeight: 44)
                            .accessibilityLabel("Undo latest check-in")
                            .accessibilityHint("Removes the check-in you just saved")
                            .accessibilityIdentifier("undoLatestCheckIn")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, HorizonLayout.compact)
            }

            Spacer().frame(height: HorizonLayout.todayTabClearance)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, HorizonLayout.roomy)
        .padding(.top, HorizonLayout.compact)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .insideHorizonWorld(.none)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            Button("Settings", systemImage: "gearshape.fill", action: onOpenSettings)
                .labelStyle(.iconOnly)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .accessibilityHint("Opens app settings")
                .accessibilityFocused(accessibilityFocus, equals: .settings)
            Button(action: onCheckIn) {
                Text("Craving?")
                    .font(HorizonType.body(.subheadline).weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, HorizonLayout.content)
                    .padding(.vertical, HorizonLayout.compact)
                    .background(HorizonTheme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I have a craving")
            .accessibilityHint("Opens Rescue")
            .accessibilityFocused(accessibilityFocus, equals: .craving)
        }
    }
}

private struct CheckInHistoryView: View {
    private static let pageSize = 50
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case week = "7 days"
        case cravings = "Cravings"
        case slips = "Slips"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var firstPage: [CravingCheckIn]
    @State private var filter: Filter = .week
    @State private var editingCheckIn: CravingCheckIn?
    @State private var pendingDeletion: CravingCheckIn?
    @State private var olderCheckIns: [CravingCheckIn] = []
    @State private var canLoadMore = true

    init() {
        var descriptor = FetchDescriptor<CravingCheckIn>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = Self.pageSize
        _firstPage = Query(descriptor)
    }

    /// Everything on screen derived in one pass. `checkIns` was a computed property that
    /// re-concatenated and re-de-duplicated both pages, and four readers each triggered
    /// it per body evaluation. Over 200 rows that was 140 µs a pass; this is 68 µs.
    private struct History {
        let all: [CravingCheckIn]
        let filtered: [CravingCheckIn]
        let resistedCount: Int
        let commonTrigger: String?
    }

    private func history() -> History {
        var seen = Set<UUID>()
        let all = (firstPage + olderCheckIns).filter { seen.insert($0.id).inserted }
        let filtered: [CravingCheckIn]
        switch filter {
        case .all: filtered = all
        case .week: filtered = all.filter { $0.occurredAt >= Date().addingTimeInterval(-7 * 86_400) }
        case .cravings: filtered = all.filter { $0.usedNicotine != true }
        case .slips: filtered = all.filter { $0.usedNicotine == true }
        }
        var commonTrigger: String?
        if all.count >= 3 {
            let useful = all.lazy.map(\.trigger).filter { $0 != "Not specified" && $0 != "Other" }
            commonTrigger = Dictionary(grouping: useful, by: { $0 }).max { $0.value.count < $1.value.count }?.key
        }
        return History(
            all: all,
            filtered: filtered,
            resistedCount: all.count { $0.usedNicotine != true },
            commonTrigger: commonTrigger
        )
    }

    var body: some View {
        let history = history()
        return NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Showing")
                        Spacer()
                        Menu(filter.rawValue) {
                            Picker("Show", selection: $filter) {
                                ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                            }
                        }
                        .accessibilityIdentifier("historyFilter")
                    }
                }
                .listRowBackground(HorizonTheme.deepCobalt)

                if !history.all.isEmpty {
                    Section {
                        if let commonTrigger = history.commonTrigger {
                            Label("\(commonTrigger) appears most often so far.", systemImage: "lightbulb.fill")
                                .foregroundStyle(HorizonTheme.accentText)
                        } else {
                            Label("\(history.resistedCount) of \(history.all.count) cravings moved through", systemImage: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .listRowBackground(HorizonTheme.surface)
                }

                Section(filter == .all ? "Recent" : filter.rawValue) {
                    ForEach(history.filtered) { checkIn in
                        VStack(alignment: .leading, spacing: HorizonLayout.tight) {
                            HStack {
                                Text(checkIn.usedNicotine == true ? "Slip" : "Craving")
                                    .font(.headline)
                                Spacer()
                            Text(checkIn.occurredAt, format: .dateTime.day().month().hour().minute())
                                .font(.caption)
                                .foregroundStyle(HorizonTheme.secondaryText)
                            }
                            Text(checkIn.trigger)
                            Text("Intensity \(checkIn.intensity)/10 · \(checkIn.copingAction)")
                                .font(.subheadline)
                                .foregroundStyle(HorizonTheme.secondaryText)
                            if let note = checkIn.note, !note.isEmpty {
                                Text(note).font(.footnote).foregroundStyle(HorizonTheme.secondaryText)
                            }
                        }
                        .padding(.vertical, HorizonLayout.micro)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier(checkIn.usedNicotine == true ? "historySlipRow" : "historyCravingRow")
                        .listRowBackground(checkIn.usedNicotine == true ? HorizonTheme.plum : HorizonTheme.surface)
                        .swipeActions(edge: .trailing) {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                pendingDeletion = checkIn
                            }
                            Button("Edit", systemImage: "pencil") {
                                editingCheckIn = checkIn
                            }
                            .tint(HorizonTheme.cobalt)
                        }
                    }
                    if canLoadMore {
                        Button("Load older check-ins", action: loadMore)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(HorizonTheme.accentText)
                            .listRowBackground(HorizonTheme.deepCobalt)
                            .accessibilityIdentifier("historyLoadMore")
                    }
                }
            }
            .navigationTitle("Check-in history")
            .scrollContentBackground(.hidden)
            .background(HorizonBackdrop())
            .foregroundStyle(.white)
            .tint(HorizonTheme.accent)
            .preferredColorScheme(.dark)
            .toolbarBackground(HorizonTheme.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .overlay {
                if history.filtered.isEmpty {
                    ContentUnavailableView(
                        history.all.isEmpty ? "No check-ins yet" : "Nothing in this view",
                        systemImage: "square.and.pencil"
                    )
                    .foregroundStyle(.white)
                }
            }
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .onAppear { canLoadMore = firstPage.count == Self.pageSize }
        }
        .sheet(item: $editingCheckIn) { checkIn in
            CheckInHistoryEditor(checkIn: checkIn) { changesStreak in
                saveCorrection(checkIn, changesStreak: changesStreak)
            }
        }
        .confirmationDialog("Delete this check-in?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Delete check-in", role: .destructive) {
                if let pendingDeletion { delete(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("This removes the entry from your pattern history and updates your streak if it was a slip.")
        }
    }

    private func saveCorrection(_ checkIn: CravingCheckIn, changesStreak: Bool) {
        try? context.save()
        if changesStreak { refreshStreakAfterCorrection() }
        Task {
            try? await OutboxService.enqueue(checkIn: checkIn, context: context)
            await OutboxService.flush(context: context)
        }
    }

    private func delete(_ checkIn: CravingCheckIn) {
        let changesStreak = checkIn.usedNicotine == true
        try? OutboxService.enqueueDeletion(checkInID: checkIn.id, context: context)
        context.delete(checkIn)
        olderCheckIns.removeAll { $0.id == checkIn.id }
        try? context.save()
        if changesStreak { refreshStreakAfterCorrection() }
        Task { await OutboxService.flush(context: context) }
    }

    private func loadMore() {
        var descriptor = FetchDescriptor<CravingCheckIn>(
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        descriptor.fetchOffset = firstPage.count + olderCheckIns.count
        descriptor.fetchLimit = Self.pageSize
        let page = (try? context.fetch(descriptor)) ?? []
        olderCheckIns.append(contentsOf: page)
        canLoadMore = page.count == Self.pageSize
    }

    private func refreshStreakAfterCorrection() {
        var planDescriptor = FetchDescriptor<QuitPlan>()
        planDescriptor.fetchLimit = 1
        guard let plan = try? context.fetch(planDescriptor).first else { return }
        let streakStart = ProgressCalculator.streakStart(quitDate: plan.quitDate, context: context)
        MilestoneAcknowledgement.reset(streakStart: streakStart, context: context)
        Task { await NotificationService.refreshMilestones(streakStart: streakStart, nicotineType: plan.nicotineTypeValue) }
    }
}
