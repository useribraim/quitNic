import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var plans: [QuitPlan]
    var body: some View {
        Group {
            if plans.first == nil { OnboardingView() }
            else { MainTabView(plan: plans[0]) }
        }
        .task { await OutboxService.flush(context: context) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await OutboxService.flush(context: context) }
        }
    }
}

struct MainTabView: View {
    private enum Tab: Hashable {
        case today, checkIn, coach, progress, settings
    }

    let plan: QuitPlan
    @State private var selection: Tab = .today

    var body: some View {
        TabView(selection: $selection) {
            DashboardView(plan: plan) { selection = .checkIn }
                .tabItem { Label("Today", systemImage: "heart.text.square") }
                .tag(Tab.today)
            CheckInView()
                .tabItem { Label("Check In", systemImage: "waveform.path.ecg") }
                .tag(Tab.checkIn)
            CoachingView()
                .tabItem { Label("Coach", systemImage: "message.fill") }
                .tag(Tab.coach)
            ProgressView(plan: plan)
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
            SettingsView(plan: plan)
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(Tab.settings)
        }
        .tint(QuitNicTheme.teal)
    }
}
