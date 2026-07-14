import Foundation
import SwiftData
import SwiftUI

struct CoachingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Query private var plans: [QuitPlan]
    @State private var model = CoachingViewModel()
    private let prompts = ["I’m having a craving", "Help me plan the next hour", "I feel like I might slip"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty && !model.isLoading { welcome }
                            ForEach(messages) { message in ChatBubble(message: message).id(message.id) }
                            if model.isLoading { HStack { SwiftUI.ProgressView(); Text("Thinking through this with you…").font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk) }.padding(.horizontal, 6) }
                        }.padding(.horizontal, 20).padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
                if let error = model.errorMessage { errorBanner(error) }
                composer
            }
            .background(QuitNicTheme.warmBackground.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) { Image(systemName: "message.and.waveform.fill").font(.title2).foregroundStyle(QuitNicTheme.teal); VStack(alignment: .leading, spacing: 3) { Text("A calmer next step").font(.title3.weight(.bold)); Text("Use Coach for reflection and planning after Rescue.").font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk) } }
            Text("I can help you make the next few minutes easier. I’m not a medical service, but I can stay with you while you choose a practical coping step.").font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) { Text("Try a prompt").font(.caption.weight(.bold)).foregroundStyle(QuitNicTheme.secondaryInk); ForEach(prompts, id: \.self) { prompt in Button { model.draft = prompt } label: { HStack { Text(prompt); Spacer(); Image(systemName: "arrow.up.right") } }.buttonStyle(PromptButtonStyle()) } }
        }.padding(18).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(QuitNicTheme.teal.opacity(0.12)))
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("What’s happening?", text: $model.draft, axis: .vertical).lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 11).background(.white, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("coachInput")
            Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline.weight(.bold)).frame(width: 42, height: 42).foregroundStyle(.white).background(QuitNicTheme.actionTeal, in: Circle()) }.accessibilityLabel("Send").disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading).opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading ? 0.45 : 1)
        }.padding(.horizontal, 16).padding(.vertical, 12).background(.ultraThinMaterial)
    }

    private func errorBanner(_ error: String) -> some View { HStack(alignment: .top, spacing: 10) { Image(systemName: model.requiresReconnect ? "key.fill" : "wifi.exclamationmark").foregroundStyle(.orange); VStack(alignment: .leading, spacing: 3) { Text(model.requiresReconnect ? "Reconnect Coach" : "Coach is unavailable").font(.subheadline.weight(.semibold)); Text(error).font(.caption).foregroundStyle(QuitNicTheme.secondaryInk) }; Spacer(); Button(model.requiresReconnect ? "Reconnect" : "Retry") { Task { if model.requiresReconnect { await reconnect() } else { await retry() } } }.font(.subheadline.weight(.semibold)).disabled(model.isLoading) }.padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16).padding(.bottom, 8) }
    private func persist(_ message: ChatMessage) { context.insert(message); try? context.save() }
    private func send() async { await model.send(messages: messages, save: persist) }
    private func retry() async { await model.retry(messages: messages, save: persist) }
    private func reconnect() async {
        guard let plan = plans.first else { return }
        await model.reconnectAndRetry(messages: messages, plan: plan, context: context, save: persist)
    }
}

private struct PromptButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(QuitNicTheme.ink).padding(.horizontal, 13).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading).background(QuitNicTheme.warmBackground, in: RoundedRectangle(cornerRadius: 14)).opacity(configuration.isPressed ? 0.65 : 1) }
}

private struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 7) {
            HStack { if message.role == "user" { Spacer() }; Text(message.content).font(.body).foregroundStyle(message.isSafetyResponse ? Color(red: 0.45, green: 0.06, blue: 0.08) : QuitNicTheme.ink).padding(.horizontal, 15).padding(.vertical, 12).background(message.isSafetyResponse ? Color.red.opacity(0.12) : message.role == "user" ? QuitNicTheme.teal.opacity(0.16) : .white, in: RoundedRectangle(cornerRadius: 18)); if message.role != "user" { Spacer() } }
            if message.isSafetyResponse { Link(destination: URL(string: "https://findahelpline.com")!) { Label("Find local crisis support", systemImage: "arrow.up.right.square").font(.caption.weight(.semibold)).foregroundStyle(.red) }.accessibilityHint("Opens a directory of crisis support services") }
        }.frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading).accessibilityElement(children: .combine).accessibilityLabel("\(message.role == "user" ? "You" : "Coach"): \(message.content)")
    }
}
