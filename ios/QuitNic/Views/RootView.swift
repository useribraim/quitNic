import os
import Darwin
import UIKit
import SwiftData
import SwiftUI

enum PerformanceMemoryProbe {
    static func physicalFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), rebound, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

enum PerformanceSignposts {
    private static let signposter = OSSignposter(subsystem: "com.ibraimabduramanov.QuitNic", category: "Interaction")
    private static var settingsInterval: OSSignpostIntervalState?
    private static var quickLogInterval: OSSignpostIntervalState?
    private static var journeyInterval: OSSignpostIntervalState?
    private static var coachInterval: OSSignpostIntervalState?

    static func settingsRequested() {
        guard settingsInterval == nil else { return }
        settingsInterval = signposter.beginInterval("SettingsPresentation")
    }

    static func settingsAppeared() {
        guard let interval = settingsInterval else { return }
        signposter.endInterval("SettingsPresentation", interval)
        settingsInterval = nil
    }

    static func quickLogRequested() {
        guard quickLogInterval == nil else { return }
        quickLogInterval = signposter.beginInterval("QuickLogPresentation")
    }

    static func quickLogAppeared() {
        guard let interval = quickLogInterval else { return }
        signposter.endInterval("QuickLogPresentation", interval)
        quickLogInterval = nil
    }

    static func journeyRequested() {
        guard journeyInterval == nil else { return }
        journeyInterval = signposter.beginInterval("JourneyPresentation")
    }

    static func journeyAppeared() {
        guard let interval = journeyInterval else { return }
        signposter.endInterval("JourneyPresentation", interval)
        journeyInterval = nil
    }

    static func coachRequested() {
        guard coachInterval == nil else { return }
        coachInterval = signposter.beginInterval("CoachPresentation")
    }

    static func coachAppeared() {
        guard let interval = coachInterval else { return }
        signposter.endInterval("CoachPresentation", interval)
        coachInterval = nil
    }
}

enum HorizonDestination: String, CaseIterable {
    case today
    case journey
    case rescue
    case quickLog = "quick-log"
    case coach
    /// Opens Coach straight into a hands-free spoken conversation, for a reminder or
    /// shortcut fired at a moment when nobody wants to type.
    case conversation
    case settings

    init?(url: URL) {
        guard url.scheme?.lowercased() == "quitnic" else { return nil }
        let component = (url.host ?? url.pathComponents.dropFirst().first ?? "")
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.init(rawValue: component)
    }
}

@MainActor
final class HorizonURLRouter: ObservableObject {
    static let shared = HorizonURLRouter()
    @Published var destination: HorizonDestination?
    private init() {}

    func accept(_ url: URL) -> Bool {
        guard let destination = HorizonDestination(url: url) else { return false }
        self.destination = destination
        return true
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var plans: [QuitPlan]
    @Query private var latestSlips: [CravingCheckIn]
    @State private var newlyCreatedPlan: QuitPlan?
    @State private var isRefreshingForegroundState = false
    @ObservedObject private var urlRouter = HorizonURLRouter.shared

    init() {
        var planDescriptor = FetchDescriptor<QuitPlan>()
        planDescriptor.fetchLimit = 1
        _plans = Query(planDescriptor)
        var slipDescriptor = FetchDescriptor<CravingCheckIn>(
            predicate: #Predicate { $0.usedNicotine == true },
            sortBy: [SortDescriptor(\.occurredAt, order: .reverse)]
        )
        slipDescriptor.fetchLimit = 1
        _latestSlips = Query(slipDescriptor)
    }

    var body: some View {
        Group {
            if let plan = plans.first ?? newlyCreatedPlan {
                HorizonTabView(
                    plan: plan,
                    lastNicotineUse: latestSlips.first?.occurredAt,
                    destination: $urlRouter.destination
                )
            } else {
                OnboardingView { plan in
                    // SwiftData queries update shortly after a save. Keep the hand-off
                    // explicit so a new person reaches Today immediately, even offline.
                    newlyCreatedPlan = plan
                }
            }
        }
        .quitNicFontStyle()
        .onOpenURL { url in _ = urlRouter.accept(url) }
        .onAppear {
            // UI-test entry point for screens that normally sit behind a deep link.
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-open-conversation") {
                urlRouter.destination = .conversation
            }
        }
        .task {
            // Give SwiftUI one clean interactive frame before storage, notification and
            // network maintenance compete for the main actor.
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await onForeground()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await onForeground() }
        }
    }

    private func onForeground() async {
        guard !isRefreshingForegroundState else { return }
        isRefreshingForegroundState = true
        defer { isRefreshingForegroundState = false }
        await SyncCoordinator.flush(context: context)
        guard let plan = plans.first ?? newlyCreatedPlan else { return }
        // One bounded query feeds both notifications and the tab container. A slip is a
        // meaningful state change; ordinary check-ins do not rebuild this root view.
        let streakStart = ProgressCalculator.streakStart(
            quitDate: plan.quitDate,
            lastSlip: latestSlips.first?.occurredAt
        )
        await NotificationService.refreshForeground(streakStart: streakStart, nicotineType: plan.nicotineTypeValue)
    }
}

struct HorizonTabView: View {
    private enum Tab: Hashable {
        case today, journey, coach
    }

    let plan: QuitPlan
    let lastNicotineUse: Date?
    @Binding var destination: HorizonDestination?
    @State private var selection: Tab = .today
    @State private var presentedRescueMode: CheckInStartMode?
    @State private var showSettings = false
    @State private var focusRequest: DashboardFocusTarget?
    @State private var focusAfterDismissal: DashboardFocusTarget?
    @State private var hasVisitedJourney = false
    @State private var startsConversation = false
    @State private var worldClock = Date()
    @Environment(\.scenePhase) private var scenePhase
    @State private var memoryProbeGeneration = 0
    @State private var memoryProbeFootprint: UInt64 = 0

    init(plan: QuitPlan, lastNicotineUse: Date?, destination: Binding<HorizonDestination?>) {
        self.plan = plan
        self.lastNicotineUse = lastNicotineUse
        _destination = destination
        // The system default unselected tint is too dim over Horizon's dark landscape.
        UITabBar.appearance().unselectedItemTintColor = UIColor(white: 0.78, alpha: 1)
    }

    private var streakStart: Date {
        ProgressCalculator.streakStart(quitDate: plan.quitDate, lastSlip: lastNicotineUse)
    }

    /// Where the camera stands for this streak. Every screen derives its own depth from
    /// this one number, so nothing has to be kept in step by hand — Today sits on it,
    /// Journey scrubs from it, Coach pushes past it and Rescue retreats from it.
    private var earnedDepth: Double {
        ZoomChain.displayDepth(ZoomDepth.depth(streakStart: streakStart))
    }

    var body: some View {
        // One world, one axis, one clock — published here and drawn by all three tabs.
        //
        // Each screen used to invent its own background: Today drew the landscape while
        // Journey and Coach each drew a flat cobalt gradient, so changing tab read as
        // changing app. A TabView page paints an opaque background of its own, so the
        // world genuinely has to be drawn per screen; what matters is that all three
        // read the same values, which is what the environment guarantees.
        tabs
            .environment(\.horizonWorld, HorizonWorld(depth: earnedDepth, date: worldClock))
            // The light must keep up with the time of day over a long session, but it
            // only resolves per minute, so a minute is as often as this needs to move.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    worldClock = .now
                    try? await Task.sleep(for: .seconds(60))
                }
            }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            DashboardView(
                plan: plan,
                lastNicotineUse: lastNicotineUse,
                isActive: selection == .today,
                focusRequest: $focusRequest,
                onCheckIn: {
                    guard presentedRescueMode == nil, !showSettings else { return }
                    focusAfterDismissal = .craving
                    presentedRescueMode = .rescue
                },
                onOpenSettings: {
                    guard presentedRescueMode == nil else { return }
                    focusAfterDismissal = .settings
                    PerformanceSignposts.settingsRequested()
                    showSettings = true
                },
                onEnterJourney: { selection = .journey }
            )
            .tabItem { Label("Today", systemImage: "house.fill") }
            .tag(Tab.today)

            Group {
                if selection == .journey || hasVisitedJourney {
                    HorizonJourneyView(
                        streakStart: streakStart,
                        nicotineType: plan.nicotineTypeValue,
                        isActive: selection == .journey,
                        onOpenRescue: { presentedRescueMode = .rescue },
                        onOpenCoach: { selection = .coach }
                    )
                } else {
                    // Journey has its own roadmap state and timers. Defer constructing it
                    // until the first visit, then keep it mounted so position survives.
                    Color.clear.insideHorizonWorld(.reading)
                }
            }
            // Stated per tab: toolbar modifiers resolve from the selected tab's content, so
            // without this the bar falls back to the light scheme on Journey and the
            // unselected item is drawn dark grey on dark grass — invisible.
            .toolbarColorScheme(.dark, for: .tabBar)
            .tabItem { Label("Journey", systemImage: "map.fill") }
            .tag(Tab.journey)

            Group {
                if selection == .coach {
                    CoachingView(earnedDepth: earnedDepth, showsCloseButton: false, startsConversation: $startsConversation) {
                        selection = .today
                        Task { @MainActor in
                            await Task.yield()
                            presentedRescueMode = .rescue
                        }
                    }
                } else {
                    // Do not retain the chat query, speech controller, or transcript UI
                    // while another tab is active. SceneStorage restores any draft when
                    // Coach is opened again.
                    Color.clear.insideHorizonWorld(.reading)
                }
            }
            .toolbarColorScheme(.dark, for: .tabBar)
            .tabItem { Label("Coach", systemImage: "message.fill") }
            .tag(Tab.coach)
        }
        .tint(HorizonTheme.accent)
        .toolbarBackground(HorizonTheme.tabBarSurface.opacity(0.97), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .onChange(of: selection) { _, newSelection in
            if newSelection == .journey {
                PerformanceSignposts.journeyRequested()
                hasVisitedJourney = true
            } else if newSelection == .coach {
                PerformanceSignposts.coachRequested()
            }
        }
        .onChange(of: destination, initial: true) { _, newDestination in
            guard let newDestination else { return }
            open(newDestination)
            destination = nil
        }
        .overlay(alignment: .topLeading) {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing-memory-probe") {
                Text(verbatim: "\(memoryProbeGeneration):\(memoryProbeFootprint)")
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("performanceMemoryProbe")
            }
        }
        .task(id: selection) {
            guard ProcessInfo.processInfo.arguments.contains("-ui-testing-memory-probe") else { return }
            // Coach gets a short settling sample; Today deliberately waits the full
            // five-second recovery gate required by the performance contract.
            let delay: Duration = selection == .today ? .seconds(5) : .seconds(2)
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            memoryProbeFootprint = PerformanceMemoryProbe.physicalFootprint()
            memoryProbeGeneration += 1
        }
        .fullScreenCover(item: $presentedRescueMode, onDismiss: restoreLaunchingFocus) { mode in
            CheckInView(earnedDepth: earnedDepth, startMode: mode)
        }
        // Settings leaves the world: it is utility, and forcing it into the landscape
        // would make a form the person has to read through weather.
        .sheet(isPresented: $showSettings, onDismiss: restoreLaunchingFocus) {
            SettingsView(plan: plan, lastNicotineUse: lastNicotineUse)
        }
    }

    private func restoreLaunchingFocus() {
        selection = .today
        focusRequest = focusAfterDismissal
        focusAfterDismissal = nil
    }

    private func open(_ destination: HorizonDestination) {
        presentedRescueMode = nil
        showSettings = false
        switch destination {
        case .today:
            selection = .today
        case .journey:
            selection = .journey
        case .coach:
            selection = .coach
        case .conversation:
            selection = .coach
            startsConversation = true
        case .rescue, .quickLog, .settings:
            selection = .today
            Task { @MainActor in
                await Task.yield()
                switch destination {
                case .rescue:
                    focusAfterDismissal = .craving
                    presentedRescueMode = .rescue
                case .quickLog:
                    focusAfterDismissal = .craving
                    PerformanceSignposts.quickLogRequested()
                    presentedRescueMode = .quickLog
                case .settings:
                    focusAfterDismissal = .settings
                    PerformanceSignposts.settingsRequested()
                    showSettings = true
                case .today, .journey, .coach, .conversation:
                    break
                }
            }
        }
    }
}
