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
    let plan: QuitPlan
    var body: some View {
        TabView {
            DashboardView(plan: plan).tabItem { Label("Today", systemImage: "heart.text.square") }
            CheckInView().tabItem { Label("Check In", systemImage: "waveform.path.ecg") }
            CoachingView().tabItem { Label("Coach", systemImage: "message.fill") }
            ProgressView(plan: plan).tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
            SettingsView(plan: plan).tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}

