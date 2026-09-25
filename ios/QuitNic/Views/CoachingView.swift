import Foundation
import SwiftData
import SwiftUI

struct CoachingView: View {
    static let transcriptWindow = 100
    private static let prompts = ["I’m having a craving", "Help me plan the next hour", "I feel like I might slip"]

    @Environment(\.modelContext) private var context
    @Query private var messages: [ChatMessage]
    @Query private var coachingPlans: [ActiveCoachingPlan]
    @Query private var plans: [QuitPlan]
    @State private var model = CoachingViewModel()
    @State private var speech = PushToTalkController()
    @State private var now = Date()
    @State private var showClearConversationConfirmation = false
    @State private var showConversation = false
    @State private var draftPersistenceTask: Task<Void, Never>?
    @FocusState private var isComposerFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @SceneStorage("coachDraft") private var savedDraft = ""
    @AppStorage("voiceInputEnabled") private var voiceInputEnabled = false
    /// Retained in the initializer contract so callers do not need a navigation rewrite;
    /// Coach itself now uses a calm reading surface instead of decoding the world plates.
    let earnedDepth: Double
    let showsCloseButton: Bool
    /// Set by a deep link that wants the spoken conversation, not the chat. Cleared once
    /// the conversation is on screen so returning to Coach later shows the transcript.
    @Binding var startsConversation: Bool
    let onOpenRescue: () -> Void

    init(
        earnedDepth: Double,
        showsCloseButton: Bool = true,
        startsConversation: Binding<Bool> = .constant(false),
        onOpenRescue: @escaping () -> Void
    ) {
        self.earnedDepth = earnedDepth
        self.showsCloseButton = showsCloseButton
        _startsConversation = startsConversation
        self.onOpenRescue = onOpenRescue

        _messages = Query(Self.recentMessageDescriptor())

        var coachingPlanDescriptor = FetchDescriptor<ActiveCoachingPlan>(
            predicate: #Predicate { $0.completedAt == nil },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        coachingPlanDescriptor.fetchLimit = 1
        _coachingPlans = Query(coachingPlanDescriptor)

        var quitPlanDescriptor = FetchDescriptor<QuitPlan>()
        quitPlanDescriptor.fetchLimit = 1
        _plans = Query(quitPlanDescriptor)
    }

    private var displayMessages: ReversedCollection<[ChatMessage]> { messages.reversed() }
    private var latestMessage: ChatMessage? { messages.first }

    static func recentMessageDescriptor() -> FetchDescriptor<ChatMessage> {
        var descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = transcriptWindow
        return descriptor
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: HorizonLayout.content) {
                            if messages.isEmpty && !model.isLoading { welcome }
                            ForEach(displayMessages) { message in ChatBubble(message: message).id(message.id) }
                            if model.isLoading { HStack { SwiftUI.ProgressView(); Text("Thinking through this with you…").font(HorizonType.body(.subheadline)).foregroundStyle(HorizonTheme.secondaryText) }.padding(.horizontal, HorizonLayout.tight) }
                        }.padding(.horizontal, HorizonLayout.section).padding(.vertical, HorizonLayout.content)
                    }
                    .scrollDismissesKeyboard(.immediately)
                    .onChange(of: messages.count) { _, _ in if let id = latestMessage?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
                if let error = model.errorMessage { errorBanner(error) }
                if let activePlan { currentPlan(activePlan) }
                // Never invite somebody to turn a crisis referral into a "plan".
                else if let latestMessage, latestMessage.role == "assistant", !latestMessage.isSafetyResponse { planPrompt }
                composer
            }
            .insideHorizonWorld(.reading)
            .navigationTitle("Coach")
            // Keep the same compact Horizon chrome whether or not the keyboard is open.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if showsCloseButton { HorizonCloseButton() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Talk", systemImage: "waveform") { showConversation = true }
                        .accessibilityHint("Opens a hands-free spoken conversation with Coach")
                        .accessibilityIdentifier("startConversation")
                    if !messages.isEmpty {
                        Button("Clear chat", systemImage: "trash") {
                            showClearConversationConfirmation = true
                        }
                        .accessibilityHint("Removes this conversation from this device")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { isComposerFocused = false }
                }
            }
            .fullScreenCover(isPresented: $showConversation) {
                ConversationView(openingLine: conversationOpening, onOpenRescue: onOpenRescue)
            }
            .confirmationDialog("Clear this chat from this device?", isPresented: $showClearConversationConfirmation, titleVisibility: .visible) {
                Button("Clear chat", role: .destructive) { clearConversation() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the conversation display from this iPhone. Delete your account in Settings to remove server-held account data.")
            }
            // Only tick while a delay countdown is actually on screen; this used to wake
            // every second for the whole time the tab existed.
            .task(id: activePlan?.delayEndsAt) {
                guard let endsAt = activePlan?.delayEndsAt else { return }
                while !Task.isCancelled && Date() < endsAt {
                    now = .now
                    try? await Task.sleep(for: .seconds(1))
                }
                now = .now
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("horizonCoachScreen")
        .onAppear {
            PerformanceSignposts.coachAppeared()
            if model.draft.isEmpty { model.draft = savedDraft }
        }
        .onChange(of: startsConversation, initial: true) { _, wants in
            guard wants else { return }
            startsConversation = false
            showConversation = true
        }
        .onChange(of: model.draft) { _, draft in persistDraftSoon(draft) }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            persistDraftNow()
            discardActiveRecording()
        }
        .onDisappear {
            persistDraftNow()
            discardActiveRecording()
            Task { await CoachMarkdownCache.shared.removeAll() }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.control) {
            Text("Choose one practical next step for the next few minutes.")
                .font(HorizonType.body(.title3).weight(.semibold))
            Text("Coach offers general support, not medical advice.")
                .font(HorizonType.body(.subheadline))
                .foregroundStyle(HorizonTheme.secondaryText)
            Button("Talk it through out loud", systemImage: "waveform") { showConversation = true }
                .font(HorizonType.body(.subheadline).weight(.semibold))
                .foregroundStyle(HorizonTheme.accentText)
                .buttonStyle(.plain)
                .accessibilityHint("Opens a hands-free spoken conversation with Coach")
            Button("Open Rescue", systemImage: "wind", action: onOpenRescue)
                .font(HorizonType.body(.subheadline).weight(.semibold))
                .foregroundStyle(HorizonTheme.accentText)
                .buttonStyle(.plain)
                .accessibilityHint("Starts the guided breathing reset")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HorizonLayout.tight) {
                    ForEach(Self.prompts, id: \.self) { prompt in
                        Button {
                            model.draft = prompt
                            Task { await send() }
                        } label: {
                            Text(prompt).lineLimit(1)
                        }
                        .buttonStyle(PromptButtonStyle())
                        .accessibilityHint("Sends this prompt to Coach")
                    }
                }
                .padding(.horizontal, HorizonLayout.section)
            }
            // Run the carousel to the screen edge so a half-visible chip reads as more
            // to scroll, not as text cut off by the margin.
            .padding(.horizontal, -HorizonLayout.section)
        }
        .padding(.vertical, HorizonLayout.tight)
    }

    private var composer: some View {
        VStack(spacing: HorizonLayout.tight) {
            if let error = speech.errorMessage {
                Label(error, systemImage: "mic.slash")
                    .font(HorizonType.body(.caption))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HorizonLayout.section)
            } else if speech.isRecording {
                Label("Listening… release when you are done", systemImage: "waveform")
                    .font(HorizonType.body(.caption).weight(.semibold))
                    .foregroundStyle(HorizonTheme.accentText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, HorizonLayout.section)
            }
            HStack(alignment: .bottom, spacing: HorizonLayout.control) {
                if voiceInputEnabled {
                    PushToTalkButton(isRecording: speech.isRecording, mode: transcriptionMode) {
                        Task { await startVoiceInput() }
                    } onRelease: {
                        Task { await finishVoiceInput() }
                    }
                }
            TextField("What’s happening?", text: $model.draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isComposerFocused)
                .padding(.horizontal, HorizonLayout.content)
                .padding(.vertical, HorizonLayout.control)
                .background(HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
                .accessibilityIdentifier("coachInput")
            Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline.weight(.bold)).frame(width: 42, height: 42).foregroundStyle(.white).background(HorizonTheme.accent, in: Circle()) }.accessibilityLabel("Send").disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading).opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading ? 0.45 : 1)
            }
            .padding(.horizontal, HorizonLayout.content)
        }
        .padding(.vertical, HorizonLayout.control)
        .background(HorizonTheme.deepCobalt.opacity(0.98))
        .animation(.easeInOut(duration: 0.18), value: isComposerFocused)
    }

    /// The coach speaks first so nobody has to work out how to begin out loud.
    private var conversationOpening: String {
        messages.isEmpty
            ? "I am here with you. Tell me what is happening right now."
            : "I am here. What is going on right now?"
    }

    private var activePlan: ActiveCoachingPlan? {
        coachingPlans.first(where: { $0.completedAt == nil })
    }

    private var planPrompt: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.compact) {
            Text("Make this actionable")
                .font(HorizonType.body(.subheadline).weight(.bold))
            Text("Keep one clear next step available while you move through the craving.")
                .font(HorizonType.body(.caption))
                .foregroundStyle(HorizonTheme.secondaryText)
            Button("Use this as my plan") { createPlanFromLatestReply() }
                .buttonStyle(CoachActionButtonStyle(tint: HorizonTheme.accent))
        }
        .padding(HorizonLayout.content)
        .background(HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
        .padding(.horizontal, HorizonLayout.content)
        .padding(.bottom, HorizonLayout.tight)
    }

    private func currentPlan(_ plan: ActiveCoachingPlan) -> some View {
        VStack(alignment: .leading, spacing: HorizonLayout.control) {
            HStack {
                Label("Current plan", systemImage: "checkmark.circle.fill")
                    .font(HorizonType.body(.subheadline).weight(.bold))
                    .foregroundStyle(HorizonTheme.accentText)
                Spacer()
                if let delayEndsAt = plan.delayEndsAt, delayEndsAt > now {
                    Text("Delay \(remainingDelay(until: delayEndsAt))")
                        .font(HorizonType.body(.caption).weight(.bold).monospacedDigit())
                        .foregroundStyle(HorizonTheme.accentText)
                }
            }
            Text(plan.summary)
                .font(HorizonType.body(.subheadline))
                .foregroundStyle(HorizonTheme.primaryText)
            HStack(spacing: HorizonLayout.compact) {
                Button(plan.delayEndsAt != nil && (plan.delayEndsAt ?? .distantPast) > now ? "Delay running" : "Start 5-min delay") {
                    plan.delayEndsAt = now.addingTimeInterval(300)
                    try? context.save()
                }
                .buttonStyle(CoachActionButtonStyle(tint: HorizonTheme.accent))
                .disabled(plan.delayEndsAt != nil && (plan.delayEndsAt ?? .distantPast) > now)
                Button("Open Rescue") { onOpenRescue() }
                    .buttonStyle(CoachActionButtonStyle(tint: HorizonTheme.primaryText))
                Button("Complete") {
                    plan.completedAt = .now
                    try? context.save()
                }
                .buttonStyle(CoachActionButtonStyle(tint: HorizonTheme.secondaryText))
            }
        }
        .padding(HorizonLayout.content)
        .background(HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
        .padding(.horizontal, HorizonLayout.content)
        .padding(.bottom, HorizonLayout.tight)
        .accessibilityElement(children: .combine)
    }

    private func remainingDelay(until date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private func createPlanFromLatestReply() {
        guard let reply = messages.first(where: { $0.role == "assistant" }) else { return }
        let compact = reply.content
            .split(whereSeparator: { ".!?\n".contains($0) })
            .prefix(2)
            .joined(separator: ". ")
        context.insert(ActiveCoachingPlan(summary: String(compact).prefix(240).description))
        try? context.save()
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top, spacing: HorizonLayout.control) {
            Image(systemName: model.requiresReconnect ? "key.fill" : "wifi.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: HorizonLayout.micro) {
                Text(model.requiresReconnect ? (model.hasEverConnected ? "Reconnect Coach" : "Connect Coach") : "Coach is unavailable")
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(error)
                    .font(HorizonType.body(.caption))
                    .foregroundStyle(HorizonTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button(model.requiresReconnect ? (model.hasEverConnected ? "Reconnect" : "Connect") : "Retry") {
                Task { if model.requiresReconnect { await reconnect() } else { await retry() } }
            }
            .font(HorizonType.body(.subheadline).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, HorizonLayout.control)
            .frame(minWidth: 96, minHeight: 48)
            .background(HorizonTheme.accent, in: Capsule())
            .contentShape(Rectangle())
            .disabled(model.isLoading)
        }
        .padding(HorizonLayout.control)
        .background(HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.panelRadius))
        .padding(.horizontal, HorizonLayout.content)
        .padding(.bottom, HorizonLayout.compact)
    }
    private func persist(_ message: ChatMessage) { context.insert(message); try? context.save() }
    private func send() async {
        // Drop the keyboard on send so the tab bar comes back and the reply is readable.
        // Without this somebody who sends one message is left staring at a chat with no
        // visible way out of the tab.
        isComposerFocused = false
        await model.send(messages: Array(displayMessages), save: persist)
    }
    private func retry() async { await model.retry(messages: Array(displayMessages), save: persist) }
    private func reconnect() async {
        guard let plan = plans.first else { return }
        await model.reconnectAndRetry(messages: Array(displayMessages), plan: plan, context: context, save: persist)
    }

    private func clearConversation() {
        try? context.delete(model: ChatMessage.self)
        try? context.save()
        Task { await CoachMarkdownCache.shared.removeAll() }
    }

    private func persistDraftSoon(_ draft: String) {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            savedDraft = draft
        }
    }

    private func persistDraftNow() {
        draftPersistenceTask?.cancel()
        draftPersistenceTask = nil
        savedDraft = model.draft
    }

    private func discardActiveRecording() {
        guard let audioURL = speech.cancel() else { return }
        try? FileManager.default.removeItem(at: audioURL)
    }

    private var transcriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: "transcriptionMode") ?? "") ?? .onDevice
    }

    private func startVoiceInput() async {
        await speech.start(mode: transcriptionMode)
    }

    private func finishVoiceInput() async {
        guard let audioURL = speech.stop() else { return }
        defer { try? FileManager.default.removeItem(at: audioURL) }
        if transcriptionMode == .enhancedCloud {
            do { model.draft = try await APIClient.shared.transcribe(audioURL: audioURL).text }
            catch let error as APIError {
                speech.errorMessage = error.errorDescription ?? "Enhanced transcription is unavailable. Try on-device speech or type instead."
            } catch {
                speech.errorMessage = "Enhanced transcription is unavailable. Try on-device speech or type instead."
            }
        } else {
            model.draft = speech.transcript
        }
    }
}

private struct CoachActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HorizonType.body(.caption).weight(.bold))
            .foregroundStyle(tint)
            .padding(.horizontal, HorizonLayout.control)
            .padding(.vertical, HorizonLayout.compact)
            .background(tint.opacity(configuration.isPressed ? 0.20 : 0.12), in: Capsule())
    }
}


private struct PromptButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(HorizonType.body(.subheadline).weight(.medium))
            .foregroundStyle(HorizonTheme.primaryText)
            .padding(.horizontal, HorizonLayout.control)
            .padding(.vertical, HorizonLayout.compact)
            .background(HorizonTheme.forest.opacity(0.72), in: Capsule())
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

private actor CoachMarkdownCache {
    static let shared = CoachMarkdownCache()
    private let limit = 200
    private var values: [String: AttributedString] = [:]
    private var order: [String] = []

    func rendered(_ source: String) -> AttributedString? {
        if let cached = values[source] { return cached }
        guard let parsed = try? AttributedString(
            markdown: source,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return nil }
        if order.count >= limit, let oldest = order.first {
            values.removeValue(forKey: oldest)
            order.removeFirst()
        }
        values[source] = parsed
        order.append(source)
        return parsed
    }

    func removeAll() {
        values.removeAll(keepingCapacity: false)
        order.removeAll(keepingCapacity: false)
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    @State private var renderedContent: AttributedString?

    // The coaching model is asked for plain prose, but nothing guarantees it never slips
    // in `**bold**` or a `-` list. Rendering as Markdown handles that gracefully; a plain
    // Text would otherwise show the literal asterisks and dashes to the person reading it.
    private var displayText: Text {
        renderedContent.map(Text.init) ?? Text(message.content)
    }

    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: HorizonLayout.compact) {
            HStack {
                if message.role == "user" { Spacer() }
                displayText
                    .font(HorizonType.body())
                    .foregroundStyle(HorizonTheme.primaryText)
                    .padding(.horizontal, HorizonLayout.content)
                    .padding(.vertical, HorizonLayout.control)
                    .background(
                        message.isSafetyResponse
                            ? Color.red.opacity(0.24)
                            : message.role == "user" ? HorizonTheme.plum : HorizonTheme.surface,
                        in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius)
                    )
                if message.role != "user" { Spacer() }
            }
            if message.isSafetyResponse { Link(destination: URL(string: "https://findahelpline.com")!) { Label("Find local crisis support", systemImage: "arrow.up.right.square").font(HorizonType.body(.caption).weight(.semibold)).foregroundStyle(.red) }.accessibilityHint("Opens a directory of crisis support services") }
        }
        .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(message.role == "user" ? "You" : "Coach"): \(message.content)")
        .accessibilityIdentifier(message.role == "user" ? "coachUserMessage" : "coachAssistantMessage")
        .task(id: message.content) {
            renderedContent = await CoachMarkdownCache.shared.rendered(message.content)
        }
    }
}
