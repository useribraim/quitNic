import SwiftData
import SwiftUI

/// Hands-free spoken coaching.
///
/// The screen deliberately has almost nothing on it. Somebody opens this in the middle of
/// a craving, often walking, often without looking at the phone at all, so the interface
/// is the voice: talk, pause, hear the reply, talk again. Everything visible is a status
/// read-out for the moments when somebody does glance down.
struct ConversationView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = ConversationSession()
    @State private var hasStarted = false

    let openingLine: String
    let onOpenRescue: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: HorizonLayout.section) {
                Spacer(minLength: 0)
                orb
                Text(session.phase.label)
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(HorizonTheme.accentText)
                    .accessibilityIdentifier("conversationPhase")
                transcript
                Spacer(minLength: 0)
                if let error = session.errorMessage { errorNote(error) }
                controls
            }
            .padding(.horizontal, HorizonLayout.section)
            .padding(.bottom, HorizonLayout.section)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .insideHorizonWorld(.reading)
            .navigationTitle("Conversation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { end() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rescue", systemImage: "wind") {
                        session.stop()
                        onOpenRescue()
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("horizonConversationScreen")
        .task {
            guard !hasStarted else { return }
            hasStarted = true
            session.respond = { [context] spoken in await Self.reply(to: spoken, context: context) }
            await session.start(opening: openingLine)
        }
        // Recording must never continue behind a lock screen or another app.
        .onChange(of: scenePhase) { _, phase in if phase != .active { session.stop() } }
        .onDisappear { session.stop() }
    }

    // MARK: - Pieces

    /// One circle that breathes with the room. It grows with input loudness while
    /// listening, holds a slow pulse while the coach talks, and settles while thinking.
    private var orb: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: 210, height: 210)
                .scaleEffect(1 + session.level * 0.30)
            Circle()
                .fill(tint.opacity(0.28))
                .frame(width: 150, height: 150)
                .scaleEffect(1 + session.level * 0.18)
            Circle()
                .fill(tint)
                .frame(width: 96, height: 96)
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
        }
        .animation(.easeOut(duration: 0.12), value: session.level)
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .accessibilityHidden(true)
    }

    private var transcript: some View {
        VStack(spacing: HorizonLayout.control) {
            if !session.liveTranscript.isEmpty {
                Text(session.liveTranscript)
                    .font(HorizonType.body(.title3).weight(.medium))
                    .foregroundStyle(HorizonTheme.primaryText)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .accessibilityLabel("You said: \(session.liveTranscript)")
                    .accessibilityIdentifier("conversationLiveTranscript")
            } else if !session.lastReply.isEmpty {
                Text(session.lastReply)
                    .font(HorizonType.body(.body))
                    .foregroundStyle(HorizonTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Coach said: \(session.lastReply)")
                    .accessibilityIdentifier("conversationReply")
            } else {
                Text("Just talk. Pause when you are done and Coach will answer.")
                    .font(HorizonType.body(.subheadline))
                    .foregroundStyle(HorizonTheme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(minHeight: 120, alignment: .top)
        .animation(.easeInOut(duration: 0.2), value: session.liveTranscript)
    }

    private var controls: some View {
        HStack(spacing: HorizonLayout.content) {
            circleControl(
                symbol: session.isMuted ? "mic.slash.fill" : "mic.fill",
                label: session.isMuted ? "Unmute" : "Mute",
                tint: session.isMuted ? .orange : HorizonTheme.primaryText
            ) { session.toggleMute() }

            Button("I’m done talking") { session.handOverTurn() }
                .font(HorizonType.body(.subheadline).weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, HorizonLayout.section)
                .frame(minHeight: 52)
                .background(HorizonTheme.accent, in: Capsule())
                .opacity(session.phase == .listening ? 1 : 0.4)
                .disabled(session.phase != .listening)
                .accessibilityHint("Ends your turn now instead of waiting for the pause")

            circleControl(symbol: "xmark", label: "End conversation", tint: HorizonTheme.secondaryText) {
                end()
            }
        }
    }

    private func circleControl(symbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(HorizonTheme.surface, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private func errorNote(_ error: String) -> some View {
        Label(error, systemImage: "exclamationmark.triangle")
            .font(HorizonType.body(.caption))
            .foregroundStyle(.orange)
            .multilineTextAlignment(.leading)
            .padding(HorizonLayout.control)
            .background(HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.controlRadius))
    }

    private var tint: Color {
        switch session.phase {
        case .listening: HorizonTheme.accent
        case .speaking: HorizonTheme.plum
        case .thinking: HorizonTheme.forest
        case .idle: HorizonTheme.surface
        }
    }

    private var symbol: String {
        switch session.phase {
        case .listening: "waveform"
        case .speaking: "speaker.wave.2.fill"
        case .thinking: "ellipsis"
        case .idle: "mic"
        }
    }

    private func end() {
        session.stop()
        dismiss()
    }

    // MARK: - Turn handling

    /// Runs one spoken turn: store what was said, ask the coach for a spoken-length reply,
    /// store that too. The conversation lands in the same transcript as the typed chat, so
    /// nothing said out loud is lost when somebody switches back to reading.
    @MainActor
    private static func reply(to spoken: String, context: ModelContext) async -> ConversationSession.Reply {
        let history = recentMessages(context)
        persist(ChatMessage(role: "user", content: spoken), in: context)
        let turns = history.suffix(8).map { ConversationTurn(role: $0.role, content: $0.content) }
        do {
            let response = try await APIClient.shared.coach(
                CoachingRequest(message: spoken, recentContext: turns, style: "voice")
            )
            persist(
                ChatMessage(role: "assistant", content: response.message, isSafetyResponse: response.isSafetyResponse),
                in: context
            )
            return ConversationSession.Reply(text: response.message, isSafetyResponse: response.isSafetyResponse)
        } catch {
            // Say something rather than going silent — a dead pause in a voice call reads
            // as abandonment, which is the opposite of what this screen is for.
            let message = (error as? APIError) == .unauthorized
                ? "I cannot reach the coach right now because this device is not connected. Your progress is still saved here."
                : "I could not reach the coach just then. Let us try again in a moment, or take five slow breaths with me now."
            return ConversationSession.Reply(text: message, isFailure: true)
        }
    }

    @MainActor
    private static func recentMessages(_ context: ModelContext) -> [ChatMessage] {
        var descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 10
        let recent = (try? context.fetch(descriptor)) ?? []
        return recent.reversed()
    }

    @MainActor
    private static func persist(_ message: ChatMessage, in context: ModelContext) {
        context.insert(message)
        try? context.save()
    }
}
